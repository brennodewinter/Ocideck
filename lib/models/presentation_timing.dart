/// Generieke timinginstellingen voor een presentatie.
///
/// Een benoemd formaat, zoals PechaKucha, is een strikt preset bovenop deze
/// velden. Daardoor hoeft de presenter geen formaatnamen te kennen en kan een
/// volgend automatisch formaat dezelfde runtime hergebruiken.
class PresentationTimingConfig {
  const PresentationTimingConfig({
    this.autoplay = false,
    this.slideDuration = Duration.zero,
    this.maxSlides,
    this.requiredSlides,
    this.stopAfterLastSlide = false,
    this.manualAdvance = true,
    this.format,
  });

  const PresentationTimingConfig.pechaKuchaPreset()
    : autoplay = true,
      slideDuration = const Duration(seconds: 20),
      maxSlides = 20,
      requiredSlides = 20,
      stopAfterLastSlide = true,
      manualAdvance = false,
      format = pechaKuchaFormat;

  const PresentationTimingConfig.ignitePreset()
    : autoplay = true,
      slideDuration = const Duration(seconds: 15),
      maxSlides = 20,
      requiredSlides = 20,
      stopAfterLastSlide = true,
      manualAdvance = false,
      format = igniteFormat;

  static const disabled = PresentationTimingConfig();
  static const pechaKuchaFormat = 'pechakucha';
  static const igniteFormat = 'ignite';

  final bool autoplay;
  final Duration slideDuration;
  final int? maxSlides;
  final int? requiredSlides;
  final bool stopAfterLastSlide;
  final bool manualAdvance;

  /// De bekende presetnaam; null voor losse, generieke timinginstellingen.
  final String? format;

  bool get enabled => autoplay && slideDuration > Duration.zero;
  bool get isPechaKucha => format == pechaKuchaFormat;
  bool get isIgnite => format == igniteFormat;
  bool get isTimedPreset => isPechaKucha || isIgnite;
  bool get hasSettings =>
      autoplay ||
      slideDuration > Duration.zero ||
      maxSlides != null ||
      requiredSlides != null ||
      stopAfterLastSlide ||
      !manualAdvance;

  Duration durationForSlides(int slideCount) =>
      slideDuration * slideCount.clamp(0, maxSlides ?? slideCount);

  PresentationTimingValidation validate(int slideCount) {
    final safeCount = slideCount < 0 ? 0 : slideCount;
    final required = requiredSlides;
    final maximum = maxSlides;
    final missing = required == null || safeCount >= required
        ? 0
        : required - safeCount;
    final excess = maximum == null || safeCount <= maximum
        ? 0
        : safeCount - maximum;
    return PresentationTimingValidation(
      slideCount: safeCount,
      requiredSlides: required,
      maxSlides: maximum,
      missingSlides: missing,
      excessSlides: excess,
      currentDuration: slideDuration * safeCount,
      targetDuration: required == null ? null : slideDuration * required,
    );
  }
}

/// Afgeleide, presentatie-onafhankelijke validatie voor live feedback.
class PresentationTimingValidation {
  const PresentationTimingValidation({
    required this.slideCount,
    required this.requiredSlides,
    required this.maxSlides,
    required this.missingSlides,
    required this.excessSlides,
    required this.currentDuration,
    required this.targetDuration,
  });

  final int slideCount;
  final int? requiredSlides;
  final int? maxSlides;
  final int missingSlides;
  final int excessSlides;
  final Duration currentDuration;
  final Duration? targetDuration;

  bool get isValid => missingSlides == 0 && excessSlides == 0;
}
