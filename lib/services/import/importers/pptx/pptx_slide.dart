import 'package:xml/xml.dart';

import '../../models/body_block.dart';
import '../../models/conversion_issue.dart';
import '../../models/source_chart.dart';
import '../../models/source_image.dart';
import '../../models/source_slide.dart';
import '../../models/source_table.dart';
import '../../pipeline/parse_guard.dart';
import 'pptx_chart.dart';
import 'pptx_context.dart';
import 'pptx_media.dart';
import 'pptx_shape.dart';
import 'pptx_table.dart';

/// Parse one `ppt/slides/slideN.xml` into a [SourceSlide].
///
/// This commit handles text (title/subtitle/body bullets), free-form
/// positioned text boxes, hyperlinks, and speaker notes. Images, charts,
/// tables, and video/audio are added in following commits by extending
/// [parseShape].
SourceSlide parseSlide(
  PptxContext ctx,
  int index,
  String slidePath, {
  bool isHidden = false,
  bool isSection = false,
}) {
  final doc = ctx.readXml(slidePath);
  if (doc == null) {
    return _unreadableSlide(ctx, slidePath, index, isHidden, isSection);
  }

  final rels = ctx.relsFor(slidePath);
  String? resolveLink(String rId) => ctx.resolveRel(rels, rId, slidePath);
  final slideHeight = ctx.slideSize?.height ?? 6858000;

  final parts = _SlideParts();
  final spTree = descendantsLocal(doc, 'spTree').firstOrNull;
  if (spTree != null) {
    _readShapeTree(
      spTree,
      ctx,
      rels,
      slidePath,
      index,
      resolveLink,
      parts,
      slideHeight,
    );
  }

  // Title slides created without title/subtitle placeholders still carry the
  // title in the biggest, highest non-placeholder text box.
  resolveTitleAndSubtitle(
    parts.nonPhCandidates,
    parts.title,
    parts.subtitle,
    parts.body,
    parts.positioned,
    parts.links,
    slideHeight: slideHeight,
  );

  // Title placeholders sometimes contain a title and a subtitle separated by a
  // line break (e.g. a hard return in the title box). Split it into the two
  // fields when no separate subtitle was found.
  final titleStr = parts.title.toString().trim();
  final newline = titleStr.indexOf('\n');
  if (newline != -1 && parts.subtitle.isEmpty) {
    parts.title.clear();
    parts.title.write(titleStr.substring(0, newline).trim());
    parts.subtitle.write(titleStr.substring(newline + 1).trim());
  }

  // Embedded/linked media: scan the slide rels for video/audio targets.
  final media = guardParse<Media>(
    sink: parts.parseIssues,
    slideIndex: index,
    component: IssueComponent.media,
    feature: 'Afbeelding of media',
    description: 'kon niet worden gelezen en is overgeslagen',
    logOp: 'PptxImporter: dia ${index + 1} media',
    body: () => scanMedia(ctx, rels, slidePath),
    fallback: const Media(),
  )!;

  final notes =
      guardParse<String>(
        sink: parts.parseIssues,
        slideIndex: index,
        component: IssueComponent.notes,
        feature: 'Sprekersnotities',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'PptxImporter: dia ${index + 1} notities',
        body: () => readNotes(ctx, slidePath, rels),
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
    video: media.video,
    audioFileName: media.audioFileName,
    hyperlinks: parts.links,
    positionedTexts: parts.positioned,
    notes: notes,
    isHidden: isHidden,
    isSection: isSection,
    parseIssues: parts.parseIssues,
  );
}

/// De losse onderdelen die één `p:sld` oplevert, door [_readShapeTree] gevuld.
///
/// Een verzamelaar in plaats van een handvol out-parameters: het houdt
/// [parseSlide] leesbaar en onder de methodelengte-lat, en de shape-lus op één
/// plek (#877).
class _SlideParts {
  final title = StringBuffer();
  final subtitle = StringBuffer();
  final body = <BodyBlock>[];
  final links = <({String text, String url})>[];
  final positioned = <PositionedText>[];
  final images = <SourceImage>[];
  final nonPhCandidates = <ShapeText>[];
  final parseIssues = <ConversionIssue>[];
  SourceChart? chart;
  SourceTable? table;
}

