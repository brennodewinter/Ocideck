/// One OWASP WSTG test from the Web Security Testing Guide checklist: its stable
/// identifier (e.g. `WSTG-ATHN-07`), the canonical English [title], and the
/// human [category] name it belongs to (also derivable from the id's middle
/// segment, but carried for convenient grouping). Used by [WstgCatalog] to
/// pre-fill a `checklist` slide with the standard's test list.
class WstgTest {
  const WstgTest({
    required this.id,
    required this.title,
    required this.category,
  });

  /// Stable WSTG id, e.g. `WSTG-INPV-05`.
  final String id;

  /// Canonical English test title, e.g. `Testing for SQL Injection`.
  final String title;

  /// Human category name, e.g. `Input Validation Testing`.
  final String category;
}
