import 'dart:typed_data';
import 'dart:math' as math;

import 'package:xml/xml.dart';

import '../../../../utils/image_resize.dart';
import '../../models/body_block.dart';
import '../../models/conversion_issue.dart';
import '../../models/source_chart.dart';
import '../../models/source_image.dart';
import '../../models/source_slide.dart';
import '../../models/source_table.dart';
import '../../pipeline/parse_guard.dart';
import 'odp_chart.dart';
import 'odp_context.dart';
import 'odp_table.dart';
import 'odp_text.dart';

/// Parse one `<draw:page>` into a [SourceSlide].
///
/// This commit handles text frames (title/subtitle/body via
/// `presentation:class`, free text boxes as positioned text), images, and
/// speaker notes. Tables and charts are added in the next commit.
/// Frame classes that carry no meaningful slide content.
const _skipClasses = {
  'notes',
  'date',
  'footer',
  'header',
  'page-number',
  'page',
  'graphic',
  'chart',
  'object',
  'image',
  'table',
  'clipart',
  'orgchart',
  'diagram',
};

SourceSlide parsePage(
  OdpContext ctx,
  int index,
  XmlElement page, {
  bool isHidden = false,
}) {
  final (pageW, pageH) = ctx.pageSize(page);

  final parts = _PageParts();
  _readFrames(ctx, index, page, pageW, pageH, parts);

  final notes =
      guardParse<String>(
        sink: parts.parseIssues,
        slideIndex: index,
        component: IssueComponent.notes,
        feature: 'Sprekersnotities',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'OdpImporter: dia ${index + 1} notities',
        body: () => _readNotes(ctx, page),
      ) ??
      '';

  return SourceSlide(
    index: index,
    title: parts.title.toString().trim(),
    subtitle: parts.subtitle.toString().trim(),
    bodyBlocks: parts.body,
    images: parts.images,
    chart: parts.chart,
    table: parts.table,
    hyperlinks: parts.links,
    positionedTexts: parts.positioned,
    notes: notes,
    isHidden: isHidden,
    parseIssues: parts.parseIssues,
  );
}

/// De losse onderdelen die één `draw:page` oplevert, door [_readFrames] gevuld.
/// Een verzamelaar in plaats van out-parameters, zodat [parsePage] leesbaar en
/// onder de methodelengte-lat blijft (#877).
class _PageParts {
  final title = StringBuffer();
  final subtitle = StringBuffer();
  final body = <BodyBlock>[];
  final links = <({String text, String url})>[];
  final positioned = <PositionedText>[];
  final images = <SourceImage>[];
  final parseIssues = <ConversionIssue>[];
  SourceTable? table;
  SourceChart? chart;
}

/// Lees de directe `draw:frame`-kinderen van [page] in [parts], met per frame
/// een foutgrens (#877): een onleesbaar tekstvak, afbeelding, tabel of grafiek
/// wordt overgeslagen en genoteerd, de rest van de dia blijft.
void _readFrames(
  OdpContext ctx,
  int index,
  XmlElement page,
  double pageW,
  double pageH,
  _PageParts parts,
) {
  // Only consider direct child frames and groups; this avoids speaker notes
  // and animation nodes that are also descendants of the page. Groepen
  // (`draw:g`) worden recursief uitgeklapt — een presentatieauteur groepeert
  // vaak tekstvakken en afbeeldingen, en zonder recursie verdween de hele
  // groep stil.
  for (final frame in page.children.whereType<XmlElement>()) {
    if (frame.name.local == 'g') {
      _readFrames(ctx, index, frame, pageW, pageH, parts);
      continue;
    }
    if (frame.name.local != 'frame') continue;

    final presClass = _attr(frame, 'class');
    if (presClass != null && _skipClasses.contains(presClass)) continue;

    final textBox = descendantsLocal(frame, 'text-box').firstOrNull;
    if (textBox != null) {
      // Isoleer een onleesbaar tekstvak tot dit frame (#877); de rest van de dia
      // en de volgende dia's blijven intact.
      final parsed = guardParse<OdpParsedText>(
        sink: parts.parseIssues,
        slideIndex: index,
        component: IssueComponent.slide,
        feature: 'Dia-inhoud',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'OdpImporter: dia ${index + 1} tekstvak',
        body: () => parseTextBox(textBox),
      );
      if (parsed == null || parsed.blocks.isEmpty) continue;
      _applyTextFrame(frame, parsed, presClass, pageW, pageH, parts);
      continue;
    }

    final img = descendantsLocal(frame, 'image').firstOrNull;
    if (img != null) {
      final source = guardParse<SourceImage>(
        sink: parts.parseIssues,
        slideIndex: index,
        component: IssueComponent.media,
        feature: 'Afbeelding of media',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'OdpImporter: dia ${index + 1} afbeelding',
        body: () => _imageFromHref(ctx, img, frame),
      );
      if (source != null) {
        parts.images.add(source);
      } else if (_imageHrefMissing(ctx, img)) {
        parts.parseIssues.add(
          ConversionIssue(
            slideIndex: index,
            component: IssueComponent.media,
            cause: IssueCause.missingPart,
            feature: 'Afbeelding of media',
            description: 'ontbrak in het bestand en is overgeslagen',
          ),
        );
      }
      continue;
    }

    final tbl = descendantsLocal(frame, 'table').firstOrNull;
    if (tbl != null) {
      parts.table ??= guardParse<SourceTable>(
        sink: parts.parseIssues,
        slideIndex: index,
        component: IssueComponent.table,
        feature: 'Tabel',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'OdpImporter: dia ${index + 1} tabel',
        body: () => parseOdpTable(tbl),
      );
      continue;
    }

    // A draw:object xlink:href -> ObjectCharts/N is a chart sub-document.
    final obj = descendantsLocal(frame, 'object').firstOrNull;
    if (obj != null) {
      parts.chart ??= guardParse<SourceChart>(
        sink: parts.parseIssues,
        slideIndex: index,
        component: IssueComponent.chart,
        feature: 'Grafiek',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'OdpImporter: dia ${index + 1} grafiek',
        body: () => _chartFromObject(ctx, obj),
      );
    }
  }
}

