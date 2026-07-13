import '../models/checklist_spec.dart';
import '../models/deck.dart';
import '../models/findings_summary_spec.dart';
import '../models/scope_matrix_spec.dart';
import '../models/slide.dart';

/// Management-summary derivation (PENTEST_MIAUW §10.3 / 4.3.2 / 4.3.5): the
/// management overview **regenerates from the deck**, so it is consistent by
/// construction — findings per severity band plus the "standards used" overview
/// and the scope-coverage totals, all read from the findings, scope matrix and
/// checklists present. No storage: it is always derived on demand.

/// The distinct test standards applied in the deck, in first-seen order: the
/// standard bound to each scope object's type (WSTG / PTES / MASTG / …) plus each
/// checklist's standard label. Empty labels are skipped.
List<String> deckStandardsUsed(Deck deck) {
  final standards = <String>[];
  void add(String s) {
    final v = s.trim();
    if (v.isNotEmpty && !standards.contains(v)) standards.add(v);
  }

  for (final slide in deck.slides) {
    switch (slide.type) {
      case SlideType.scopeMatrix:
        for (final row in ScopeMatrixSpec.fromSlide(
          slide.title,
          slide.tableRows,
        ).rows) {
          add(row.standard);
        }
      case SlideType.checklist:
        add(
          ChecklistSpec.fromSlide(slide.title, slide.tableRows).standardLabel,
        );
      default:
        break;
    }
  }
  return standards;
}

/// The derived management summary of a deck.
class ManagementSummary {
  const ManagementSummary({
    required this.severities,
    required this.standards,
    required this.scopeObjectCount,
    required this.scopeTestedCount,
    required this.resolvedCount,
  });

  /// Findings per CVSS severity band (with a derived total).
  final FindingsSummarySpec severities;

  /// The distinct test standards used (see [deckStandardsUsed]).
  final List<String> standards;

  /// Number of scope objects across all scope-matrix slides.
  final int scopeObjectCount;

  /// How many of those scope objects have a coverage status other than
  /// "not tested".
  final int scopeTestedCount;

  /// How many findings were resolved after retest (hertest).
  final int resolvedCount;

  /// Total number of findings (derived from [severities]).
  int get findingCount => severities.total;
}

/// Derive the full management summary from [deck] (PENTEST_MIAUW §10.3).
ManagementSummary deckManagementSummary(Deck deck) {
  final resolved = deckRetestResolvedCount(deck.slides);
  final severities = FindingsSummarySpec.fromSeverities(
    '',
    deckFindingSeverities(deck.slides),
    resolved: resolved,
  );
  var objects = 0;
  var tested = 0;
  for (final slide in deck.slides) {
    if (slide.type != SlideType.scopeMatrix) continue;
    final spec = ScopeMatrixSpec.fromSlide(slide.title, slide.tableRows);
    objects += spec.total;
    tested += spec.testedCount;
  }
  return ManagementSummary(
    severities: severities,
    standards: deckStandardsUsed(deck),
    scopeObjectCount: objects,
    scopeTestedCount: tested,
    resolvedCount: resolved,
  );
}
