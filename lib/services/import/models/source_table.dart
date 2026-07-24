/// A table extracted from a source slide.
///
/// Carries the raw grid of cells. Merged cells, per-cell colours and borders
/// are not representable in OciDeck's GFM tables (FILE_FORMAT §5, `table`):
/// the classifier records them as a [ConversionIssue] instead so nothing is
/// lost silently.
class SourceTable {
  const SourceTable({required this.header, required this.rows});

  /// First row, treated as the GFM header by OciDeck.
  final List<String> header;

  /// Data rows; each row's cell count should match [header].
  final List<List<String>> rows;
}
