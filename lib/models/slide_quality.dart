import 'markdown_validation.dart';

/// Sentinel index for deck-wide issues (theme contrast, etc.).
const int kDeckWideSlideIndex = -1;

enum SlideQualityCategory {
  altText,
  contrast,
  textDensity,
  content,
  privacy,
  improvement,
  callout,
}

enum SlideQualityIssueKind {
  missingAltCaption,
  themeContrast,
  slideContrast,
  footerContrast,
  checklistContrast,
  imageContrastUnverified,
  titleImageContrast,
  chartMissingDescription,
  mediaMissingDescription,
  missingMediaFile,
  externalMediaFile,
  // Deckbreed: het logo van het actieve stijlprofiel wijst naar niets — een
  // verdwenen bestand, een `asset:`-sleutel die niet in de bundel zit, of een
  // `mem:`-logo dat na een herlaad leeg is. De renderlaag laat het logo stil
  // vallen (vertrouwde stijl-config toont nooit een placeholder), dus zonder
  // deze melding staat de gebruiker voor een lege hoek zonder te weten waarom.
  themeLogoMissing,
  // Deckbreed: de dia-achtergrond is donker, maar het logo is lichte inkt
  // zonder donkere variant — het logo is op de dia vrijwel onzichtbaar.
  // Geldt alleen voor eigen logo's; een gebundeld merk-logo kiest automatisch.
  themeLogoDarkMissing,
  textDensityWarning,
  textDensityCritical,
  splitRunDragged,
  tableDensityMinimum,
  codeDensityHigh,
  freeMarkdownDensityHigh,
  titleDensityHigh,
  quoteDensityHigh,
  bulletCountHigh,
  bulletCountCritical,
  bulletWordCountHigh,
  bulletWordCountCritical,
  bulletAverageLengthHigh,
  bulletMultiSentence,
  bulletNestingDeep,
  bulletColumnImbalance,
  questionAnswerCountHigh,
  questionNotAnswerable,
  emptySlide,
  // Non-lineaire navigatie (#1162): een keuze-menublok of een sprong-uit wijst
  // naar een anker dat geen enkele dia meer draagt. De presentator valt dan
  // stil terug op de gewone volgorde — een knop die niets doet, en dat merk je
  // pas op het podium.
  danglingJump,
  findingUnknownSection,

  // ── Privacy (OCIWACHT §2.1) ─────────────────────────────────────────
  // Eén kind per familie, niet één per regel: de regelverzameling groeit naar
  // tientallen en `formatSlideQualityIssue` is een exhaustieve switch. De
  // concrete regel zit in `args['rule']` en wordt los gelokaliseerd.
  privacyIdentifier,
  privacyFinancial,
  privacyContact,
  privacyDigital,
  privacySecret,
  privacySpecialCategory,
  privacyBulk,
  privacyStructural,
  privacyImage,
  privacyImageUnreadable,

  // ── Procesverbetering golden thread ───────────────────────────────────
  improvementOrphanId,
  improvementUnusedId,

  // ── Image callouts (#1824, IMAGE_CALLOUTS.md §2.6) ───────────────────
  // De callout-checker rapporteert vier soorten problemen: ongeldige
  // geometrie (buiten [0,1] of verkeerd aantal componenten), wees-referenties
  // (een (A) in de tekst zonder entry, of een entry zonder (A) in de tekst),
  // dubbele referenties (dezelfde letter twee keer op één dia), en een
  // ontbrekend anker op een dia die callouts draagt (§2.6 binding).
  calloutInvalidGeometry,
  calloutOrphanReference,
  calloutDuplicateReference,
  calloutMissingAnchor,
  // §5: kruisende pijlen in arrow-modus — een quality finding die pins
  // suggereert, omdat kruisende pijlen onleesbaar worden.
  calloutCrossingArrows,
  // #1853: een doel valt buiten de zichtbare band die cover/zoom/focal laat
  // zien. De overlay tekent niets; deze finding meldt het zodat de auteur
  // weet waarom de markering ontbreekt — dezelfde klasse als een afbeelding
  // zonder alt-tekst: gerapporteerd, niet geblokkeerd (§8).
  calloutTargetOutOfView,
}

/// Waar binnen een veld een melding precies zit.
///
/// Bestaat omdat een melding die alleen zegt *dát* er iets is de auteur laat
/// zoeken. De privacyscanner weet de exacte positie al — zonder deze klasse
/// sneuvelde die kennis in de vertaalslag naar het kwaliteitspaneel, en dan
/// staat er "persoonsnaam j…l" bij een slide met veertig regels tekst.
///
/// De tekst zelf zit hier bewust níét in: dat zou de gevonden waarde alsnog
/// buiten de scanner tillen. Zie de kop van `privacy_finding.dart`.
class SlideQualitySpan {
  /// Welk stuk van een samengesteld veld: de zoveelste bullet, de zoveelste
  /// tabelcel. 0 voor een enkelvoudig veld.
  final int fragmentIndex;

  /// Positie binnen dat tekstfragment.
  final int start;
  final int end;

  const SlideQualitySpan({
    required this.start,
    required this.end,
    this.fragmentIndex = 0,
  });

  bool get isEmpty => end <= start;
}

class SlideQualityIssue {
  final int slideIndex;
  final SlideQualityIssueKind kind;
  final SlideQualityCategory category;
  final MarkdownValidationSeverity severity;

  /// Optional hint for UI focus, e.g. `imageCaption` or `textColor`.
  final String? field;

  /// Waar in [field] de melding zit, als we dat weten. Alleen de privacyscanner
  /// levert dit vandaag; de contrast- en dichtheidschecks gaan over een veld als
  /// geheel en laten het leeg.
  final SlideQualitySpan? span;

  /// Structured parameters for localized formatting ([formatSlideQualityIssue]).
  final Map<String, String> args;

  const SlideQualityIssue({
    required this.slideIndex,
    required this.kind,
    required this.category,
    required this.severity,
    this.field,
    this.span,
    this.args = const {},
  });

  bool get isDeckWide => slideIndex == kDeckWideSlideIndex;
}

class SlideQualityResult {
  final List<SlideQualityIssue> issues;

  const SlideQualityResult(this.issues);

  bool get hasIssues => issues.isNotEmpty;

  /// Issues that should block or warn at export time (excludes informational tips).
  bool get hasActionableIssues =>
      issues.any((i) => i.severity != MarkdownValidationSeverity.informational);

  int get errorCount => issues
      .where((i) => i.severity == MarkdownValidationSeverity.error)
      .length;

  int get warningCount => issues
      .where((i) => i.severity == MarkdownValidationSeverity.warning)
      .length;

  int get infoCount => issues
      .where((i) => i.severity == MarkdownValidationSeverity.informational)
      .length;

  List<SlideQualityIssue> get actionableIssues => issues
      .where((i) => i.severity != MarkdownValidationSeverity.informational)
      .toList();

  Iterable<SlideQualityIssue> issuesWithSeverity(
    MarkdownValidationSeverity severity,
  ) => issues.where((i) => i.severity == severity);

  List<SlideQualityIssue> forSlide(int slideIndex) =>
      issues.where((i) => i.slideIndex == slideIndex).toList();

  bool hasCategoryOnSlide(int slideIndex, SlideQualityCategory category) =>
      issues.any((i) => i.slideIndex == slideIndex && i.category == category);

  List<SlideQualityIssue> get deckWideIssues =>
      issues.where((i) => i.isDeckWide).toList();
}
