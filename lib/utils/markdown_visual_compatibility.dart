/// Constructs that the current rich-text bridge cannot round-trip without
/// changing the author's Markdown source.
enum MarkdownVisualLimitation { table, rawHtml, escapedPunctuation, footnote }

Set<MarkdownVisualLimitation> markdownVisualLimitations(String markdown) {
  final limitations = <MarkdownVisualLimitation>{};
  final lines = markdown.split('\n');
  var fenced = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    if (RegExp(r'^\s*\|?.+\|.+\|?\s*$').hasMatch(line) &&
        index + 1 < lines.length &&
        RegExp(r'^\s*\|?\s*:?-{3,}:?').hasMatch(lines[index + 1])) {
      limitations.add(MarkdownVisualLimitation.table);
    }
    if (RegExp(r'<!--|</?[A-Za-z][^>]*>').hasMatch(line)) {
      limitations.add(MarkdownVisualLimitation.rawHtml);
    }
    if (RegExp(r'\\[\\`*{}\[\]()#+.!_>-]').hasMatch(line)) {
      limitations.add(MarkdownVisualLimitation.escapedPunctuation);
    }
    if (RegExp(r'^\s*\[\^[^\]]+\]:|\[\^[^\]]+\]').hasMatch(line)) {
      limitations.add(MarkdownVisualLimitation.footnote);
    }
  }
  return limitations;
}