/// Een dia die niet te lezen viel, met het verlies genoteerd (#877).
///
/// Twee gevallen, beide gemeld zodat niets stil verdwijnt: een part dat er wél
/// is maar niet parseert ([IssueCause.malformedXml]), en een part waarnaar de
/// `sldIdLst` verwijst maar dat niet in het archief zit ([IssueCause.missingPart]).
/// De dia houdt zijn index als plek in de reeks; de notitiedia legt uit wat er
/// verdween.
SourceSlide _unreadableSlide(
  PptxContext ctx,
  String slidePath,
  int index,
  bool isHidden,
  bool isSection,
) {
  final present = ctx.readPart(slidePath) != null;
  return SourceSlide(
    index: index,
    isHidden: isHidden,
    isSection: isSection,
    parseIssues: [
      ConversionIssue(
        slideIndex: index,
        component: IssueComponent.slide,
        cause: present ? IssueCause.malformedXml : IssueCause.missingPart,
        feature: 'Dia-inhoud',
        description: present
            ? 'kon niet worden gelezen en is overgeslagen'
            : 'ontbrak in het bestand en is overgeslagen',
      ),
    ],
  );
}

/// Lees de vormen (`p:sp`/`p:pic`/`p:graphicFrame`/`p:grpSp`) van [spTree] in
/// [parts], met per onderdeel een foutgrens (#877): een onleesbaar tekstvak,
/// afbeelding, grafiek of tabel wordt overgeslagen en als verlies genoteerd,
/// de rest blijft. Groepen (`p:grpSp`) worden recursief uitgeklapt — een
/// presentatieauteur groepeert vaak tekstvakken en afbeeldingen, en zonder
/// recursie verdween de hele groep stil.
void _readShapeTree(
  XmlElement spTree,
  PptxContext ctx,
  Map<String, String> rels,
  String slidePath,
  int index,
  String? Function(String rId) resolveLink,
  _SlideParts parts,
  int slideHeight,
) {
  for (final child in spTree.children.whereType<XmlElement>()) {
    switch (child.name.local) {
      case 'grpSp':
        // Recurseer in de groep — de kinderen hebben dezelfde structuur
        // (sp/pic/graphicFrame/grpSp) als de spTree zelf.
        _readShapeTree(
          child,
          ctx,
          rels,
          slidePath,
          index,
          resolveLink,
          parts,
          slideHeight,
        );
      case 'sp':
        // Eén onleesbaar tekstvak mag de rest van de dia niet meesleuren
        // (#877); `break` werd `return;` omdat de body nu een closure is.
        guardParseVoid(
          sink: parts.parseIssues,
          slideIndex: index,
          component: IssueComponent.slide,
          feature: 'Dia-inhoud',
          description: 'kon niet worden gelezen en is overgeslagen',
          logOp: 'PptxImporter: dia ${index + 1} tekstvak',
          body: () => _applyShape(child, resolveLink, parts, slideHeight),
        );
      case 'pic':
        final img = guardParse<SourceImage>(
          sink: parts.parseIssues,
          slideIndex: index,
          component: IssueComponent.media,
          feature: 'Afbeelding of media',
          description: 'kon niet worden gelezen en is overgeslagen',
          logOp: 'PptxImporter: dia ${index + 1} afbeelding',
          body: () => parsePic(child, ctx, rels, slidePath),
        );
        if (img != null) {
          parts.images.add(img);
        } else if (picReferencesMissingMedia(child, ctx, rels, slidePath)) {
          // Er wórdt naar een afbeelding verwezen, maar de bytes ontbreken —
          // geen weggefilterd logo maar echt verlies, dus melden.
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
      case 'graphicFrame':
        parts.chart ??= guardParse<SourceChart>(
          sink: parts.parseIssues,
          slideIndex: index,
          component: IssueComponent.chart,
          feature: 'Grafiek',
          description: 'kon niet worden gelezen en is overgeslagen',
          logOp: 'PptxImporter: dia ${index + 1} grafiek',
          body: () => _parseChart(child, ctx, rels, slidePath),
        );
        parts.table ??= guardParse<SourceTable>(
          sink: parts.parseIssues,
          slideIndex: index,
          component: IssueComponent.table,
          feature: 'Tabel',
          description: 'kon niet worden gelezen en is overgeslagen',
          logOp: 'PptxImporter: dia ${index + 1} tabel',
          body: () => _parseTable(child),
        );
    }
  }
}

/// Verwerk één `p:sp`-tekstvak in [parts] (titel, ondertitel, body of vrije
/// positie). Losgetrokken uit de lus zodat de foutgrens er een closure omheen
/// kan leggen; een kale `return;` slaat dit vak over zonder de dia te breken.
void _applyShape(
  XmlElement child,
  String? Function(String rId) resolveLink,
  _SlideParts parts,
  int slideHeight,
) {
  final shape = parseShape(child, resolveLink);
  if (shape == null) return;
  if (shape.hasPh) {
    if (shape.isTitle) {
      if (parts.title.isEmpty) {
        parts.title.write(shape.text);
      } else {
        parts.title.write(' ${shape.text}');
      }
    } else if (shape.isSubtitle) {
      // Subtitle placeholders at the bottom of the slide are usually footers
      // (presenter info, slide numbers, etc.).
      if (shape.top > slideHeight * 0.75) return;
      if (parts.subtitle.isEmpty) {
        parts.subtitle.write(shape.text);
      } else {
        parts.subtitle.write(' ${shape.text}');
      }
    } else if (!shape.isSkip) {
      parts.body.addAll(shape.blocks);
    }
  } else {
    parts.nonPhCandidates.add(shape);
  }
  parts.links.addAll(shape.links);
}

/// Parse a `p:graphicFrame` whose graphic data is a DrawingML chart into a
/// [SourceChart]. Non-chart graphic frames (tables, SmartArt, ...) return
/// `null` and are handled by other parsers / noted as unconverted.
SourceChart? _parseChart(
  XmlElement graphicFrame,
  PptxContext ctx,
  Map<String, String> rels,
  String slidePath,
) {
  for (final gd in descendantsLocal(graphicFrame, 'graphicData')) {
    final uri = gd.getAttribute('uri') ?? '';
    if (!uri.endsWith('/chart')) continue;
    final chartRef = descendantsLocal(gd, 'chart').firstOrNull;
    final rId = chartRef?.getAttribute('id', namespaceUri: relsNs);
    if (rId == null) return null;
    final chartPath = ctx.resolveRel(rels, rId, slidePath);
    if (chartPath == null) return null;
    final xml = ctx.readPart(chartPath);
    if (xml == null) return null;
    // Geen interne `try/catch` meer: een misvormde grafiek-XML mag opborrelen
    // naar de `guardParse` in [parseSlide], die hem als grafiekverlies noteert
    // (#877). Voorheen werd de fout hier stil ingeslikt en verdween de grafiek
    // zonder een woord.
    return parseChartXml(xml);
  }
  return null;
}

/// Parse a `p:graphicFrame` whose graphic data is a DrawingML table.
SourceTable? _parseTable(XmlElement graphicFrame) {
  for (final gd in descendantsLocal(graphicFrame, 'graphicData')) {
    final uri = gd.getAttribute('uri') ?? '';
    if (!uri.endsWith('/table')) continue;
    final tbl = descendantsLocal(gd, 'tbl').firstOrNull;
    if (tbl == null) return null;
    return parseTableXml(tbl);
  }
  return null;
}
