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

class SlideQualityIssue {
  final int slideIndex;
  final SlideQualityIssueKind kind;
  final SlideQualityCategory category;
  final MarkdownValidationSeverity severity;

  /// Optional hint for UI focus, e.g. `imageCaption` or `textColor`.
  final String? field;

  /// Structured parameters for localized formatting ([formatSlideQualityIssue]).
  final Map<String, String> args;

  const SlideQualityIssue({
    required this.slideIndex,
    required this.kind,
    required this.category,
    required this.severity,
    this.field,
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
