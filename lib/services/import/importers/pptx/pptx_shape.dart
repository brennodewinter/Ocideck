import 'package:xml/xml.dart';

import '../../models/body_block.dart';
import '../../models/source_slide.dart';
import 'pptx_context.dart';
import 'pptx_text.dart';

/// Intermediate representation of a single `p:sp` shape's text.
///
/// Keeps the parsed paragraphs, the text's font size and bounding box so the
/// caller can decide whether this shape is a title, subtitle, body or free
/// positioned text.
class ShapeText {
  const ShapeText({
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

ShapeText? parseShape(XmlElement sp, String? Function(String rId) resolveLink) {
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

  return ShapeText(
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
void resolveTitleAndSubtitle(
  List<ShapeText> candidates,
  StringBuffer title,
  StringBuffer subtitle,
  List<BodyBlock> body,
  List<PositionedText> positioned,
  List<({String text, String url})> links, {
  required int slideHeight,
}) {
  if (candidates.isEmpty) return;

  double score(ShapeText c) {
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

  ShapeText? titleShape;
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
      ShapeText? subtitleShape;
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

String readNotes(PptxContext ctx, String slidePath, Map<String, String> rels) {
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
