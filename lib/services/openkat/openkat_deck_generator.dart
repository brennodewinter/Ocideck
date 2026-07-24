import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/chart.dart';
import '../../models/deck.dart';
import '../../models/display_window_spec.dart';
import '../../models/openkat/openkat_models.dart';
import '../../models/scorecard_spec.dart';
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
      _portfolioSurfaceSlide(portfolio),
      if (organizations.length > 1) _organizationsComparedSlide(portfolio),
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

  /// Een scorecard-dia: titel plus de tabel waar het type op rijdt. Het aantal
  /// regels wordt door [ScorecardSpec] zelf op vijf gehouden, op lezen én
  /// schrijven, dus dat wordt hier niet nog eens overgedaan.
  Slide _scorecardSlide({
    required String id,
    required String title,
    required List<ScorecardEntry> entries,
    required String view,
  }) => _slide(
    id: id,
    type: SlideType.scorecard,
    title: title,
    tableRows: ScorecardSpec(title: title, entries: entries).toTableRows(),
    notes: '<!-- ocideck_openkat_view: $view -->',
  );

  /// Eén ernstband als scorecardregel, met de stand van de vorige meting.
  ScorecardEntry _severityEntry(
    String band,
    Map<String, int> current,
    Map<String, int>? previous,
  ) => ScorecardEntry(
    label: _severityLabels[band] ?? band,
    value: (current[band] ?? 0).toDouble(),
    previous: previous == null ? null : (previous[band] ?? 0).toDouble(),
    polarity: ScorecardPolarity.lowerBetter,
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

  /// De kerncijfers als scorecard: elk getal naast wat het was.
  ///
  /// Een managementoverzicht gaat over wat er veranderde, en dat is precies wat
  /// een rij losse bullets niet laat zien. De scorecard rekent het verschil zelf
  /// uit en kleurt het — vandaar dat hier de vórige waarde wordt meegegeven en
  /// geen zelfgemaakt "+42". Meer findings is slecht nieuws, dus staat alles op
  /// [ScorecardPolarity.lowerBetter].
  Slide _portfolioSummarySlide(PortfolioAggregate portfolio) {
    final c = portfolio.current;
    final p = portfolio.previous;
    return _scorecardSlide(
      id: _id('openkat-portfolio-summary'),
      title: 'Kerncijfers',
      entries: [
        for (final band in openKatSeverityBands)
          _severityEntry(band, c.severityCounts, p?.severityCounts),
        ScorecardEntry(
          label: 'Getroffen systemen',
          value: c.affectedSystems.toDouble(),
          previous: p?.affectedSystems.toDouble(),
          polarity: ScorecardPolarity.lowerBetter,
        ),
      ],
      view: 'portfolio.summary',
    );
  }

  /// Wat er in beeld is. Bewust los van de kerncijfers: dit zijn tellingen van
  /// de inventarisatie, geen oordeel — meer systemen in beeld is goed nieuws
  /// zolang je aan het inventariseren bent, en die dubbelzinnigheid hoort niet
  /// tussen cijfers te staan die wél rood of groen kleuren.
  Slide _portfolioSurfaceSlide(PortfolioAggregate portfolio) {
    final c = portfolio.current;
    return _slide(
      id: _id('openkat-portfolio-surface'),
      type: SlideType.bullets,
      title: 'Wat er in beeld is',
      bullets: [
        '${c.totalSystems} systemen',
        '${c.hostnames} hostnames, ${c.ipv4} IPv4, ${c.ipv6} IPv6',
        '${c.totalFindings} findings in ${c.uniqueFindingTypes} types',
        '${c.criticalHighSystems} systemen met critical/high',
        _severityLine(c.severityCounts),
      ],
      viewLimit: const DisplayWindowSpec(),
      notes: '<!-- ocideck_openkat_view: portfolio.surface -->',
    );
  }

  /// De organisaties naast elkaar, grootste bewegers eerst.
  ///
  /// De scorecard toont er ten hoogste vijf (`scorecardMaxEntries`); bij meer
  /// organisaties is de warmtekaart het volledige beeld. Dat is de reden dat
  /// die dia er ook is.
  Slide _organizationsComparedSlide(PortfolioAggregate portfolio) {
    final comparison = aggregator.organizationComparison(
      portfolio.organizations,
    );
    return _scorecardSlide(
      id: _id('openkat-portfolio-orgs-compared'),
      title: 'Organisaties vergeleken',
      entries: [
        for (final org in comparison)
          ScorecardEntry(
            label: org.name,
            value: org.findings.toDouble(),
            previous: org.previousFindings?.toDouble(),
            unit: 'findings',
            polarity: ScorecardPolarity.lowerBetter,
          ),
      ],
      view: 'portfolio.orgs-compared',
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
    final previous = org.previous;
    final previousAgg = previous == null
        ? null
        : aggregator.aggregateSnapshot(previous);
    final systemStats = aggregator.systemsWithMostFindings(current);
    final improved = aggregator.mostImprovedSystems(org);

    return [
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-section'),
        type: SlideType.section,
        title: org.name,
        notes: '<!-- ocideck_openkat_view: org.${_safe(org.code)}.section -->',
      ),
      _scorecardSlide(
        id: _id('openkat-org-${_safe(org.code)}-summary'),
        title: '${org.name} — kerncijfers',
        entries: [
          ScorecardEntry(
            label: 'Systemen',
            value: agg.totalSystems.toDouble(),
            previous: previousAgg?.totalSystems.toDouble(),
            // Meer systemen in beeld is geen slecht nieuws: het verschil wordt
            // getoond, het oordeel blijft achterwege.
            polarity: ScorecardPolarity.neutral,
          ),
          ScorecardEntry(
            label: 'Findings',
            value: agg.totalFindings.toDouble(),
            previous: previousAgg?.totalFindings.toDouble(),
            polarity: ScorecardPolarity.lowerBetter,
          ),
          for (final band in const ['critical', 'high', 'medium'])
            _severityEntry(
              band,
              agg.severityCounts,
              previousAgg?.severityCounts,
            ),
        ],
        view: 'org.${_safe(org.code)}.summary',
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

/// De ernstbanden zoals ze op een dia komen te staan. De sleutels blijven de
/// Engelse tokens van OpenKAT, want dát is wat er in de data staat.
const Map<String, String> _severityLabels = {
  'critical': 'Critical',
  'high': 'High',
  'medium': 'Medium',
  'low': 'Low',
  openKatOtherSeverity: 'Overig',
};

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
