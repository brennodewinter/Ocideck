import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/chart.dart';
import '../../models/deck.dart';
import '../../models/display_window_spec.dart';
import '../../models/openkat/openkat_models.dart';
import '../../models/slide.dart';
import 'openkat_aggregator.dart';

/// Builds an OciDeck management deck from parsed OpenKAT data.
///
/// The generator is idempotent: the same inputs produce the same slide ids, so
/// calling it repeatedly and merging the output preserves any manual slides
/// outside the OpenKAT group.
class OpenKatDeckGenerator {
  final OpenKatAggregator aggregator;

  const OpenKatDeckGenerator({this.aggregator = const OpenKatAggregator()});

  /// Generates a fresh deck from the scanned organisations.
  Deck generate(
    List<OpenKatOrganization> organizations, {
    String title = 'OpenKAT managementoverzicht',
    String? outputPath,
  }) {
    final portfolio = aggregator.aggregatePortfolio(organizations);
    final slides = <Slide>[
      _titleSlide(title, organizations),
      _portfolioSummarySlide(portfolio),
      _topIssuesSlide(portfolio),
      _longestOpenSlide(portfolio),
      _trendSlide(portfolio),
      for (final org in organizations) ..._organisationSlides(org),
    ];

    return Deck(
      title: title,
      projectPath: outputPath ?? '',
      version: '1.0',
    ).copyWith(slides: slides);
  }

  /// Replaces OpenKAT-generated slides in [existing] while preserving manual
  /// slides. Stable ids make this idempotent.
  Deck update(Deck existing, List<OpenKatOrganization> organizations) {
    final fresh = generate(organizations, title: existing.title);
    final manualSlides = existing.slides.where(_isManualSlide).toList();
    final freshIds = fresh.slides.map((s) => s.id).toSet();
    final keptManual = manualSlides.where((s) => !freshIds.contains(s.id)).toList();
    return existing.copyWith(slides: [...fresh.slides, ...keptManual]);
  }

  bool _isManualSlide(Slide slide) =>
      !slide.notes.contains('<!-- ocideck_openkat_view:');

  Slide _slide({
    required String id,
    required SlideType type,
    String title = '',
    String subtitle = '',
    List<String> bullets = const [],
    List<List<String>> tableRows = const [],
    String customMarkdown = '',
    DisplayWindowSpec? viewLimit,
    String notes = '',
  }) =>
      Slide(
        id: id,
        type: type,
        title: title,
        subtitle: subtitle,
        bullets: bullets,
        tableRows: tableRows,
        customMarkdown: customMarkdown,
        viewLimit: viewLimit,
        notes: notes,
      );

  Slide _titleSlide(String title, List<OpenKatOrganization> organizations) {
    final orgNames = organizations.map((o) => o.name).join(', ');
    return _slide(
      id: _id('openkat-title'),
      type: SlideType.title,
      title: title,
      subtitle: 'Organisaties: $orgNames',
      notes: '<!-- ocideck_openkat_view: title -->',
    );
  }

  Slide _portfolioSummarySlide(PortfolioAggregate portfolio) {
    final c = portfolio.current;
    return _slide(
      id: _id('openkat-portfolio-summary'),
      type: SlideType.bullets,
      title: 'Portfolio-samenvatting',
      bullets: [
        '${c.totalSystems} systemen',
        '${c.hostnames} hostnames, ${c.ipv4} IPv4, ${c.ipv6} IPv6',
        '${c.totalFindings} findings in ${c.uniqueFindingTypes} types',
        '${c.affectedSystems} getroffen systemen',
        '${c.criticalHighSystems} systemen met critical/high',
        'Critical: ${c.severityCounts['critical']}, High: ${c.severityCounts['high']}, Medium: ${c.severityCounts['medium']}, Low: ${c.severityCounts['low']}',
      ],
      viewLimit: const DisplayWindowSpec(),
      notes: '<!-- ocideck_openkat_view: portfolio.summary -->',
    );
  }

  Slide _topIssuesSlide(PortfolioAggregate portfolio) {
    final issues = aggregator.topIssues(portfolio.organizations, limit: 5);
    final rows = <List<String>>[
      ['#', 'Finding', 'Ernst', 'Systemen', 'Orgs'],
      for (var i = 0; i < issues.length; i++)
        [
          '${i + 1}',
          issues[i].findingTypeName ?? issues[i].findingTypeId,
          issues[i].highestSeverity,
          '${issues[i].affectedSystems}',
          '${issues[i].affectedOrganizations}',
        ],
    ];
    return _slide(
      id: _id('openkat-portfolio-top-issues'),
      type: SlideType.table,
      title: 'Top-5 issues',
      tableRows: rows,
      viewLimit: const DisplayWindowSpec(limit: 5, mode: DisplayWindowMode.top, key: '0'),
      notes: '<!-- ocideck_openkat_view: portfolio.top-issues -->',
    );
  }

