import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../../models/body_block.dart';
import '../../models/conversion_issue.dart';
import '../../models/source_chart.dart';
import '../../models/source_image.dart';
import '../../models/source_slide.dart';
import '../../models/source_table.dart';
import '../../models/source_video.dart';
import '../../pipeline/parse_guard.dart';
import 'pptx_chart.dart';
import 'pptx_context.dart';
import 'pptx_table.dart';
import 'pptx_text.dart';

/// Intermediate representation of a single `p:sp` shape's text.
///
/// Keeps the parsed paragraphs, the text's font size and bounding box so the
/// caller can decide whether this shape is a title, subtitle, body or free
/// positioned text.
class _ShapeText {
  const _ShapeText({
    required this.blocks,
    required this.text,
    required this.links,
    required this.phType,
    required this.hasPh,
    required this.maxFontSize,
    required this.top,
    required this.left,
    required this.width,
    required this.height,
  });

  final List<BodyBlock> blocks;
  final String text;
  final List<({String text, String url})> links;
  final String phType;
  final bool hasPh;
  final int maxFontSize;
  final double top;
  final double left;
  final double width;
  final double height;

  bool get isTitle => hasPh && (phType == 'title' || phType == 'ctrTitle');

  bool get isSubtitle => hasPh && phType == 'subTitle';

  /// Placeholders that are not content (date, footer, slide number, etc.).
  bool get isSkip =>
      hasPh &&
      const {
        'dt',
        'ftr',
        'sldNum',
        'hdr',
        'sldImg',
        'chart',
        'tbl',
        'media',
        'clipArt',
        'dgm',
      }.contains(phType);
}

/// Parse one `ppt/slides/slideN.xml` into a [SourceSlide].
///
/// This commit handles text (title/subtitle/body bullets), free-form
/// positioned text boxes, hyperlinks, and speaker notes. Images, charts,
/// tables, and video/audio are added in following commits by extending
/// [_parseShape].
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
  _resolveTitleAndSubtitle(
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
  final media = guardParse<_Media>(
    sink: parts.parseIssues,
    slideIndex: index,
    component: IssueComponent.media,
    feature: 'Afbeelding of media',
    description: 'kon niet worden gelezen en is overgeslagen',
    logOp: 'PptxImporter: dia ${index + 1} media',
    body: () => _scanMedia(ctx, rels, slidePath),
    fallback: const _Media(),
  )!;

  final notes =
      guardParse<String>(
        sink: parts.parseIssues,
        slideIndex: index,
        component: IssueComponent.notes,
        feature: 'Sprekersnotities',
        description: 'kon niet worden gelezen en is overgeslagen',
        logOp: 'PptxImporter: dia ${index + 1} notities',
        body: () => _readNotes(ctx, slidePath, rels),
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
  final nonPhCandidates = <_ShapeText>[];
  final parseIssues = <ConversionIssue>[];
  SourceChart? chart;
  SourceTable? table;
}

/// Onderscheid het onschuldige van het echte verlies (#877): een ontbrekend
/// slide-part levert een lege dia, maar een part dat er wél is en niet parseert
/// is verlies dat op de notitiedia hoort — anders verdwijnt de hele dia-inhoud
/// stil.
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
    parseIssues: present
        ? [
            ConversionIssue(
              slideIndex: index,
              component: IssueComponent.slide,
              cause: IssueCause.malformedXml,
              feature: 'Dia-inhoud',
              description: 'kon niet worden gelezen en is overgeslagen',
            ),
          ]
        : const [],
  );
}

