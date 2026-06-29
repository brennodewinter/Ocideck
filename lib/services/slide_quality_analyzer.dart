import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../models/chart.dart';
import '../models/deck.dart';
import '../models/markdown_validation.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../models/slide_quality.dart';
import '../utils/color_contrast.dart';
import '../utils/project_path.dart';
import '../widgets/slides/inline_markdown.dart';
import 'slide_layout_metrics.dart';

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
      _checkMediaDescriptions(slide, i, issues);
      _checkSlideContrast(slide, i, theme, issues);
      _checkTextDensity(slide, i, font, issues);
      _checkMissingMedia(slide, i, projectPath, issues);
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
        _checkBulletReadability(
          slide: slide,
          index: index,
          issues: issues,
          twoColumn: false,
        );
      case SlideType.twoBullets:
        _addFitScaleIssue(
          issues,
          index,
          twoBulletsSlideFitScale(slide: slide, font: font),
        );
        _checkBulletReadability(
          slide: slide,
          index: index,
          issues: issues,
          twoColumn: true,
        );
      case SlideType.bulletsImage:
        _addFitScaleIssue(
          issues,
          index,
          bulletsImageSlideFitScale(slide: slide, font: font),
        );
        _checkBulletReadability(
          slide: slide,
          index: index,
          issues: issues,
          twoColumn: false,
        );
      case SlideType.table:
        _checkTableDensity(slide, index, issues);
      case SlideType.code:
        _checkCodeDensity(slide, index, issues);
      case SlideType.freeMarkdown:
        _checkFreeMarkdownDensity(slide, index, issues);
      case SlideType.title:
        _checkTitleDensity(slide, index, issues);
      case SlideType.quote:
        _checkQuoteDensity(slide, index, issues);
      case SlideType.section:
      case SlideType.image:
      case SlideType.twoImages:
      case SlideType.video:
      case SlideType.chart:
      case SlideType.cockpit:
      case SlideType.question:
      case SlideType.timeline:
        break;
    }
  }

  void _checkBulletReadability({
    required Slide slide,
    required int index,
    required List<SlideQualityIssue> issues,
    required bool twoColumn,
  }) {
    final left = slide.listStyle == ListStyle.richText
        ? _markdownBulletTexts(slide.customMarkdown)
        : _visibleBulletTexts(slide.bullets, slide.listStyle);
    final right = twoColumn
        ? _visibleBulletTexts(slide.bullets2, slide.listStyle)
        : const <_BulletText>[];
    _checkBulletItemsReadability(
      left: left,
      right: right,
      index: index,
      issues: issues,
      twoColumn: twoColumn,
      listStyle: slide.listStyle,
    );
  }

  void _checkBulletItemsReadability({
    required List<_BulletText> left,
    required List<_BulletText> right,
    required int index,
    required List<SlideQualityIssue> issues,
    required bool twoColumn,
    required ListStyle listStyle,
  }) {
    final all = [...left, ...right];
    if (all.isEmpty) return;

    final bulletCount = all.length;
    // Enkelkoloms checklists krijgen een ruimere drempel (zie
    // [kChecklistBulletWarningCount]); andere lijsten en twee kolommen niet.
    final warningCount = twoColumn
        ? kTwoColumnBulletWarningCount
        : (listStyle == ListStyle.checklist
              ? kChecklistBulletWarningCount
              : kSingleColumnBulletWarningCount);
    final criticalCount = twoColumn
        ? kTwoColumnBulletCriticalCount
        : kSingleColumnBulletCriticalCount;
    if (bulletCount > criticalCount) {
      _addBulletIssue(
        issues,
        index,
        SlideQualityIssueKind.bulletCountCritical,
        MarkdownValidationSeverity.error,
        {'count': '$bulletCount', 'limit': '$criticalCount'},
      );
    } else if (bulletCount > warningCount) {
      _addBulletIssue(
        issues,
        index,
        SlideQualityIssueKind.bulletCountHigh,
        MarkdownValidationSeverity.warning,
        {'count': '$bulletCount', 'limit': '$warningCount'},
      );
    }

    final wordCounts = all.map((b) => _wordCount(b.text)).toList();
    final totalWords = wordCounts.fold<int>(0, (sum, value) => sum + value);
    final warningWords = twoColumn
        ? kTwoColumnWordWarningCount
        : kSingleColumnWordWarningCount;
    final criticalWords = twoColumn
        ? kTwoColumnWordCriticalCount
        : kSingleColumnWordCriticalCount;
    if (totalWords > criticalWords) {
      _addBulletIssue(
        issues,
        index,
        SlideQualityIssueKind.bulletWordCountCritical,
        MarkdownValidationSeverity.error,
        {'words': '$totalWords', 'limit': '$criticalWords'},
      );
    } else if (totalWords > warningWords) {
      _addBulletIssue(
        issues,
        index,
        SlideQualityIssueKind.bulletWordCountHigh,
        MarkdownValidationSeverity.warning,
        {'words': '$totalWords', 'limit': '$warningWords'},
      );
    }

    final averageWords = totalWords / bulletCount;
    if (bulletCount >= 3 && averageWords >= kAverageBulletWordInfoCount) {
      final severity = averageWords >= kAverageBulletWordWarningCount
          ? MarkdownValidationSeverity.warning
          : MarkdownValidationSeverity.informational;
      _addBulletIssue(
        issues,
        index,
        SlideQualityIssueKind.bulletAverageLengthHigh,
        severity,
        {'average': averageWords.round().toString()},
      );
    }

    final multiSentenceBullets = all.where((b) {
      final words = _wordCount(b.text);
      return _sentenceLikeCount(b.text) > 1 &&
          (words >= kLongMultiSentenceBulletWordCount || bulletCount >= 4);
    }).length;
    if (multiSentenceBullets > 0) {
      _addBulletIssue(
        issues,
        index,
        SlideQualityIssueKind.bulletMultiSentence,
        MarkdownValidationSeverity.warning,
        {'count': '$multiSentenceBullets'},
      );
    }

    final maxDisplayLevel = all
        .map((b) => b.level + 1)
        .fold<int>(1, (max, value) => value > max ? value : max);
    if (maxDisplayLevel >= kBulletDisplayLevelWarning) {
      _addBulletIssue(
        issues,
        index,
        SlideQualityIssueKind.bulletNestingDeep,
        MarkdownValidationSeverity.warning,
        {'level': '$maxDisplayLevel'},
      );
    }

    if (twoColumn && left.isNotEmpty && right.isNotEmpty) {
      final leftCount = left.length;
      final rightCount = right.length;
      final larger = leftCount > rightCount ? leftCount : rightCount;
      final smaller = leftCount < rightCount ? leftCount : rightCount;
      if (larger - smaller >= 4 && larger >= smaller * 2) {
        _addBulletIssue(
          issues,
          index,
          SlideQualityIssueKind.bulletColumnImbalance,
          MarkdownValidationSeverity.warning,
          {'left': '$leftCount', 'right': '$rightCount'},
        );
      }
    }
  }

  void _addBulletIssue(
    List<SlideQualityIssue> issues,
    int index,
    SlideQualityIssueKind kind,
    MarkdownValidationSeverity severity,
    Map<String, String> args,
  ) {
    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: kind,
        category: SlideQualityCategory.textDensity,
        severity: severity,
        args: args,
      ),
    );
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
    final markdownBullets = _markdownBulletTexts(md);
    if (markdownBullets.isNotEmpty) {
      _checkBulletItemsReadability(
        left: markdownBullets,
        right: const [],
        index: index,
        issues: issues,
        twoColumn: false,
        // Vrije markdown is geen checklist: gewone enkelkoloms drempel.
        listStyle: ListStyle.bullets,
      );
    }
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
    if (titleLen + subtitleLen <= kTitleDensityCharThreshold) return;

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

  void _checkQuoteDensity(
    Slide slide,
    int index,
    List<SlideQualityIssue> issues,
  ) {
    final quoteLen = stripInlineMarkdown(slide.quote).length;
    final authorLen = stripInlineMarkdown(slide.quoteAuthor).length;
    if (quoteLen + authorLen <= kQuoteDensityCharThreshold) return;

    issues.add(
      SlideQualityIssue(
        slideIndex: index,
        kind: SlideQualityIssueKind.quoteDensityHigh,
        category: SlideQualityCategory.textDensity,
        severity: MarkdownValidationSeverity.warning,
        field: 'quote',
        args: {'chars': '${quoteLen + authorLen}'},
      ),
    );
  }

  List<_BulletText> _visibleBulletTexts(List<String> bullets, ListStyle style) {
    return bullets
        .where((b) => b.trimLeft().isNotEmpty)
        .map((b) {
          final level = bulletLevel(b);
          final text = style == ListStyle.checklist
              ? checklistItemText(b)
              : bulletText(b);
          return _BulletText(text: stripInlineMarkdown(text), level: level);
        })
        .where((b) => b.text.trim().isNotEmpty)
        .toList();
  }

  List<_BulletText> _markdownBulletTexts(String markdown) {
    final bullets = <_BulletText>[];
    final lines = markdown.split('\n');
    final marker = RegExp(r'^(\s*)(?:[-*+•◦▪▫–]|\d+[.)])\s+(.+)$');
    final htmlItem = RegExp(r'<li[^>]*>(.*?)</li>', caseSensitive: false);
    for (final line in lines) {
      for (final item in htmlItem.allMatches(line)) {
        bullets.add(
          _BulletText(text: _cleanInlineText(item.group(1) ?? ''), level: 0),
        );
      }
      final match = marker.firstMatch(line);
      if (match == null) continue;
      final indent = match.group(1) ?? '';
      final raw = match.group(2) ?? '';
      final text = raw.replaceFirst(RegExp(r'^\[[ xX]\]\s*'), '');
      bullets.add(
        _BulletText(
          text: _cleanInlineText(text),
          level: (indent.replaceAll('\t', '  ').length / 2).floor(),
        ),
      );
    }
    return bullets.where((b) => b.text.trim().isNotEmpty).toList();
  }

  String _cleanInlineText(String value) {
    final withoutTags = value.replaceAll(RegExp(r'<[^>]+>'), ' ');
    return stripInlineMarkdown(withoutTags).replaceAll(RegExp(r'\s+'), ' ');
  }

  int _wordCount(String value) {
    return RegExp(
      r"[A-Za-zÀ-ÖØ-öø-ÿ0-9]+(?:[-'][A-Za-zÀ-ÖØ-öø-ÿ0-9]+)*",
    ).allMatches(value).length;
  }

  int _sentenceLikeCount(String value) {
    return RegExp(r'[.!?](?:\s+|$)').allMatches(value).length;
  }

  String _percent(double scale) => '${(scale * 100).round()}%';
}

class _BulletText {
  final String text;
  final int level;

  const _BulletText({required this.text, required this.level});
}
