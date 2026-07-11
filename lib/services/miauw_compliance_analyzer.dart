import '../models/deck.dart';
import '../models/eis_entry.dart';
import '../models/finding_spec.dart';
import '../models/miauw_compliance.dart';
import '../models/slide.dart';
import 'miauw_eis_catalog.dart';

/// Reads the bundled [MiauwEisCatalog] and produces, per requirement, a
/// [EisStatus] against a deck (PENTEST_MIAUW §9). A **gap analysis, not a gate**:
///
/// - a requirement excluded in `deck.miauwWaivers` is **uitgesloten** (its
///   reason carried through);
/// - an **automatic** requirement is **voldaan** when its content check passes,
///   else **open**;
/// - a **manual** requirement can't be proven from content, so it stays **open**
///   until the client waives it (a manual-confirmation state is later work).
///
/// Modelled on `SlideQualityAnalyzer`: a `const` service with a single pure
/// [analyze] entry point, so the provider recomputes cheaply on every deck edit.
class MiauwComplianceAnalyzer {
  const MiauwComplianceAnalyzer();

  MiauwComplianceResult analyze(Deck deck) {
    final findings = _findingSpecs(deck);
    final results = <EisResult>[
      for (final eis in MiauwEisCatalog.instance.entries)
        _evaluate(eis, deck, findings),
    ];
    return MiauwComplianceResult(results);
  }

  EisResult _evaluate(EisEntry eis, Deck deck, List<FindingSpec> findings) {
    final reason = deck.miauwWaivers[eis.id];
    if (reason != null) {
      return EisResult(
        entry: eis,
        status: EisStatus.uitgesloten,
        waiverReason: reason,
      );
    }
    if (eis.derivation == EisDerivation.manual) {
      return EisResult(entry: eis, status: EisStatus.open);
    }
    final met = _check(eis.check!, deck, findings);
    return EisResult(
      entry: eis,
      status: met ? EisStatus.voldaan : EisStatus.open,
    );
  }

  /// The parsed structured header of every `finding` slide (the group headers;
  /// detail/evidence slides carry no [FindingSpec]).
  List<FindingSpec> _findingSpecs(Deck deck) => [
    for (final slide in deck.slides)
      if (slide.type == SlideType.finding)
        FindingSpec.parse(slide.customMarkdown),
  ];

  bool _hasSlide(Deck deck, SlideType type) =>
      deck.slides.any((s) => s.type == type);

  /// Whether every finding satisfies [test]; false when there are no findings at
  /// all (an empty report can't satisfy the per-finding requirements — 4.2 flags
  /// the missing findings, and the client can waive if that is intentional).
  bool _everyFinding(
    List<FindingSpec> findings,
    bool Function(FindingSpec) test,
  ) => findings.isNotEmpty && findings.every(test);

  bool _check(EisCheck check, Deck deck, List<FindingSpec> findings) {
    return switch (check) {
      EisCheck.sealed => deck.finalized && deck.sealHash.trim().isNotEmpty,
      EisCheck.reportVersion => deck.version.trim().isNotEmpty,
      EisCheck.signOff =>
        _hasSlide(deck, SlideType.signOff) || deck.signature != null,
      EisCheck.scopeMatrix => _hasSlide(deck, SlideType.scopeMatrix),
      EisCheck.managementSummary => _hasSlide(deck, SlideType.findingsSummary),
      EisCheck.timeline => _hasSlide(deck, SlideType.timeline),
      EisCheck.checklistPresent => _hasSlide(deck, SlideType.checklist),
      EisCheck.findingsPresent => findings.isNotEmpty,
      EisCheck.everyFindingHasScope => _everyFinding(
        findings,
        (f) => f.scopeObject.trim().isNotEmpty,
      ),
      EisCheck.everyFindingHasCvss => _everyFinding(
        findings,
        (f) => f.cvss != null,
      ),
      EisCheck.everyFindingHasDescription => _everyFinding(
        findings,
        (f) => f.description.trim().isNotEmpty,
      ),
      EisCheck.everyFindingHasConfirmation => _everyFinding(
        findings,
        (f) => f.confirmation.trim().isNotEmpty,
      ),
      EisCheck.everyFindingHasImpact => _everyFinding(
        findings,
        (f) => f.impact.trim().isNotEmpty,
      ),
      EisCheck.everyFindingHasRecommendation => _everyFinding(
        findings,
        (f) => f.recommendation.trim().isNotEmpty,
      ),
      EisCheck.everyFindingHasCwe => _everyFinding(
        findings,
        (f) => f.cweId != null,
      ),
    };
  }
}
