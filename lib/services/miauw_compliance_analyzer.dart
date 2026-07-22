import '../models/deck.dart';
import '../models/eis_entry.dart';
import '../models/finding_spec.dart';
import '../models/miauw_compliance.dart';
import '../models/slide.dart';
import 'document_integrity.dart';
import 'miauw_eis_catalog.dart';

/// Reads the bundled [MiauwEisCatalog] and produces, per requirement, a
/// [EisStatus] against a deck (PENTEST_MIAUW §9). A **gap analysis, not a gate**:
///
/// - a requirement excluded in `deck.miauwWaivers` is **uitgesloten** (its
///   reason carried through);
/// - an **automatic** requirement is **voldaan** when its content check passes,
///   else **open**;
/// - a **manual** requirement can't be proven from content, so it stays **open**
///   until the client confirms it (a human attestation in `miauwConfirmations`,
///   which reads as **voldaan** while carrying its note) or waives it.
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
      // A manual (organisational) EIS can't be proven from content; it stays
      // open until the client either confirms it (a human attestation) or
      // waives it. Confirmation counts as voldaan but carries its note so the
      // panel/dossier show it was human-attested, not content-verified.
      final note = deck.miauwConfirmations[eis.id];
      return EisResult(
        entry: eis,
        status: note != null ? EisStatus.voldaan : EisStatus.open,
        confirmationNote: note,
      );
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
    // Alleen de koppen. Elke andere consument filtert hier al op
    // ([deckFindingList], de ernstlijst, het gatenoverzicht, de paginabouwer);
    // deze niet, terwijl een `finding`-dia met rol `detail` prima
    // round-trippt — het is een markdown-eerst gereedschap. Zo'n dia levert een
    // lege spec, en dan meldde het nalevingspaneel de eisen 4.7.x als *open*
    // terwijl de bevindingenlijst één complete bevinding zag.
    for (final slide in deck.slides)
      if (slide.type == SlideType.finding &&
          slide.findingRole == FindingRole.header)
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
      // Niet "er stáát een hash" maar "de hash klopt". Dat verschil is het hele
      // punt van de eis: een gemanipuleerd rapport draagt zijn oude hash gewoon
      // mee, en meldde zichzelf daarmee als in orde in het nalevingsoverzicht
      // dat een auditor leest. De controle die daarvoor bestaat werd nergens
      // aangeroepen.
      EisCheck.sealed => deckIntegrityStatus(deck) == IntegrityStatus.intact,
      EisCheck.reportVersion => deck.version.trim().isNotEmpty,
      EisCheck.reportLanguage => deck.language.trim().isNotEmpty,
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
    };
  }
}