  Slide _longestOpenSlide(PortfolioAggregate portfolio) {
    final findings = aggregator.longestOpenFindings(portfolio.organizations, limit: 8);
    final rows = <List<String>>[
      ['#', 'System', 'Finding', 'Open sinds'],
      for (var i = 0; i < findings.length; i++)
        [
          '${i + 1}',
          findings[i].systemId ?? '-',
          findings[i].findingTypeName ?? findings[i].findingTypeId,
          if (findings[i].openedAt != null)
            _iso(findings[i].openedAt!)
          else
            '-',
        ],
    ];
    return _slide(
      id: _id('openkat-portfolio-longest-open'),
      type: SlideType.table,
      title: 'Langst openstaande findings',
      tableRows: rows,
      viewLimit: const DisplayWindowSpec(
        limit: 8,
        mode: DisplayWindowMode.bottom,
        key: '2',
      ),
      notes: '<!-- ocideck_openkat_view: portfolio.longest-open -->',
    );
  }

  Slide _trendSlide(PortfolioAggregate portfolio) {
    final conclusion = aggregator.compare(portfolio.current, portfolio.previous);
    final previous = portfolio.previous;
    final labels = <String>[
      'Critical',
      'High',
      'Medium',
      'Low',
    ];
    final currentSeries = <double>[
      portfolio.current.severityCounts['critical']!.toDouble(),
      portfolio.current.severityCounts['high']!.toDouble(),
      portfolio.current.severityCounts['medium']!.toDouble(),
      portfolio.current.severityCounts['low']!.toDouble(),
    ];
    final previousSeries = previous == null
        ? <double>[]
        : <double>[
            previous.severityCounts['critical']!.toDouble(),
            previous.severityCounts['high']!.toDouble(),
            previous.severityCounts['medium']!.toDouble(),
            previous.severityCounts['low']!.toDouble(),
          ];

    final chart = ChartSpec(
      type: ChartType.bar,
      x: labels,
      title: 'Trend: ${conclusion.label}',
      series: [
        ChartSeries(name: 'Huidig', data: currentSeries),
        if (previousSeries.isNotEmpty)
          ChartSeries(name: 'Vorige', data: previousSeries),
      ],
    );

    return _slide(
      id: _id('openkat-portfolio-trend'),
      type: SlideType.chart,
      title: 'Trend',
      customMarkdown: chart.toBlock(),
      notes: '<!-- ocideck_openkat_view: portfolio.trend -->',
    );
  }

  List<Slide> _organisationSlides(OpenKatOrganization org) {
    final current = org.current;
    if (current == null) return const [];
    final agg = aggregator.aggregateSnapshot(current);
    final systemStats = aggregator.systemsWithMostFindings(current, limit: 8);
    final improved = aggregator.mostImprovedSystems(org, limit: 8);

    return [
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-section'),
        type: SlideType.section,
        title: org.name,
        notes: '<!-- ocideck_openkat_view: org.${_safe(org.code)}.section -->',
      ),
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-summary'),
        type: SlideType.bullets,
        title: '${org.name} — samenvatting',
        bullets: [
          '${agg.totalSystems} systemen',
          '${agg.totalFindings} findings',
          'Critical: ${agg.severityCounts['critical']}, High: ${agg.severityCounts['high']}, Medium: ${agg.severityCounts['medium']}, Low: ${agg.severityCounts['low']}',
        ],
        notes: '<!-- ocideck_openkat_view: org.${_safe(org.code)}.summary -->',
      ),
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-systems'),
        type: SlideType.table,
        title: 'Systemen met de meeste findings',
        tableRows: [
          ['#', 'Systeem', 'Totaal', 'Critical', 'High', 'Medium'],
          for (var i = 0; i < systemStats.length; i++)
            [
              '${i + 1}',
              systemStats[i].systemId,
              '${systemStats[i].total}',
              '${systemStats[i].critical}',
              '${systemStats[i].high}',
              '${systemStats[i].medium}',
            ],
        ],
        viewLimit: const DisplayWindowSpec(
          limit: 8,
          mode: DisplayWindowMode.top,
          key: '2',
        ),
        notes: '<!-- ocideck_openkat_view: org.${_safe(org.code)}.systems -->',
      ),
      if (org.previous != null && improved.isNotEmpty)
        _slide(
          id: _id('openkat-org-${_safe(org.code)}-improved'),
          type: SlideType.table,
          title: 'Systemen die het meest verbeterden',
          tableRows: [
            ['#', 'Systeem', 'Was', 'Is', 'Classificatie'],
            for (var i = 0; i < improved.length; i++)
              [
                '${i + 1}',
                improved[i].systemId,
                '${improved[i].oldStats.total}',
                '${improved[i].newStats.total}',
                improved[i].classification,
              ],
          ],
          notes: '<!-- ocideck_openkat_view: org.${_safe(org.code)}.improved -->',
        ),
    ];
  }

  String _id(String seed) {
    final input = 'ocideck-openkat-$seed';
    final bytes = utf8.encode(input);
    final hash = md5.convert(bytes);
    return 'ocikat-${hash.toString().substring(0, 16)}';
  }

  String _safe(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

  String _iso(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
