/// One weakness from the offline CWE catalog ([CweCatalog]) — a curated,
/// pentest-relevant subset of MITRE CWE (PENTEST_MIAUW §6/§10.6). Each entry
/// carries the canonical id + name plus a short, English **deterministic**
/// snippet (a neutral description + a remediation skeleton) that the finding
/// editor can pre-fill without an LLM; the tester then specialises it for the
/// engagement. This content is bundled reference *data*, not localised UI text
/// (§12), and always links back to the canonical MITRE definition page.
class CweEntry {
  const CweEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.recommendation,
  });

  /// The numeric CWE id (e.g. `89` for CWE-89).
  final int id;

  /// The canonical MITRE weakness name.
  final String name;

  /// A concise, neutral description of the weakness (the snippet floor).
  final String description;

  /// A remediation skeleton the tester tailors to the concrete finding.
  final String recommendation;

  /// The canonical MITRE definition page for this weakness.
  String get url => 'https://cwe.mitre.org/data/definitions/$id.html';

  /// The `CWE-89 — Name` label the finding editor's CWE field expects.
  String get label => 'CWE-$id — $name';

  /// Lower-cased haystack for [CweCatalog.search]: the id in both bare (`89`)
  /// and prefixed (`cwe-89`) form plus the name and description, so a tester can
  /// find an entry by number or by keyword ("sql", "xss", "traversal").
  String get searchText =>
      'cwe-$id $id ${name.toLowerCase()} ${description.toLowerCase()}';
}
