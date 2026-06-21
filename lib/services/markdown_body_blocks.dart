import 'slide_layout_metrics.dart';

/// One renderable chunk of a rich-text markdown body.
class MarkdownBodyBlock {
  final String markdown;

  const MarkdownBodyBlock(this.markdown);
}

/// Parses [markdown] into blocks (paragraphs, headings, lists, code, math).
List<MarkdownBodyBlock> parseMarkdownBodyBlocks(String markdown) {
  if (markdown.trim().isEmpty) return const [];

  final lines = markdown.split('\n');
  final blocks = <MarkdownBodyBlock>[];
  var i = 0;

  while (i < lines.length) {
    final line = lines[i];

    final fence = RegExp(r'^\s*```(.*)$').firstMatch(line);
    if (fence != null) {
      final chunk = <String>[line];
      i++;
      while (i < lines.length && !RegExp(r'^\s*```\s*$').hasMatch(lines[i])) {
        chunk.add(lines[i]);
        i++;
      }
      if (i < lines.length) {
        chunk.add(lines[i]);
        i++;
      }
      blocks.add(MarkdownBodyBlock(chunk.join('\n')));
      continue;
    }

    if (line.trim() == r'$$') {
      final chunk = <String>[line];
      i++;
      while (i < lines.length && lines[i].trim() != r'$$') {
        chunk.add(lines[i]);
        i++;
      }
      if (i < lines.length) {
        chunk.add(lines[i]);
        i++;
      }
      blocks.add(MarkdownBodyBlock(chunk.join('\n')));
      continue;
    }

    if (RegExp(r'^\s*\$\$(.+)\$\$\s*$').hasMatch(line)) {
      blocks.add(MarkdownBodyBlock(line));
      i++;
      continue;
    }

    if (line.trim().isEmpty) {
      blocks.add(MarkdownBodyBlock(''));
      i++;
      continue;
    }

    final chunk = <String>[line];
    i++;
    while (i < lines.length) {
      final next = lines[i];
      if (next.trim().isEmpty) break;
      if (RegExp(r'^\s*```').hasMatch(next)) break;
      if (next.trim() == r'$$') break;
      if (RegExp(r'^\s*\$\$(.+)\$\$\s*$').hasMatch(next)) break;
      if (next.startsWith('# ')) break;
      if (next.startsWith('## ')) break;
      chunk.add(next);
      i++;
    }
    blocks.add(MarkdownBodyBlock(chunk.join('\n')));
  }

  return blocks;
}

double _measureBlock({
  required MarkdownBodyBlock block,
  required double scale,
  required double contentW,
  required double refW,
  required double bodySize,
  required String font,
}) {
  final lines = block.markdown.split('\n');
  if (lines.length == 1 && lines.single.trim().isEmpty) {
    return refW * 0.01 * scale;
  }

  var height = 0.0;
  for (final line in lines) {
    final fence = RegExp(r'^\s*```(.*)$').firstMatch(line);
    if (fence != null) {
      final codeLines = lines.length > 2 ? lines.length - 2 : 1;
      // Code blocks render at fixed [refW] sizes (not scaled by text scale).
      height +=
          refW * 0.008 * 2 +
          refW * 0.018 * 2 +
          codeLines * refW * 0.02 * 1.3;
      return height;
    }
    if (line.trim() == r'$$' ||
        RegExp(r'^\s*\$\$(.+)\$\$\s*$').hasMatch(line)) {
      height += refW * 0.032 + refW * 0.012 * 2;
      return height;
    }
    if (line.startsWith('# ')) {
      height += measureTextHeight(
        line.substring(2),
        refW * 0.04 * scale,
        contentW,
        bold: true,
        lineHeight: kRichTextBodyLineHeight,
        fontFamily: font,
      );
    } else if (line.startsWith('## ')) {
      height += measureTextHeight(
        line.substring(3),
        refW * 0.03 * scale,
        contentW,
        lineHeight: kRichTextBodyLineHeight,
        fontFamily: font,
      );
    } else if (line.startsWith('- ')) {
      height += measureTextHeight(
        '• ${line.substring(2)}',
        bodySize * scale,
        contentW,
        lineHeight: kRichTextBodyLineHeight,
        fontFamily: font,
      );
    } else if (line.isEmpty) {
      height += refW * 0.01 * scale;
    } else {
      height += measureTextHeight(
        line,
        bodySize * scale,
        contentW,
        lineHeight: kRichTextBodyLineHeight,
        fontFamily: font,
      );
    }
  }
  return height;
}

double measureMarkdownBlocksHeight({
  required List<MarkdownBodyBlock> blocks,
  required double scale,
  required double contentW,
  required double refW,
  required double bodySize,
  required String font,
  double blockGap = 0,
}) {
  if (blocks.isEmpty) return 0;
  var h = 0.0;
  for (var i = 0; i < blocks.length; i++) {
    h += _measureBlock(
      block: blocks[i],
      scale: scale,
      contentW: contentW,
      refW: refW,
      bodySize: bodySize,
      font: font,
    );
    if (i < blocks.length - 1 && blockGap > 0) h += blockGap;
  }
  return h;
}

/// Height of a rich-text markdown body at [scale], wrapping at [contentW].
double markdownBodyHeight({
  required String markdown,
  required double contentW,
  required double refW,
  required double bodySize,
  required String font,
  double scale = 1.0,
}) {
  return measureMarkdownBlocksHeight(
    blocks: parseMarkdownBodyBlocks(markdown),
    scale: scale,
    contentW: contentW,
    refW: refW,
    bodySize: bodySize,
    font: font,
  );
}
