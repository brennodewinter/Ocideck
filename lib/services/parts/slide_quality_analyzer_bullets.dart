// Part of the slide_quality_analyzer library — see ../slide_quality_analyzer.dart.
// Split out for navigability (bullet-leesbaarheidschecks); all imports live in
// the main library file. Instance methods relocate verbatim into an extension
// on SlideQualityAnalyzer — same library, same members, no behaviour change.
part of '../slide_quality_analyzer.dart';

extension SlideQualityBulletChecks on SlideQualityAnalyzer {
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
}
