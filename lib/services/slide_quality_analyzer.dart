import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/chart.dart';
import '../models/deck.dart';
import '../models/markdown_validation.dart';
import '../models/question.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../utils/color_contrast.dart';
import '../utils/project_path.dart';
import '../widgets/slides/inline_markdown.dart';
import 'slide_layout_metrics.dart';

part 'parts/slide_quality_analyzer_density.dart';

/// Cached fit-scale per slide, so re-analysing a deck after an edit only
/// re-measures the slide that actually changed. The quality provider re-runs
/// [SlideQualityAnalyzer.analyze] on every deck edit, and a single bullet-slide
/// fit-scale costs several milliseconds of TextPainter layout; for a deck of any
/// size that recomputation dominated the analysis. Editing one slide replaces
/// only that slide's object (see `DeckNotifier.updateSlide`), so the unchanged
/// slides keep their identity and hit this cache. The [Expando] is weak-keyed:
/// entries are collected once a slide is no longer referenced, so the cache
/// never leaks. The key is (slide identity, font); a changed slide is a new
/// object — never a stale hit — and a font change misses via [_FitMemo.font].
final Expando<_FitMemo> _fitScaleCache = Expando<_FitMemo>('slideFitScale');

@visibleForTesting
double memoizedFitScale(Slide slide, String font, double Function() compute) {
  final cached = _fitScaleCache[slide];
  if (cached != null && cached.font == font) return cached.scale;
  final scale = compute();
  _fitScaleCache[slide] = _FitMemo(font, scale);
  return scale;
}

/// Cached per-slide issue list, same weak-keyed identity idea as
/// [_fitScaleCache] but for de volledige per-slide analyse. Die omvat naast de
/// (al gememoiseerde) fit-scale ook `File.existsSync` voor media,
/// `ChartSpec.parse` en regex-scans over bullets — werk dat anders bij elke
/// toetsaanslag voor élke slide opnieuw draait. Een edit vervangt alleen het
/// object van de bewerkte slide, dus ongewijzigde slides hiten deze cache.
/// Kanttekening: of een mediabestand bestaat wordt voor een slide dus pas
/// opnieuw op schijf gecheckt wanneer die slide (of thema/instelling) wijzigt.
final Expando<_SlideIssuesMemo> _slideIssuesCache = Expando<_SlideIssuesMemo>(
  'slideQualityIssues',
);

/// Maximum combined quote + author length before a density warning.
const int kQuoteDensityCharThreshold = 750;

/// Readability guardrails for bullet-heavy slides. The existing fit-scale check
/// catches physical overflow; these thresholds catch slides that still fit but
/// are likely too dense for an audience to read comfortably.
const int kSingleColumnBulletWarningCount = 8;
const int kSingleColumnBulletCriticalCount = 14;

/// Checklists mogen meer regels dragen voor een waarschuwing verschijnt: een
/// af te vinken takenlijst kan een legitiem zakelijk doel dienen waar acht
/// regels te beperkend voor is.
const int kChecklistBulletWarningCount = 12;
const int kTwoColumnBulletWarningCount = 14;
const int kTwoColumnBulletCriticalCount = 22;
const int kSingleColumnWordWarningCount = 90;
const int kSingleColumnWordCriticalCount = 150;
const int kTwoColumnWordWarningCount = 120;
const int kTwoColumnWordCriticalCount = 220;
const int kAverageBulletWordInfoCount = 15;
const int kAverageBulletWordWarningCount = 25;
const int kLongMultiSentenceBulletWordCount = 24;
const int kBulletDisplayLevelWarning = 3;

/// Maximum combined title + subtitle length before a density warning.
const int kTitleDensityCharThreshold = 120;

/// Footer text opacity in slide previews — keep in sync with overlays.dart.
const double kFooterTextAlpha = 0.7;

/// Analyses deck slides for accessibility and readability quality issues.
class SlideQualityAnalyzer {
  /// Minimum acceptable contrast ratio for normal-size text. Defaults to the
  /// WCAG AA threshold ([kWcagAaNormalText] = 4.5); the user can relax it via
  /// settings (e.g. 3.5) when they accept slightly lower contrast. Large text
  /// still uses the lower of this and the WCAG large-text threshold (3.0), and
  /// the hard-error floor stays at [kWcagCriticalBodyText].
  final double minContrastRatio;

  const SlideQualityAnalyzer({this.minContrastRatio = kWcagAaNormalText});

  SlideQualityResult analyze(Deck deck) => analyzeSlides(
    slides: deck.slides,
    theme: deck.themeProfile,
    font: deck.themeProfile.fontFamily,
    projectPath: deck.projectPath,
  );

