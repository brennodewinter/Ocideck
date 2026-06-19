import '../models/chart.dart';
import '../models/deck.dart';
import '../models/markdown_validation.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../utils/color_contrast.dart';
import '../widgets/slides/inline_markdown.dart';
import 'slide_layout_metrics.dart';

/// Analyses deck slides for accessibility and readability quality issues.
class SlideQualityAnalyzer {
  const SlideQualityAnalyzer();

  SlideQualityResult analyze(Deck deck) => analyzeSlides(
    slides: deck.slides,
    theme: deck.themeProfile,
    font: deck.themeProfile.fontFamily,
  );

  SlideQualityResult analyzeSlides({
    required List<Slide> slides,
    required ThemeProfile theme,
    required String font,
  }) {
    final issues = <SlideQualityIssue>[];
    _checkThemeContrast(theme, issues);
    for (var i = 0; i < slides.length; i++) {
      final slide = slides[i];
      if (slide.skipped) continue;
      _checkAltText(slide, i, issues);
      _checkSlideContrast(slide, i, theme, issues);
      _checkTextDensity(slide, i, font, issues);
    }
    return SlideQualityResult(issues);
  }

  void _checkThemeContrast(ThemeProfile theme, List<SlideQualityIssue> issues) {
    void addPairIssue({
      required String label,
      required String foreground,
      required String background,
      required bool largeText,
      String? field,
    }) {
      final ratio = hexContrastRatio(foreground, background);
      if (ratio == null) return;
      final aaThreshold = largeText ? kWcagAaLargeText : kWcagAaNormalText;
      if (ratio >= aaThreshold) return;

      final severity = !largeText && ratio < kWcagCriticalBodyText
          ? MarkdownValidationSeverity.error
          : MarkdownValidationSeverity.warning;

      issues.add(
        SlideQualityIssue(
          slideIndex: kDeckWideSlideIndex,
          kind: SlideQualityIssueKind.themeContrast,
          category: SlideQualityCategory.contrast,
          severity: severity,
          field: field,
          args: {
            'label': label,
            'ratio': ratio.toStringAsFixed(1),
            'threshold': aaThreshold.toStringAsFixed(1),
            'largeText': largeText.toString(),
          },
        ),
      );
    }

    addPairIssue(
      label: 'Thema bodytekst',
      foreground: theme.textColor,
      background: theme.slideBackgroundColor,
      largeText: false,
      field: 'textColor',
    );
    addPairIssue(
      label: 'Thema titel',
      foreground: theme.titleTextColor,
      background: theme.titleBackgroundColor,
      largeText: true,
      field: 'titleTextColor',
    );
    addPairIssue(
      label: 'Thema tabeltekst',
      foreground: theme.tableTextColor,
      background: theme.slideBackgroundColor,
      largeText: false,
      field: 'tableTextColor',
    );
    addPairIssue(
      label: 'Thema tabelkop',
      foreground: theme.tableHeaderTextColor,
      background: theme.tableHeaderBackgroundColor,
      largeText: true,
      field: 'tableHeaderTextColor',
    );
    addPairIssue(
      label: 'Thema code',
      foreground: theme.codeTextColor,
      background: theme.codeBackgroundColor,
      largeText: false,
      field: 'codeTextColor',
    );
  }

  void _checkSlideContrast(
    Slide slide,
    int index,
    ThemeProfile theme,
    List<SlideQualityIssue> issues,
  ) {
    switch (slide.type) {
      case SlideType.section:
        _addSlidePairIssue(
          issues: issues,
          slideIndex: index,
          label: 'Tussentitel',
          foreground: theme.titleTextColor,
          background: theme.sectionBackgroundColor,
        );
      case SlideType.title:
        if (slide.imagePath.isNotEmpty) {
          _addImageContrastNote(issues, index);
        }
      case SlideType.quote:
        if (slide.imagePath.isNotEmpty) {
          _addImageContrastNote(issues, index);
        }
      default:
        break;
    }
  }

