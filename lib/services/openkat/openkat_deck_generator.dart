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
  /// slides — **in place**, and with copy protection.
  ///
  /// De scheidslijn is de `ocideck_openkat_view`-markering, maar de markering
  /// alléén is niet genoeg (bewaker-bevinding #767): `Slide.duplicate`
  /// kopieert de notities mee, dus een gebruiker die een gegenereerde tabel
  /// dupliceert om erop te annoteren draagt de markering óók. Daarom telt per
  /// markering alleen de **eerste** dia als de gegenereerde: die wordt op zijn
  /// plek vervangen (of vervalt als de verse generatie hem niet meer kent);
  /// elke volgende met dezelfde markering is een kopie van de gebruiker en
  /// blijft staan — net als elke dia zonder markering, op precies de plek waar
  /// de gebruiker hem zette. Wat de verse generatie toevoegt en nog nergens
  /// stond, komt achteraan.
  Deck update(Deck existing, List<OpenKatOrganization> organizations) {
    final fresh = generate(organizations, title: existing.title);
    final freshByView = <String, Slide>{
      for (final s in fresh.slides) ?_viewIdOf(s): s,
    };
    final vervangen = <String>{};
    final out = <Slide>[];
    for (final slide in existing.slides) {
      final view = _viewIdOf(slide);
      if (view == null || vervangen.contains(view)) {
        out.add(slide); // handmatig, of een kopie van de gebruiker
        continue;
      }
      vervangen.add(view);
      final replacement = freshByView.remove(view);
      if (replacement != null) out.add(replacement);
      // Geen vervanger: deze gegenereerde dia bestaat niet meer en vervalt.
    }
    // Nieuw in deze generatie, in generatievolgorde.
    out.addAll(
      fresh.slides.where((s) => freshByView.containsKey(_viewIdOf(s))),
    );
    return existing.copyWith(slides: out);
  }

  /// De markering in de notities, of null voor een handmatige dia.
  static final _viewMarker = RegExp(
    r'<!--\s*ocideck_openkat_view:\s*([^\s>]+)\s*-->',
  );

  String? _viewIdOf(Slide slide) =>
      _viewMarker.firstMatch(slide.notes)?.group(1);

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
  }) => Slide(
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
        _severityLine(c.severityCounts),
      ],
      viewLimit: const DisplayWindowSpec(),
      notes: '<!-- ocideck_openkat_view: portfolio.summary -->',
    );
  }

  Slide _topIssuesSlide(PortfolioAggregate portfolio) {
    final issues = aggregator.topIssues(portfolio.organizations);
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
      // De aggregator sorteert al op zwaarte; 'first' toont die rangorde.
      // ('top' op kolom 0 — het volgnummer — keerde de lijst juist om.)
      viewLimit: const DisplayWindowSpec(limit: 5),
      notes: '<!-- ocideck_openkat_view: portfolio.top-issues -->',
    );
  }

  Slide _longestOpenSlide(PortfolioAggregate portfolio) {
    final findings = aggregator.longestOpenFindings(portfolio.organizations);
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
      // Datumkolommen zijn geen getallen; de aggregator sorteert al op
      // langst-open, dus 'first' bewaart precies die volgorde.
      viewLimit: const DisplayWindowSpec(limit: 8),
      notes: '<!-- ocideck_openkat_view: portfolio.longest-open -->',
    );
  }

  Slide _trendSlide(PortfolioAggregate portfolio) {
    final conclusion = aggregator.compare(
      portfolio.current,
      portfolio.previous,
    );
    final previous = portfolio.previous;
    final labels = <String>['Critical', 'High', 'Medium', 'Low'];
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
    final systemStats = aggregator.systemsWithMostFindings(current);
    final improved = aggregator.mostImprovedSystems(org);

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
          _severityLine(agg.severityCounts),
        ],
        notes: '<!-- ocideck_openkat_view: org.${_safe(org.code)}.summary -->',
      ),
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-systems'),
        type: SlideType.table,
        title: 'Systemen met de meeste findings',
        tableRows: _systemsTable(
          systemStats,
          showOther: agg.hasOtherSeverities,
        ),
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
          // Alles blijft in de data; de dia toont de kop van de rangorde die
          // de aggregator al maakte.
          viewLimit: const DisplayWindowSpec(limit: 8),
          notes:
              '<!-- ocideck_openkat_view: org.${_safe(org.code)}.improved -->',
        ),
    ];
  }

  String _id(String seed) => _slideId(seed);

  String _safe(String value) => _safeCode(value);

  String _iso(DateTime value) => _isoDate(value);
}

/// Een dia-id die alleen van [seed] afhangt, zodat opnieuw genereren dezelfde
/// dia's oplevert en een herimport ze op hun plek terugvindt.
String _slideId(String seed) {
  final bytes = utf8.encode('ocideck-openkat-$seed');
  final hash = md5.convert(bytes);
  return 'ocikat-${hash.toString().substring(0, 16)}';
}

String _safeCode(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

/// De ernstverdeling op één regel. De restcategorie staat er alleen als hij
/// gevuld is, maar dán ook altijd: een uitsplitsing die het totaal niet
/// verklaart laat de lezer met een gat achter dat hij niet kan thuisbrengen.
String _severityLine(Map<String, int> counts) {
  final parts = [
    'Critical: ${counts['critical'] ?? 0}',
    'High: ${counts['high'] ?? 0}',
    'Medium: ${counts['medium'] ?? 0}',
    'Low: ${counts['low'] ?? 0}',
    if ((counts[openKatOtherSeverity] ?? 0) > 0)
      'Overig: ${counts[openKatOtherSeverity]}',
  ];
  return parts.join(', ');
}

/// De tabel "Systemen met de meeste findings": alle banden, zodat de kolommen
/// optellen tot het totaal. De restkolom verschijnt alleen als er findings in
/// vallen — een kolom die overal nul is kost breedte en zegt niets.
List<List<String>> _systemsTable(
  List<OpenKatSystemStats> stats, {
  required bool showOther,
}) => [
  [
    '#',
    'Systeem',
    'Totaal',
    'Critical',
    'High',
    'Medium',
    'Low',
    if (showOther) 'Overig',
  ],
  for (var i = 0; i < stats.length; i++)
    [
      '${i + 1}',
      stats[i].systemId,
      '${stats[i].total}',
      '${stats[i].critical}',
      '${stats[i].high}',
      '${stats[i].medium}',
      '${stats[i].low}',
      if (showOther) '${stats[i].other}',
    ],
];