  SlideQualityResult analyzeSlides({
    required List<Slide> slides,
    required ThemeProfile theme,
    required String font,
    String? projectPath,
  }) {
    final issues = <SlideQualityIssue>[];
    _checkThemeContrast(theme, issues);
    _checkFooterContrast(theme, issues);
    _checkChecklistContrast(theme, slides, issues);
    for (var i = 0; i < slides.length; i++) {
      final slide = slides[i];
      if (slide.skipped) continue;
      issues.addAll(_memoizedSlideIssues(slide, i, theme, font, projectPath));
    }
    return SlideQualityResult(issues);
  }

  List<SlideQualityIssue> _memoizedSlideIssues(
    Slide slide,
    int index,
    ThemeProfile theme,
    String font,
    String? projectPath,
  ) {
    final memo = _slideIssuesCache[slide];
    if (memo != null &&
        identical(memo.theme, theme) &&
        memo.font == font &&
        memo.projectPath == projectPath &&
        memo.minContrastRatio == minContrastRatio) {
      if (memo.index == index) return memo.issues;
      // Slide is verschoven (invoegen/verwijderen elders): alleen de index in
      // de issues herschrijven, de analyse zelf blijft geldig.
      final reindexed = [
        for (final issue in memo.issues)
          SlideQualityIssue(
            slideIndex: index,
            kind: issue.kind,
            category: issue.category,
            severity: issue.severity,
            field: issue.field,
            args: issue.args,
          ),
      ];
      _slideIssuesCache[slide] = memo.withIndex(index, reindexed);
      return reindexed;
    }
    final issues = <SlideQualityIssue>[];
    _checkMediaDescriptions(slide, index, issues);
    _checkSlideContrast(slide, index, theme, issues);
    _checkTextDensity(slide, index, font, issues);
    _checkMissingMedia(slide, index, projectPath, issues);
    // Hangt alleen van de slide-inhoud af, dus veilig per slide te cachen.
    _checkQuestionAnswerable(slide, index, issues);
    _slideIssuesCache[slide] = _SlideIssuesMemo(
      theme: theme,
      font: font,
      projectPath: projectPath,
      minContrastRatio: minContrastRatio,
      index: index,
      issues: issues,
    );
    return issues;
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
      final aaThreshold = largeText
          ? math.min(kWcagAaLargeText, minContrastRatio)
          : minContrastRatio;
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
    addPairIssue(
      label: 'Thema accent',
      foreground: theme.accentColor,
      background: theme.slideBackgroundColor,
      largeText: false,
      field: 'accentColor',
    );
  }