/// Plaats de tekst van één `draw:text-box`-frame op titel, ondertitel, body of
/// vrije positie in [parts], volgens `presentation:class` en de verticale plek.
void _applyTextFrame(
  XmlElement frame,
  OdpParsedText parsed,
  String? presClass,
  double pageW,
  double pageH,
  _PageParts parts,
) {
  final text = parsed.blocks.map((b) => b.text).join(' ').trim();
  final top = _cm(_attr(frame, 'y'));
  if (top > pageH * 0.85) return; // footer

  if (presClass == 'title') {
    if (parts.title.isEmpty) {
      parts.title.write(text);
    } else {
      parts.title.write(' $text');
    }
  } else if (presClass == 'subtitle') {
    if (parts.subtitle.isEmpty) {
      parts.subtitle.write(text);
    } else {
      parts.subtitle.write(' $text');
    }
  } else if (presClass == 'outline' ||
      (presClass == null &&
          (parts.title.isNotEmpty || top >= pageH * 0.5 || text.isEmpty))) {
    parts.body.addAll(parsed.blocks);
    if (presClass == null && text.isNotEmpty) {
      parts.positioned.add(_positionedText(frame, text, pageW, pageH));
    }
  } else if (presClass == null && parts.title.isEmpty && top < pageH * 0.5) {
    // Free-form text box at the top of the title slide: split the first
    // paragraph(s) into title and subtitle.
    for (var i = 0; i < parsed.blocks.length; i++) {
      final block = parsed.blocks[i];
      if (i == 0) {
        parts.title.write(block.text);
      } else if (i == 1) {
        parts.subtitle.write(block.text);
      } else {
        parts.body.add(block);
      }
    }
  }
  parts.links.addAll(parsed.links);
}

/// True wanneer een `<draw:image>` naar een bestand verwijst dat niet in het
/// archief zit — echt verlies dat gemeld moet worden (#877). Een `image` zónder
/// href telt niet: dan is er niets om te missen.
bool _imageHrefMissing(OdpContext ctx, XmlElement img) {
  final href = xlinkHref(img);
  if (href == null) return false;
  return ctx.readPartBytes(ctx.resolveHref(href)) == null;
}

/// Resolve a `<draw:object>` chart reference to its `content.xml` and parse
/// it. Non-chart objects (e.g. embedded OLE) return `null`.
SourceChart? _chartFromObject(OdpContext ctx, XmlElement obj) {
  final href = xlinkHref(obj);
  if (href == null) return null;
  final base = ctx.resolveHref(href);
  final xml = ctx.readPart('$base/content.xml');
  if (xml == null) return null;
  return parseOdpChartXml(xml);
}

SourceImage? _imageFromHref(OdpContext ctx, XmlElement img, XmlElement frame) {
  final href = xlinkHref(img);
  if (href == null) return null;
  final path = ctx.resolveHref(href);
  final bytes = ctx.readPartBytes(path);
  if (bytes == null) return null;
  final imageBytes = Uint8List.fromList(bytes);

  // Bak wat Impress met de afbeelding doet in de bytes, net als de
  // PPTX-importer: OciDeck zet hem zonder eigen geometrie op de dia.
  final geometry = _geometry(ctx, frame, imageBytes);
  return SourceImage(
    bytes: geometry.isIdentity
        ? imageBytes
        : bakeImportGeometry(imageBytes, geometry, path),
    ext: _extFromPath(path),
    name: path.split('/').last,
  );
}

/// De geometrie die Impress op [frame] legt: de draaiing uit `draw:transform`
/// op het frame zelf, het spiegelen en bijsnijden uit zijn grafische stijl.
///
/// ODF telt zijn rotatie tegen de klok in (getoetst tegen wat LibreOffice zelf
/// rendert) en `bakeImportGeometry` met de klok mee — vandaar het minteken.
ImportImageGeometry _geometry(
  OdpContext ctx,
  XmlElement frame,
  Uint8List bytes,
) {
  final props = ctx.graphicProperties(_drawStyleName(frame));
  final mirror = (props == null ? null : _attr(props, 'mirror')) ?? '';
  return ImportImageGeometry(
    crop: _clipCrop(props, bytes),
    // `horizontal` spiegelt om de verticale as, en de varianten
    // `horizontal-on-odd`/`-on-even` doen dat afhankelijk van het paginanummer
    // — een onderscheid dat een dia niet kent, dus die spiegelen gewoon mee.
    flipHorizontal: mirror.contains('horizontal'),
    flipVertical: mirror.contains('vertical'),
    clockwiseDegrees: -_rotationFromTransform(_attr(frame, 'transform')),
  );
}

