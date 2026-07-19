import 'markdown_validation.dart';

/// Sentinel index for deck-wide issues (theme contrast, etc.).
const int kDeckWideSlideIndex = -1;

enum SlideQualityCategory { altText, contrast, textDensity, content, privacy }

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
  questionNotAnswerable,

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
