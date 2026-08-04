// Part of the slide_quality_analyzer library — see
// slide_quality_analyzer.dart. Split out for navigability (tekst-dichtheids-
// en leesbaarheidschecks); alle imports staan in het hoofdbestand. Deze
// private methodes verhuizen ongewijzigd naar een extension — zelfde library,
// zelfde members, geen gedragswijziging.
part of '../slide_quality_analyzer.dart';

extension _QualityDensityChecks on SlideQualityAnalyzer {
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
          memoizedFitScale(
            slide,
            font,
            () => bulletsSlideFitScale(slide: slide, font: font),
          ),
        );
        _checkBulletReadability(
          slide: slide,
          index: index,
          issues: issues,
          twoColumn: false,
        );
      case SlideType.tree:
      case SlideType.flow:
      case SlideType.phaseGate:
        _addFitScaleIssue(
          issues,
          index,
          memoizedFitScale(
            slide,
            font,
            () => bulletsSlideFitScale(slide: slide, font: font),
          ),
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
          memoizedFitScale(
            slide,
            font,
            () => twoBulletsSlideFitScale(slide: slide, font: font),
          ),
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
          memoizedFitScale(
            slide,
            font,
            () => bulletsImageSlideFitScale(slide: slide, font: font),
          ),
        );
        _checkBulletReadability(
          slide: slide,
          index: index,
          issues: issues,
          twoColumn: false,
        );
      case SlideType.table:
        issues.addAll(_tableDensityIssues(slide, index, font));
      case SlideType.matrix:
        // Een matrix is een tabel, dus dezelfde dichtheidstoets — maar hij toont
        // een kolom méér dan hij bewaart (de afgeleide RPN). Zonder die
        // meegeteld zou de zwaarste matrix van allemaal, een FMEA van negen
        // kolommen, als achtkoloms worden gekeurd en net onder de klacht blijven.
        issues.addAll(
          _tableDensityIssues(
            slide,
            index,
            font,
            extraColumns: matrixHasDerivedColumn(slide) ? 1 : 0,
          ),
        );
      case SlideType.code:
        _checkCodeDensity(slide, index, issues);
      case SlideType.freeMarkdown:
      case SlideType.canvas:
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
      case SlideType.scorecard:
      case SlideType.assets:
      case SlideType.discoveries:
      case SlideType.finding:
      case SlideType.findingsSummary:
      case SlideType.checklist:
      case SlideType.scopeMatrix:
      case SlideType.controlStatus:
      case SlideType.signOff:
      // Een keuze-menu is een raster van blokken, geen doorlopende tekst; de
      // dichtheids-/fit-scale-heuristieken van bullets slaan er niet op.
      case SlideType.menu:
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
        // A group heading is a section label, not a content bullet, so it must
        // not count toward "too many bullets" or the reading-density metrics.
        .where((b) => b.trimLeft().isNotEmpty && !isGroupHeading(b))
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

  /// De gedeelde tekstgrootte van een split-run is het minimum over de pagina's,
  /// zodat een gesplitste lijst overal even groot staat. Dat is goed zolang de
  /// pagina's bij elkaar horen — maar één overvolle pagina in de reeks trekt alle
  /// andere mee omlaag, en dan meldt de dichtheidscheck niets: die kijkt naar de
  /// eigen tekst van een slide, en die is prima. Precies de slide die te klein
  /// rendert blijft dus stil. Deze pas vult dat gat.
  void _checkSplitRuns(
    List<Slide> slides,
    ThemeProfile theme,
    String font,
    List<SlideQualityIssue> issues,
  ) {
    var i = 0;
    while (i < slides.length) {
      final (start, end) = splitRunRange(slides, i);
      if (end <= start) {
        i++;
        continue;
      }
      final scales = [
        for (var k = start; k <= end; k++)
          _memoizedRunScale(slides[k], theme, font),
      ];
      final drag = splitRunDrag(scales, warningScale: kTextDensityWarningScale);
      if (drag != null) {
        final shared = scales[drag.offender];
        final offenderIndex = start + drag.offender;
        for (final d in drag.dragged) {
          final index = start + d;
          if (slides[index].skipped) continue;
          issues.add(
            SlideQualityIssue(
              slideIndex: index,
              kind: SlideQualityIssueKind.splitRunDragged,
              category: SlideQualityCategory.textDensity,
              severity: shared <= kTextDensityCriticalScale + 0.001
                  ? MarkdownValidationSeverity.error
                  : MarkdownValidationSeverity.warning,
              args: {
                'percent': _percent(shared),
                'own': _percent(scales[d]),
                // Menselijke slidenummers voor de melding, de index voor de fix.
                'page': '${offenderIndex + 1}',
                'offender': '$offenderIndex',
              },
            ),
          );
        }
      }
      i = end + 1;
    }
  }

  double _memoizedRunScale(Slide slide, ThemeProfile theme, String font) {
    final cached = _runScaleCache[slide];
    if (cached != null &&
        cached.font == font &&
        identical(cached.theme, theme)) {
      return cached.scale;
    }
    final scale = splitRunMemberScale(slide, theme, font);
    _runScaleCache[slide] = _RunScaleMemo(font, theme, scale);
    return scale;
  }
}

/// Waarschuwt wanneer de celtekst op het minimumformaat uitkomt — dezelfde
/// inpassing die de render doet, op een referentiedia. Niet meer de
/// dichtheidsformule: die telt rijen en kolommen, terwijl de tabel sinds het
/// verticaal vullen zijn letter uit de hoogte haalt. Achttien kolommen met
/// enkele tekens rendert ruim, en daar hoorde geen "staat op het
/// minimumformaat" bij.
List<SlideQualityIssue> _tableDensityIssues(
  Slide slide,
  int index,
  String font, {
  int extraColumns = 0,
}) {
  final rows = slide.tableRows.where((r) => r.isNotEmpty).toList();
  if (rows.isEmpty) return const [];
  final colCount =
      rows.fold<int>(0, (m, r) => r.length > m ? r.length : m) + extraColumns;
  final w = kReferenceSlideWidth;
  final cellSize = tableFit(
    rows: rows,
    colCount: colCount,
    slideWidth: w,
    tableWidth: tableReferenceWidth(w),
    availH: tableReferenceAvailableHeight(w),
    font: font,
  ).cellSize;
  final minimum = tableCellFontMinimum(w);
  if (cellSize > minimum + 0.001) return const [];

  return [
    SlideQualityIssue(
      slideIndex: index,
      kind: SlideQualityIssueKind.tableDensityMinimum,
      category: SlideQualityCategory.textDensity,
      severity: MarkdownValidationSeverity.warning,
      args: {'rows': '${rows.length}', 'cols': '$colCount'},
    ),
  ];
}
