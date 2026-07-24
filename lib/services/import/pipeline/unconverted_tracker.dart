import '../models/conversion_issue.dart';

/// Builds the "not converted" note slides that guarantee losslessness.
///
/// For every source slide with [ConversionIssue]s, the pipeline emits a
/// free-Markdown slide right after it that lists what was not converted and,
/// where relevant, what part was salvaged. So a reader always knows what was
/// dropped — nothing disappears silently.
class UnconvertedTracker {
  /// Build the free-Markdown body for a note slide covering [issues] from
  /// source slide number [sourceSlideNumber] (1-based, user-facing).
  ///
  /// The body is plain Markdown (no front matter, no `_class`) so the writer
  /// can wrap it in a free-Markdown slide. The wording is Dutch for now,
  /// matching OciDeck's source language; it can be localised later by
  /// passing a label function.
  static String buildNoteBody(
    int sourceSlideNumber,
    List<ConversionIssue> issues, {
    String? heading,
  }) {
    final lines = <String>[
      heading ?? '# Niet overgenomen van slide $sourceSlideNumber',
      '',
      for (final issue in issues) _formatIssue(issue),
    ];
    return lines.join('\n');
  }

  /// Build the free-Markdown body for a deck-wide note slide covering
  /// [issues] that are not attributable to a single source slide (e.g. a
  /// whole format whose internals the import cannot parse yet). Appended once at
  /// the end of the deck by the writer.
  static String buildDeckNoteBody(List<ConversionIssue> issues) {
    final lines = <String>[
      '# Niet overgenomen van dit document',
      '',
      for (final issue in issues) _formatIssue(issue),
    ];
    return lines.join('\n');
  }

  /// Whether [issues] contain any non-salvaged loss worth noting.
  static bool hasLoss(List<ConversionIssue> issues) =>
      issues.any((i) => !i.isSalvaged) || issues.isNotEmpty;

  static String _formatIssue(ConversionIssue issue) {
    final feature = _escMarkdown(issue.feature);
    final description = _escMarkdown(issue.description);
    final base = '- $feature: $description';
    if (issue.isSalvaged) {
      return '$base (deels overgenomen: ${_escMarkdown(issue.salvagedAs!)})';
    }
    return base;
  }

  /// Escape HTML and Markdown metacharacters in user-facing issue text.
  ///
  /// `&`, `<` and `>` are turned into HTML entities so a `<!--` or `-->`
  /// inside an issue cannot break the surrounding note slide. Markdown
  /// metacharacters are backslash-escaped and line breaks are collapsed to
  /// spaces so the bullet list stays intact.
  static String _escMarkdown(String s) {
    return s
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\\', '\\\\')
        .replaceAll('*', '\\*')
        .replaceAll('_', '\\_')
        .replaceAll('~', '\\~')
        .replaceAll('|', '\\|')
        .replaceAll('[', '\\[')
        .replaceAll(']', '\\]')
        .replaceAll('\n', ' ');
  }
}
