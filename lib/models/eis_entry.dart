/// The number of testable EIS in the full MIAUW schema (PENTEST_MIAUW §1),
/// parsed from the authoritative workbook. The workbook numbers 92 rows, of
/// which four are part-section headers (modelled by [EisPart]) and one (`4.6`)
/// is an empty number; the remaining 88 are the requirements the overview
/// assesses. It is the denominator the compliance overview reports coverage
/// against, so a reader can never mistake a partial tally for full conformance.
const int kMiauwFullSchemaSize = 88;

/// One of the four parts of the MIAUW requirement schema (PENTEST_MIAUW §1).
enum EisPart {
  algemeen('Algemeen'),
  interacties('Interacties / Plan van aanpak'),
  executie('Executie'),
  rapportage('Rapportage');

  const EisPart(this.dutchLabel);

  /// The Dutch section label (bundled normative content — data, not localised).
  final String dutchLabel;
}

/// Whether an EIS can be checked from the deck's content, or needs a human
/// confirmation (organisational requirements the deck cannot prove).
enum EisDerivation { automatic, manual }

/// The content-derivable checks the [MiauwComplianceAnalyzer] knows how to
/// evaluate against a deck. Manual EIS carry no check. Several requirements may
/// share one check (e.g. the CVSS check backs both 3.2 and 4.7.2).
enum EisCheck {
  /// The deck is finalised/sealed with an integrity hash (1.1).
  sealed,

  /// The deck carries a report version (1.5).
  reportVersion,

  /// A sign-off / truthful-reporting attestation is present (1.6).
  signOff,

  /// A scope matrix (objects × standard) is present (2.2 / 4.4).
  scopeMatrix,

  /// At least one finding is documented (4.2).
  findingsPresent,

  /// A management / findings summary is present (4.3).
  managementSummary,

  /// A timeline slide is present (4.5).
  timeline,

  /// At least one checklist is present (4.13).
  checklistPresent,

  /// Every finding names its scope object (4.7.1).
  everyFindingHasScope,

  /// Every finding carries a CVSS 4.0 score + vector (3.2 / 4.7.2).
  everyFindingHasCvss,

  /// Every finding has a description (4.7.3).
  everyFindingHasDescription,

  /// Every finding has confirmation / reproduction steps (4.7.4).
  everyFindingHasConfirmation,

  /// Every finding states its possible impact (4.7.5).
  everyFindingHasImpact,

  /// Every finding has a recommendation (4.7.6).
  everyFindingHasRecommendation,

  /// Every finding links a CWE weakness (4.7.6).
  everyFindingHasCwe,
}

/// One MIAUW requirement (EIS) from the bundled schema (PENTEST_MIAUW §1/§9).
///
/// The catalog holds the **full** set of testable EIS parsed from the
/// authoritative MIAUW workbook — the always-on offline floor, mirroring the CWE
/// catalog; the provisioned data pack (§6) can carry the same schema. [title] is
/// bundled normative content (data, not localised UI text, §12). [check] is set
/// only for [EisDerivation.automatic] requirements.
class EisEntry {
  const EisEntry({
    required this.id,
    required this.part,
    required this.title,
    required this.derivation,
    this.check,
  }) : assert(
         (derivation == EisDerivation.automatic) == (check != null),
         'automatic EIS need a check; manual EIS must not carry one',
       );

  /// The dotted requirement number, e.g. `1.6` or `4.7.2`.
  final String id;

  final EisPart part;

  /// The Dutch requirement text (bundled data).
  final String title;

  final EisDerivation derivation;

  /// The content check backing an automatic EIS, or null for a manual one.
  final EisCheck? check;
}
