/// Constructs that the current rich-text bridge cannot round-trip without
/// changing the author's Markdown source.
///
/// A GFM table is deliberately **absent** here: it round-trips losslessly as an
/// `x-embed-table` block embed (see `MarkdownQuillCodec` / `TableEmbedBuilder`),
/// so it is rendered and editable in the visual editor instead of forcing a
/// fall back to raw Markdown.
enum MarkdownVisualLimitation { rawHtml, escapedPunctuation, footnote }

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