/// Lees de vormen (`p:sp`/`p:pic`/`p:graphicFrame`) van [spTree] in [parts],
/// met per onderdeel een foutgrens (#877): een onleesbaar tekstvak, afbeelding,
/// grafiek of tabel wordt overgeslagen en als verlies genoteerd, de rest blijft.
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
          body: () => _parsePic(child, ctx, rels, slidePath),
        );
        if (img != null) {
          parts.images.add(img);
        } else if (_picReferencesMissingMedia(child, ctx, rels, slidePath)) {
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
  final shape = _parseShape(child, resolveLink);
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

/// True wanneer [pic] wél naar een ingesloten afbeelding verwijst maar de bytes
/// ontbreken — echt verlies, geen weggefilterd logo (dat draagt zijn bytes wél).
///
/// [_parsePic] geeft ook `null` terug voor een te klein logo of een `pic` zonder
/// blip; dat is géén verlies. Alleen een aanwezige `r:embed`-verwijzing zonder
/// leesbare bytes telt als een ontbrekend media-onderdeel (#877).
bool _picReferencesMissingMedia(
  XmlElement pic,
  PptxContext ctx,
  Map<String, String> rels,
  String slidePath,
) {
  final blip = descendantsLocal(pic, 'blip').firstOrNull;
  if (blip == null) return false;
  final rId = blip.getAttribute('embed', namespaceUri: relsNs);
  if (rId == null) return false;
  return ctx.readRelBytes(rels, rId, slidePath) == null;
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

const _videoExts = {
  'mp4',
  'mov',
  'avi',
  'mkv',
  'webm',
  'm4v',
  'wmv',
  'mpg',
  'mpeg',
};
const _audioExts = {'mp3', 'wav', 'aac', 'm4a', 'ogg', 'wma', 'flac'};

class _Media {
  const _Media({this.video, this.audioFileName});
  final SourceVideo? video;
  final String? audioFileName;
}

/// Scan the slide's relationships for embedded or linked video/audio media.
///
/// The first video target wins (OciDeck has one video per slide); an audio
/// target is recorded as a file name for the note slide (OciDeck has no audio
/// slide). Embedded bytes are carried so the writer can copy them to
/// `media/`; `http(s)` targets become URL videos.
_Media _scanMedia(PptxContext ctx, Map<String, String> rels, String slidePath) {
  SourceVideo? video;
  String? audio;
  for (final entry in rels.entries) {
    final resolved = ctx.resolveRel(rels, entry.key, slidePath);
    if (resolved == null) continue;
    final ext = _extFromPath(resolved);
    if (video == null && _videoExts.contains(ext)) {
      video = _videoFor(ctx, entry.key, resolved, slidePath, rels);
    } else if (audio == null && _audioExts.contains(ext)) {
      audio = p.url.basename(resolved);
    }
  }
  return _Media(video: video, audioFileName: audio);
}

SourceVideo _videoFor(
  PptxContext ctx,
  String rId,
  String resolved,
  String slidePath,
  Map<String, String> rels,
) {
  final name = p.url.basename(resolved);
  // External link (r:link) -> URL video.
  final linkTarget = _linkTarget(ctx, rels, rId, slidePath);
  if (linkTarget != null &&
      (linkTarget.startsWith('http://') || linkTarget.startsWith('https://'))) {
    final kind = linkTarget.contains('youtu') || linkTarget.contains('youtube')
        ? SourceVideoKind.youtube
        : (linkTarget.contains('vimeo.com')
              ? SourceVideoKind.vimeo
              : SourceVideoKind.url);
    return SourceVideo(kind: kind, ref: linkTarget);
  }
  // Embedded -> copy bytes to media/<name> via the writer.
  final bytes = ctx.readPartBytes(resolved);
  return SourceVideo(
    kind: SourceVideoKind.local,
    ref: 'media/$name',
    bytes: bytes == null ? null : Uint8List.fromList(bytes),
  );
}

/// Look up an `r:link` target for [rId] (external videos are linked, not
/// embedded). Returns `null` when the relationship is embed-only.
String? _linkTarget(
  PptxContext ctx,
  Map<String, String> rels,
  String rId,
  String slidePath,
) {
  // The rels map already holds the target; for external links it is an
  // absolute URL (Targets that start with http are stored verbatim). Resolve
  // defensively: if it doesn't look like a path inside the package, return it
  // as-is.
  final target = rels[rId];
  if (target == null) return null;
  if (target.startsWith('http://') || target.startsWith('https://')) {
    return target;
  }
  return null;
}

/// Parse a `p:pic` picture shape into a [SourceImage] by following its
/// `a:blip` `r:embed` to the media part. Linked-only pictures (`r:link`)
/// are dropped for now (M2) — the bytes are not in the package.
///
/// Very small images (logos, footer icons) are ignored so they don't take
/// over a slide layout.
SourceImage? _parsePic(
  XmlElement pic,
  PptxContext ctx,
  Map<String, String> rels,
  String slidePath,
) {
  final blip = descendantsLocal(pic, 'blip').firstOrNull;
  if (blip == null) return null;
  final rId = blip.getAttribute('embed', namespaceUri: relsNs);
  if (rId == null) return null;

  // Skip small logos/footer icons.
  final spPr = descendantsLocal(pic, 'spPr').firstOrNull;
  final xfrm = spPr != null ? childLocal(spPr, 'xfrm') : null;
  final ext = xfrm != null ? childLocal(xfrm, 'ext') : null;
  if (ext != null && !_isSignificantImageSize(ext, ctx.slideSize)) {
    return null;
  }

  final bytes = ctx.readRelBytes(rels, rId, slidePath);
  if (bytes == null) return null;
  final resolved = ctx.resolveRel(rels, rId, slidePath) ?? '';
  final name = descendantsLocal(pic, 'cNvPr').firstOrNull?.getAttribute('name');
  return SourceImage(
    bytes: Uint8List.fromList(bytes),
    ext: _extFromPath(resolved),
    name: name ?? p.url.basename(resolved),
  );
}

/// Returns true when the picture occupies at least ~3% of the slide area or
/// at least one side is 25% of the slide, to avoid logos being promoted to
/// full slide images.
bool _isSignificantImageSize(
  XmlElement ext,
  ({int width, int height})? slideSize,
) {
  if (slideSize == null) return true;
  final cx = int.tryParse(ext.getAttribute('cx') ?? '') ?? 0;
  final cy = int.tryParse(ext.getAttribute('cy') ?? '') ?? 0;
  if (cx <= 0 || cy <= 0) return true;

  final widthFraction = cx / slideSize.width;
  final heightFraction = cy / slideSize.height;
  final areaFraction = widthFraction * heightFraction;

  return areaFraction >= 0.03 ||
      widthFraction >= 0.25 ||
      heightFraction >= 0.25;
}

String _extFromPath(String path) {
  final dot = path.lastIndexOf('.');
  if (dot < 0) return 'png';
  final ext = path.substring(dot + 1).toLowerCase();
  return ext.isEmpty ? 'png' : ext;
}

_ShapeText? _parseShape(
  XmlElement sp,
  String? Function(String rId) resolveLink,
) {
  final ph = descendantsLocal(sp, 'ph').firstOrNull;
  final phType = ph?.getAttribute('type') ?? 'body';
  final txBody = descendantsLocal(sp, 'txBody').firstOrNull;
  if (txBody == null) return null;

  final isTitle = phType == 'title' || phType == 'ctrTitle';
  final isSubtitle = phType == 'subTitle' || phType == 'dt' || phType == 'ftr';
  // Only body placeholders auto-bullet; free text boxes (no ph) do not.
  final defaultBullet = ph != null && !isTitle && !isSubtitle;
  final parsed = parseTxBody(
    txBody,
    defaultBullet: defaultBullet,
    resolveLink: resolveLink,
  );

  if (parsed.blocks.isEmpty) return null;

  final off = descendantsLocal(sp, 'off').firstOrNull;
  final ext = descendantsLocal(sp, 'ext').firstOrNull;
  final text = parsed.blocks.map((b) => b.text).join(' ').trim();

  return _ShapeText(
    blocks: parsed.blocks,
    text: text,
    links: parsed.links,
    phType: phType,
    hasPh: ph != null,
    maxFontSize: parsed.maxFontSize,
    top: _emuToDouble(off?.getAttribute('y')),
    left: _emuToDouble(off?.getAttribute('x')),
    width: _emuToDouble(ext?.getAttribute('cx')),
    height: _emuToDouble(ext?.getAttribute('cy')),
  );
}

/// Converts an EMU string to a double, defaulting to `0` when missing.
double _emuToDouble(String? emu) {
  final v = int.tryParse(emu ?? '');
  return v == null ? 0 : v.toDouble();
}

/// Picks title and subtitle from free text boxes when no placeholder is used.
///
/// Title/subtitle candidates are scored by font size and vertical position
/// (higher and larger wins), while digit-only labels and footer text are
/// ignored for those roles. Everything else stays in the body and is recorded
/// as positioned text.
void _resolveTitleAndSubtitle(
  List<_ShapeText> candidates,
  StringBuffer title,
  StringBuffer subtitle,
  List<BodyBlock> body,
  List<PositionedText> positioned,
  List<({String text, String url})> links, {
  required int slideHeight,
}) {
  if (candidates.isEmpty) return;

  double score(_ShapeText c) {
    // Prefer large text near the top of the slide. The top penalty is tuned
    // so a large mid-slide label like "01" does not beat the actual title.
    final topPenalty = c.top * 1000 / slideHeight;
    return c.maxFontSize - topPenalty;
  }

  bool isDigitLabel(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return true;
    return RegExp(r'^[\d\s\/\.\-]+$').hasMatch(trimmed);
  }

  // Filter out labels like "01", "02", "2 / 22" from title/subtitle.
  final selectable = candidates.where((c) => !isDigitLabel(c.text)).toList();

  _ShapeText? titleShape;
  if (title.isEmpty && selectable.isNotEmpty) {
    selectable.sort((a, b) => score(b).compareTo(score(a)));
    titleShape = selectable.removeAt(0);
    candidates.remove(titleShape);
    title.write(titleShape.text);
  } else if (title.isEmpty) {
    // All candidates are digit labels; fall back to the first one.
    titleShape = candidates.removeAt(0);
    title.write(titleShape.text);
  } else {
    titleShape = candidates.isNotEmpty ? candidates.first : null;
  }

  if (subtitle.isEmpty && titleShape != null) {
    // The subtitle is the best remaining candidate below the title but not
    // pushed into the footer/slide-number area, and not the first item of a
    // list of items that starts directly under the title.
    final subtitleThreshold = slideHeight * 0.75;
    final nearRegion = slideHeight * 0.25;
    final belowTitle = selectable
        .where((c) => c.top > titleShape!.top && c.top < subtitleThreshold)
        .toList();
    if (belowTitle.isNotEmpty) {
      final near = belowTitle
          .where((c) => c.top < titleShape!.top + nearRegion)
          .toList();
      _ShapeText? subtitleShape;
      if (near.length == 1) {
        // A single candidate directly under the title is the subtitle.
        subtitleShape = near.single;
      } else if (near.isEmpty) {
        // The subtitle is lower; pick the highest candidate below the title.
        belowTitle.sort((a, b) => a.top.compareTo(b.top));
        subtitleShape = belowTitle.first;
      } else {
        // Multiple candidates cluster under the title: this is a bulleted list,
        // not a subtitle.
      }
      if (subtitleShape != null) {
        candidates.remove(subtitleShape);
        subtitle.write(subtitleShape.text);
      }
    }
  }

  // The remaining shapes are body/free-form text. If a title is already
  // known, drop shapes that are purely in the footer/bottom area.
  final footerThreshold = slideHeight * 0.85;
  for (final c in candidates) {
    if (title.isNotEmpty && c.top > footerThreshold) continue;
    body.addAll(c.blocks);
    if (c.width > 0 && c.height > 0) {
      positioned.add(
        PositionedText(
          text: c.blocks.map((b) => b.text).join('\n'),
          left: _emuToNorm(c.left.toStringAsFixed(0)),
          top: _emuToNorm(c.top.toStringAsFixed(0)),
          width: _emuToNorm(c.width.toStringAsFixed(0)),
          height: _emuToNorm(c.height.toStringAsFixed(0)),
        ),
      );
    }
    links.addAll(c.links);
  }
}

String _readNotes(PptxContext ctx, String slidePath, Map<String, String> rels) {
  // The notes slide is referenced by a relationship of type .../notesSlide.
  String? notesPath;
  for (final entry in rels.entries) {
    if (entry.value.contains('notesSlides/')) {
      notesPath = ctx.resolveRel(rels, entry.key, slidePath);
      break;
    }
  }
  if (notesPath == null) return '';
  final doc = ctx.readXml(notesPath);
  if (doc == null) return '';
  final buf = StringBuffer();
  for (final txBody in descendantsLocal(doc, 'txBody')) {
    final ph = txBody.parentElement;
    final phType = descendantsLocal(
      ph ?? txBody,
      'ph',
    ).firstOrNull?.getAttribute('type');
    if (phType == 'sldNum' || phType == 'dt' || phType == 'ftr') continue;
    final parsed = parseTxBody(
      txBody,
      defaultBullet: false,
      resolveLink: (_) => null,
    );
    for (final b in parsed.blocks) {
      if (buf.isNotEmpty) buf.write('\n');
      buf.write(b.text);
    }
  }
  return buf.toString().trim();
}

double _emuToNorm(String? emu) {
  final v = int.tryParse(emu ?? '');
  if (v == null) return 0;
  // EMU per slide side: 9144000 (width) / 6858000 (height) at 16:9. Use the
  // width as the normaliser for x/width and height for y/height.
  return v / 9144000.0;
}