  void _addImageContrastNote(List<SlideQualityIssue> issues, int index) {
    if (issues.any(
      (i) =>
          i.slideIndex == index &&
          i.kind == SlideQualityIssueKind.imageContrastUnverified,
    )) {
      return;
    }
    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.imageContrastUnverified,
        category: SlideQualityCategory.contrast,
        severity: MarkdownValidationSeverity.warning,
      ),
    );
  }

  void _addSlidePairIssue({
    required List<SlideQualityIssue> issues,
    required int slideIndex,
    required String label,
    required String foreground,
    required String background,
  }) {
    final ratio = hexContrastRatio(foreground, background);
    if (ratio == null) return;
    const aaThreshold = kWcagAaLargeText;
    if (ratio >= aaThreshold) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: slideIndex,
        kind: SlideQualityIssueKind.slideContrast,
        category: SlideQualityCategory.contrast,
        severity: MarkdownValidationSeverity.warning,
        args: {
          'label': label,
          'ratio': ratio.toStringAsFixed(1),
          'threshold': aaThreshold.toStringAsFixed(1),
        },
      ),
    );
  }

  void _checkAltText(Slide slide, int index, List<SlideQualityIssue> issues) {
    void missingCaption({
      required String path,
      required String caption,
      required String field,
      required String label,
    }) {
      if (path.trim().isEmpty || caption.trim().isNotEmpty) return;
      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.missingAltCaption,
          category: SlideQualityCategory.altText,
          severity: MarkdownValidationSeverity.informational,
          field: field,
          args: {'label': label},
        ),
      );
    }

    switch (slide.type) {
      case SlideType.image:
        missingCaption(
          path: slide.imagePath,
          caption: slide.imageCaption,
          field: 'imageCaption',
          label: 'Afbeelding',
        );
      case SlideType.twoImages:
        missingCaption(
          path: slide.imagePath,
          caption: slide.imageCaption,
          field: 'imageCaption',
          label: 'Eerste afbeelding',
        );
        missingCaption(
          path: slide.imagePath2,
          caption: slide.imageCaption2,
          field: 'imageCaption2',
          label: 'Tweede afbeelding',
        );
      case SlideType.bulletsImage:
        missingCaption(
          path: slide.imagePath,
          caption: slide.imageCaption,
          field: 'imageCaption',
          label: 'Afbeelding',
        );
      case SlideType.title:
        if (slide.imagePath.isNotEmpty) {
          missingCaption(
            path: slide.imagePath,
            caption: slide.imageCaption,
            field: 'imageCaption',
            label: 'Achtergrondafbeelding',
          );
        }
      case SlideType.quote:
        if (slide.imagePath.isNotEmpty) {
          missingCaption(
            path: slide.imagePath,
            caption: slide.imageCaption,
            field: 'imageCaption',
            label: 'Achtergrondafbeelding',
          );
        }
      case SlideType.chart:
        _checkChartAltText(slide, index, issues);
      case SlideType.video:
        _checkMediaAltText(
          slide: slide,
          index: index,
          issues: issues,
          hasMedia: slide.videoPath.trim().isNotEmpty,
          label: 'Video',
        );
      case SlideType.bullets:
      case SlideType.twoBullets:
      case SlideType.section:
      case SlideType.table:
      case SlideType.freeMarkdown:
      case SlideType.code:
        break;
    }
  }

  void _checkChartAltText(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    final spec = ChartSpec.parse(slide.customMarkdown);
    if (spec.title.trim().isNotEmpty) return;
    if (spec.hasInlineData &&
        spec.series.any((s) => s.name.trim().isNotEmpty)) {
      return;
    }
    if (spec.source != null && spec.source!.trim().isNotEmpty) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.chartMissingDescription,
        category: SlideQualityCategory.altText,
        severity: MarkdownValidationSeverity.informational,
        field: 'customMarkdown',
      ),
    );
  }

  void _checkMediaAltText({
    required Slide slide,
    required int index,
    required List<SlideQualityIssue> issues,
    required bool hasMedia,
    required String label,
  }) {
    if (!hasMedia) return;
    final hasDescription =
        slide.title.trim().isNotEmpty ||
        slide.notes.trim().isNotEmpty ||
        slide.subtitle.trim().isNotEmpty;
    if (hasDescription) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.mediaMissingDescription,
        category: SlideQualityCategory.altText,
        severity: MarkdownValidationSeverity.informational,
        field: 'title',
        args: {'label': label},
      ),
    );
  }

  void _checkTextDensity(
    Slide slide,
    int index,
    String font,
    List<SlideQualityIssue> issues,
  ) {
    switch (slide.type) {
      case SlideType.bullets:
        _addFitScaleIssue(
          issues,
          index,
          bulletsSlideFitScale(slide: slide, font: font),
        );
      case SlideType.twoBullets:
        _addFitScaleIssue(
          issues,
          index,
          twoBulletsSlideFitScale(slide: slide, font: font),
        );
      case SlideType.bulletsImage:
        _addFitScaleIssue(
          issues,
          index,
          bulletsImageSlideFitScale(slide: slide, font: font),
        );
      case SlideType.table:
        _checkTableDensity(slide, index, issues);
      case SlideType.code:
        _checkCodeDensity(slide, index, issues);
      case SlideType.freeMarkdown:
        _checkFreeMarkdownDensity(slide, index, issues);
      case SlideType.title:
        _checkTitleDensity(slide, index, issues);
      case SlideType.section:
      case SlideType.image:
      case SlideType.twoImages:
      case SlideType.video:
      case SlideType.quote:
      case SlideType.chart:
        break;
    }
  }

  void _addFitScaleIssue(
    List<SlideQualityIssue> issues,
    int index,
    double scale,
  ) {
    if (scale > kTextDensityWarningScale) return;

    final critical = scale <= kTextDensityCriticalScale + 0.001;
    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: critical
            ? SlideQualityIssueKind.textDensityCritical
            : SlideQualityIssueKind.textDensityWarning,
        category: SlideQualityCategory.textDensity,
        severity: critical
            ? MarkdownValidationSeverity.error
            : MarkdownValidationSeverity.warning,
        args: {'percent': _percent(scale)},
      ),
    );
  }

  void _checkTableDensity(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    final rows = slide.tableRows.where((r) => r.isNotEmpty).toList();
    if (rows.isEmpty) return;
    final colCount = rows.fold<int>(0, (m, r) => r.length > m ? r.length : m);
    final w = kReferenceSlideWidth;
    final cellSize = tableCellFontSize(
      w,
      rowCount: rows.length,
      colCount: colCount,
    );
    final minimum = tableCellFontMinimum(w);
    if (cellSize > minimum + 0.001) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.tableDensityMinimum,
        category: SlideQualityCategory.textDensity,
        severity: MarkdownValidationSeverity.warning,
        args: {'rows': '${rows.length}', 'cols': '$colCount'},
      ),
    );
  }

  void _checkCodeDensity(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    final code = slide.customMarkdown;
    if (code.trim().isEmpty) return;
    final lines = code.split('\n');
    if (lines.length <= 28 && code.length <= 1800) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.codeDensityHigh,
        category: SlideQualityCategory.textDensity,
        severity: MarkdownValidationSeverity.warning,
        field: 'customMarkdown',
        args: {'lines': '${lines.length}'},
      ),
    );
  }

  void _checkFreeMarkdownDensity(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    final md = slide.customMarkdown;
    if (md.trim().isEmpty) return;
    final lines = md.split('\n').where((l) => l.trim().isNotEmpty).length;
    if (lines <= 18 && md.length <= 1200) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.freeMarkdownDensityHigh,
        category: SlideQualityCategory.textDensity,
        severity: MarkdownValidationSeverity.warning,
        field: 'customMarkdown',
        args: {'lines': '$lines'},
      ),
    );
  }

  void _checkTitleDensity(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    final titleLen = stripInlineMarkdown(slide.title).length;
    final subtitleLen = stripInlineMarkdown(slide.subtitle).length;
    if (titleLen + subtitleLen <= 120) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.titleDensityHigh,
        category: SlideQualityCategory.textDensity,
        severity: MarkdownValidationSeverity.warning,
        args: {'chars': '${titleLen + subtitleLen}'},
      ),
    );
  }

  String _percent(double scale) => '${(scale * 100).round()}%';
}