  void _checkFooterContrast(
    ThemeProfile theme,
    List<SlideQualityIssue> issues,
  ) {
    if (theme.footerText.trim().isEmpty && !theme.footerShowPageNumbers) return;

    final ratio = blendedHexContrastRatio(
      theme.textColor,
      theme.slideBackgroundColor,
      foregroundAlpha: kFooterTextAlpha,
    );
    if (ratio == null) return;
    final aaThreshold = minContrastRatio;
    if (ratio >= aaThreshold) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: kDeckWideSlideIndex,
        kind: SlideQualityIssueKind.footerContrast,
        category: SlideQualityCategory.contrast,
        severity: MarkdownValidationSeverity.warning,
        field: 'textColor',
        args: {
          'label': 'Footer-tekst',
          'ratio': ratio.toStringAsFixed(1),
          'threshold': aaThreshold.toStringAsFixed(1),
          'largeText': 'false',
        },
      ),
    );
  }

  void _checkChecklistContrast(
    ThemeProfile theme,
    List<Slide> slides,
    List<SlideQualityIssue> issues,
  ) {
    final usesChecklist = slides.any(
      (slide) =>
          !slide.skipped &&
          (slide.type == SlideType.bullets ||
              slide.type == SlideType.twoBullets ||
              slide.type == SlideType.bulletsImage) &&
          slide.listStyle == ListStyle.checklist,
    );
    if (!usesChecklist) return;
    void addPair({
      required String label,
      required String foreground,
      required String field,
    }) {
      final ratio = hexContrastRatio(foreground, theme.slideBackgroundColor);
      if (ratio == null) return;
      final aaThreshold = minContrastRatio;
      if (ratio >= aaThreshold) return;

      issues.add(
        SlideQualityIssue(
          slideIndex: kDeckWideSlideIndex,
          kind: SlideQualityIssueKind.checklistContrast,
          category: SlideQualityCategory.contrast,
          severity: MarkdownValidationSeverity.warning,
          field: field,
          args: {
            'label': label,
            'ratio': ratio.toStringAsFixed(1),
            'threshold': aaThreshold.toStringAsFixed(1),
            'largeText': 'false',
          },
        ),
      );
    }

    addPair(
      label: 'Checklist (niet aangevinkt)',
      foreground: theme.checklistUncheckedColor,
      field: 'checklistUncheckedColor',
    );
    addPair(
      label: 'Checklist (aangevinkt)',
      foreground: theme.checklistCheckedColor,
      field: 'checklistCheckedColor',
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
      default:
        break;
    }
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
    final aaThreshold = math.min(kWcagAaLargeText, minContrastRatio);
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

  void _checkMediaDescriptions(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    switch (slide.type) {
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
      case SlideType.image:
      case SlideType.twoImages:
      case SlideType.bulletsImage:
      case SlideType.title:
      case SlideType.quote:
      case SlideType.bullets:
      case SlideType.twoBullets:
      case SlideType.section:
      case SlideType.table:
      case SlideType.freeMarkdown:
      case SlideType.code:
      case SlideType.cockpit:
      case SlideType.question:
      case SlideType.timeline:
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

  void _checkMissingMedia(
    Slide slide,
    int index,
    String? projectPath,
    List<SlideQualityIssue> issues,
  ) {
    if (kIsWeb || projectPath == null || projectPath.trim().isEmpty) return;

    void missingFile({
      required String path,
      required String field,
      required String label,
    }) {
      if (path.trim().isEmpty) return;
      final resolved = _resolveAssetPath(path, projectPath);
      if (resolved == null || File(resolved).existsSync()) return;

      issues.add(
        SlideQualityIssue(
          slideIndex: index,
          kind: SlideQualityIssueKind.missingMediaFile,
          category: SlideQualityCategory.altText,
          severity: MarkdownValidationSeverity.warning,
          field: field,
          args: {'label': label, 'path': path},
        ),
      );
    }

    switch (slide.type) {
      case SlideType.image:
      case SlideType.bulletsImage:
        missingFile(
          path: slide.imagePath,
          field: 'imagePath',
          label: 'Afbeelding',
        );
      case SlideType.twoImages:
        missingFile(
          path: slide.imagePath,
          field: 'imagePath',
          label: 'Eerste afbeelding',
        );
        missingFile(
          path: slide.imagePath2,
          field: 'imagePath2',
          label: 'Tweede afbeelding',
        );
      case SlideType.title:
      case SlideType.quote:
        missingFile(
          path: slide.imagePath,
          field: 'imagePath',
          label: 'Achtergrondafbeelding',
        );
      case SlideType.video:
        missingFile(path: slide.videoPath, field: 'videoPath', label: 'Video');
      case SlideType.question:
        missingFile(
          path: slide.imagePath,
          field: 'imagePath',
          label: 'Afbeelding',
        );
      case SlideType.bullets:
      case SlideType.twoBullets:
      case SlideType.section:
      case SlideType.table:
      case SlideType.freeMarkdown:
      case SlideType.code:
      case SlideType.chart:
      case SlideType.cockpit:
      case SlideType.timeline:
        break;
    }
  }

  // Route through the shared containment guard so a crafted deck can't turn the
  // "missing media" check into a file-existence oracle (existsSync) for paths
  // outside the project via absolute or `../` references.
  String? _resolveAssetPath(String path, String? projectPath) =>
      resolveSlideAssetPath(path, projectPath);

  /// Waarschuw voor vraagslides die tijdens het presenteren niet speelbaar
  /// zijn (geen geldige vraagspecificatie), vóórdat de presentator er live
  /// tegenaan loopt.
  void _checkQuestionAnswerable(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    if (slide.type != SlideType.question) return;
    final spec = QuestionSpec.parse(slide.customMarkdown);
    if (spec.isPresentable) return;
    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.questionNotAnswerable,
        category: SlideQualityCategory.content,
        severity: MarkdownValidationSeverity.warning,
        field: 'customMarkdown',
      ),
    );
  }
}

class _BulletText {
  final String text;
  final int level;

  const _BulletText({required this.text, required this.level});
}

/// A memoised fit-scale together with the font it was measured for, so a font
/// change invalidates the cached value without touching the [Expando] key.
class _FitMemo {
  final String font;
  final double scale;

  const _FitMemo(this.font, this.scale);
}

/// Gememoiseerde per-slide issues plus alles waarvan de analyse afhangt, zodat
/// een gewijzigd thema, lettertype, projectpad of contrastdrempel de cache
/// laat missen. [theme] wordt op identiteit vergeleken (immutable model).
class _SlideIssuesMemo {
  final ThemeProfile theme;
  final String font;
  final String? projectPath;
  final double minContrastRatio;
  final int index;
  final List<SlideQualityIssue> issues;

  const _SlideIssuesMemo({
    required this.theme,
    required this.font,
    required this.projectPath,
    required this.minContrastRatio,
    required this.index,
    required this.issues,
  });

  _SlideIssuesMemo withIndex(int newIndex, List<SlideQualityIssue> reindexed) =>
      _SlideIssuesMemo(
        theme: theme,
        font: font,
        projectPath: projectPath,
        minContrastRatio: minContrastRatio,
        index: newIndex,
        issues: reindexed,
      );
}