/// De uitsnede uit `fo:clip="rect(boven, rechts, onder, links)"`.
///
/// ODF meet die vier lengtes af tegen de natuurlijke afmeting van de
/// afbeelding — het pixelformaat gedeeld door haar eigen resolutie — en niet
/// tegen het kader waarin ze staat. Zonder die maat valt de uitsnede niet te
/// duiden, en dan snijden we liever niets weg.
ImportCrop? _clipCrop(XmlElement? props, Uint8List bytes) {
  final clip = props == null ? null : _attr(props, 'clip');
  if (clip == null) return null;
  final rect = RegExp(r'rect\s*\(([^)]*)\)').firstMatch(clip);
  if (rect == null) return null;
  final sides = rect
      .group(1)!
      .split(RegExp(r'[,\s]+'))
      .where((s) => s.isNotEmpty)
      .toList();
  if (sides.length != 4) return null;
  final natural = imageNaturalSizeCm(bytes);
  if (natural == null) return null;
  return importCrop(
    top: _lengthCm(sides[0]) / natural.height,
    right: _lengthCm(sides[1]) / natural.width,
    bottom: _lengthCm(sides[2]) / natural.height,
    left: _lengthCm(sides[3]) / natural.width,
  );
}

/// De `draw:style-name` van [frame]. Een frame draagt vaak ook een
/// `presentation:style-name`; alleen de eerste wijst naar de grafische stijl
/// waarin het spiegelen en bijsnijden staat.
String? _drawStyleName(XmlElement frame) {
  for (final a in frame.attributes) {
    if (a.name.local == 'style-name' && a.name.prefix == 'draw') {
      return a.value;
    }
  }
  return null;
}

/// Lees een ODF-lengte in centimeters.
///
/// LibreOffice schrijft cm, maar de norm staat elke XSL-eenheid toe — en juist
/// bij `fo:clip` is het verschil tussen millimeters en centimeters het verschil
/// tussen een nette uitsnede en een weggesneden afbeelding. Een waarde zonder
/// eenheid, `auto` of iets onbekends levert 0 op: dan valt die zijde weg uit de
/// uitsnede in plaats van er een verzonnen maat op los te laten.
double _lengthCm(String value) {
  final match = RegExp(r'^(-?[\d.]+)([a-z]*)$').firstMatch(value.trim());
  if (match == null) return 0;
  final number = double.tryParse(match.group(1)!) ?? 0;
  return switch (match.group(2)) {
    'cm' || '' => number,
    'mm' => number / 10,
    'in' => number * 2.54,
    'pt' => number * 2.54 / 72,
    'pc' => number * 2.54 / 6,
    // ODF's pixel is een schermpixel; LibreOffice rekent hem als 1/96 inch.
    'px' => number * 2.54 / 96,
    _ => 0,
  };
}

/// Parse `draw:transform="rotate (<radialen>)"` en return graden, of 0.
double _rotationFromTransform(String? transform) {
  if (transform == null) return 0;
  final match = RegExp(r'rotate\s*\(\s*([-\d.]+)\s*\)').firstMatch(transform);
  if (match == null) return 0;
  final radians = double.tryParse(match.group(1)!);
  if (radians == null) return 0;
  return radians * 180 / math.pi;
}

PositionedText _positionedText(
  XmlElement frame,
  String text,
  double pageW,
  double pageH,
) {
  return PositionedText(
    text: text,
    left: _cm(_attr(frame, 'x')) / pageW,
    top: _cm(_attr(frame, 'y')) / pageH,
    width: _cm(_attr(frame, 'width')) / pageW,
    height: _cm(_attr(frame, 'height')) / pageH,
  );
}

String _readNotes(OdpContext ctx, XmlElement page) {
  final buf = StringBuffer();
  for (final notes in descendantsLocal(page, 'notes')) {
    for (final textBox in descendantsLocal(notes, 'text-box')) {
      final parsed = parseTextBox(textBox);
      for (final b in parsed.blocks) {
        if (buf.isNotEmpty) buf.write('\n');
        buf.write(b.text);
      }
    }
  }
  return buf.toString().trim();
}

double _cm(String? value) {
  if (value == null) return 0;
  final num = double.tryParse(value.replaceAll(RegExp(r'[a-z%]'), '')) ?? 0;
  return num;
}

String _extFromPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return 'png';
  final ext = path.substring(dot + 1).toLowerCase();
  return ext.isEmpty ? 'png' : ext;
}

String? _attr(XmlElement el, String local) {
  for (final a in el.attributes) {
    if (a.name.local == local) return a.value;
  }
  return null;
}
