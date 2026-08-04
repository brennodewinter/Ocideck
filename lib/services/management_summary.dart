import '../models/checklist_spec.dart';
import '../models/deck.dart';
import '../models/findings_summary_spec.dart';
import '../models/scope_matrix_spec.dart';
import '../models/slide.dart';
import 'scope_coverage.dart' show normalizeScopeObject;

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
      // Uitgeschreven: een `default:` zou een nieuw type dat óók een norm draagt
      // stilzwijgend uit de managementsamenvatting laten vallen.
      case SlideType.title ||
          SlideType.section ||
          SlideType.bullets ||
          SlideType.menu ||
          SlideType.twoBullets ||
          SlideType.bulletsImage ||
          SlideType.twoImages ||
          SlideType.image ||
          SlideType.video ||
          SlideType.quote ||
          SlideType.table ||
          SlideType.freeMarkdown ||
          SlideType.code ||
          SlideType.chart ||
          SlideType.cockpit ||
          SlideType.question ||
          SlideType.timeline ||
          SlideType.scorecard ||
          SlideType.assets ||
          SlideType.discoveries ||
          SlideType.finding ||
          SlideType.findingsSummary ||
          SlideType.signOff ||
          // Een matrix draagt een verbetersjabloon, geen toetsnorm.
          SlideType.matrix ||
          SlideType.canvas ||
          SlideType.tree ||
          SlideType.flow ||
          SlideType.phaseGate ||
          // controlStatus draagt de ISO-norm in de front matter, niet als
          // pentest-toetsnorm; de ISO-voortgang heeft een eigen analyzer.
          SlideType.controlStatus:
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
  // Per object tellen, niet per rij.
  //
  // De ruwe rijaantallen werden opgeteld over alle scopematrices, dus een object
  // dat op twee dia's staat — een planningsmatrix en een uitvoeringsmatrix is een
  // gewone opzet — telde dubbel. Het gatenoverzicht ontdubbelt wél, dus twee
  // weergaven van hetzelfde deck noemden een ander totaal: "3 / 5 getest" naast
  // een lijst die van vier objecten uitging.
  //
  // Getest wint van niet-getest: is hetzelfde object érgens afgevinkt, dan telt
  // het één keer als getest.
  final statuses = <String, bool>{};
  for (final slide in deck.slides) {
    if (slide.type != SlideType.scopeMatrix) continue;
    final spec = ScopeMatrixSpec.fromSlide(slide.title, slide.tableRows);
    for (final row in spec.rows) {
      final key = normalizeScopeObject(row.object);
      if (key.isEmpty) continue;
      statuses[key] = (statuses[key] ?? false) || row.status.isTested;
    }
  }
  final objects = statuses.length;
  final tested = statuses.values.where((t) => t).length;
  return ManagementSummary(
    severities: severities,
    standards: deckStandardsUsed(deck),
    scopeObjectCount: objects,
    scopeTestedCount: tested,
    resolvedCount: resolved,
  );
}
