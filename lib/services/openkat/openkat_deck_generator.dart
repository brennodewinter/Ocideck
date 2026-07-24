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
      if (portfolio.previous != null) _keyMessageSlide(portfolio),
      _portfolioSummarySlide(portfolio),
      _trendSlide(portfolio),
      _portfolioSurfaceSlide(portfolio),
      if (organizations.length > 1) ...[
        _organizationsComparedSlide(portfolio),
        _severityMatrixSlide(portfolio),
      ],
      _topIssuesSlide(portfolio),
      ?_recommendationsSlide(portfolio),
      _longestOpenSlide(portfolio),
      ?_controlsSlide(portfolio),
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

  /// Waar het rapport op neerkomt, in woorden.
  ///
  /// De aggregator maakt deze zinnen al ("42 meer medium findings") en trekt er
  /// een conclusie uit; tot nu toe haalde alleen het label de dia, als
  /// grafiektitel. Het zijn tellingen uit de meting zelf, geen bedachte
  /// risicoscore — daarom mogen ze vooraan staan.
  ///
  /// Alleen bij een tweede meting: zonder vorige meting valt er niets te zeggen
  /// over wat er veranderde, en een dia die dat alsnog probeert wordt een
  /// omschrijving van de cijfers die er twee dia's verderop staan.
  Slide _keyMessageSlide(PortfolioAggregate portfolio) {
    final conclusion = aggregator.compare(
      portfolio.current,
      portfolio.previous,
    );
    return _slide(
      id: _id('openkat-portfolio-key-message'),
      type: SlideType.bullets,
      title: 'Wat dit rapport zegt',
      subtitle: 'Ten opzichte van de vorige meting: ${conclusion.label}',
      bullets: conclusion.lines,
      notes: '<!-- ocideck_openkat_view: portfolio.key-message -->',
    );
  }

  /// De ernstverdeling per organisatie als warmtekaart.
  ///
  /// Waar de scorecard bij vijf regels ophoudt, schaalt dit door: één rij per
  /// organisatie, één kolom per band, en de kleur zegt waar het zwaartepunt
  /// ligt. Bij één organisatie is het hetzelfde plaatje als de verloopgrafiek
  /// en blijft de dia weg.
  Slide _severityMatrixSlide(PortfolioAggregate portfolio) {
    final perOrg = <String, Map<String, int>>{
      for (final org in portfolio.organizations)
        if (org.current != null)
          org.name: openKatSeverityCounts(org.current!.findings),
    };
    final bands = _visibleBands(perOrg.values);
    return _slide(
      id: _id('openkat-portfolio-severity-matrix'),
      type: SlideType.chart,
      title: 'Ernst per organisatie',
      customMarkdown: ChartSpec(
        type: ChartType.heatmap,
        title: 'Findings per ernstband',
        x: [for (final band in bands) _severityLabels[band] ?? band],
        series: [
          for (final entry in perOrg.entries)
            ChartSeries(
              name: entry.key,
              data: [
                for (final band in bands) (entry.value[band] ?? 0).toDouble(),
              ],
            ),
        ],
      ).toBlock(),
      notes: '<!-- ocideck_openkat_view: portfolio.severity-matrix -->',
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
    // Hoeveel er sinds de vorige meting bijkwamen wordt al geteld, maar zonder
    // vorige meting is die kolom overal nul en zegt hij niets.
    final showNew = portfolio.organizations.any((o) => o.previous != null);
    final rows = <List<String>>[
      ['#', 'Finding', 'Ernst', 'Systemen', 'Orgs', if (showNew) 'Nieuw'],
      for (var i = 0; i < issues.length; i++)
        [
          '${i + 1}',
          issues[i].findingTypeName ?? issues[i].findingTypeId,
          _severityLabels[openKatSeverityBand(issues[i].highestSeverity)] ??
              issues[i].highestSeverity,
          '${issues[i].affectedSystems}',
          '${issues[i].affectedOrganizations}',
          if (showNew) '${issues[i].deltaSincePrevious}',
        ],
    ];
    return _slide(
      id: _id('openkat-portfolio-top-issues'),
      type: SlideType.table,
      // Geen "Top-5" in de titel: de weergavelimiet zegt zelf al "5 van 22", en
      // een getal in de titel dat de limiet tegenspreekt is een fout die
      // niemand meer ziet als de limiet ooit verandert.
      title: 'Meest voorkomende issues',
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
      ['#', 'Systeem', 'Finding', 'Ernst', 'Open sinds', 'Dagen'],
      for (var i = 0; i < findings.length; i++)
        [
          '${i + 1}',
          findings[i].finding.systemId ?? '-',
          findings[i].finding.findingTypeName ??
              findings[i].finding.findingTypeId,
          _severityLabels[openKatSeverityBand(findings[i].finding.severity)] ??
              findings[i].finding.severity,
          findings[i].finding.openedAt == null
              ? '-'
              : _iso(findings[i].finding.openedAt!),
          '${findings[i].daysOpen}',
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

  /// Het verloop over álle meetmomenten, niet alleen de laatste twee.
  ///
  /// De momentopnames staan er al — ze werden alleen nooit getoond. Met twee of
  /// meer meetpunten is dat een lijn door de tijd; met één meetpunt valt er
  /// niets te verlopen en blijft het een staafdiagram van de stand van nu, want
  /// een lijn van één punt is geen grafiek.
  Slide _trendSlide(PortfolioAggregate portfolio) {
    final conclusion = aggregator.compare(
      portfolio.current,
      portfolio.previous,
    );
    final history = aggregator.history(portfolio.organizations);
    return _slide(
      id: _id('openkat-portfolio-trend'),
      type: SlideType.chart,
      title: history.length > 1 ? 'Verloop over de tijd' : 'Stand van nu',
      customMarkdown:
          (history.length > 1
                  ? _historyChart(
                      history,
                      title: 'Verloop: ${conclusion.label}',
                    )
                  : _distributionChart(
                      portfolio.current.severityCounts,
                      title: conclusion.label,
                    ))
              .toBlock(),
      notes: '<!-- ocideck_openkat_view: portfolio.trend -->',
    );
  }

  /// Wat OpenKAT zelf aanraadt bij de zwaarste issues.
  ///
  /// De aanbeveling wordt al uit de bron gehaald en per findingtype bewaard —
  /// hij haalde alleen nooit een dia. Hier komt hij als tussenkop (de finding)
  /// met de tekst eronder, zodat één dia meerdere adviezen kan dragen zonder
  /// dat ze in elkaar overlopen.
  ///
  /// Niets verzinnen: draagt geen enkel issue een aanbeveling, dan is er geen
  /// dia. De tekst is die van OpenKAT, onbewerkt.
  Slide? _recommendationsSlide(PortfolioAggregate portfolio) {
    final withAdvice = aggregator
        .topIssues(portfolio.organizations)
        .where((i) => (i.recommendation ?? '').trim().isNotEmpty)
        .take(_maxRecommendations)
        .toList();
    if (withAdvice.isEmpty) return null;

    return _slide(
      id: _id('openkat-portfolio-recommendations'),
      type: SlideType.bullets,
      title: 'Wat OpenKAT aanraadt',
      bullets: [
        for (final issue in withAdvice) ...[
          '$kGroupHeadingMarker${issue.findingTypeName ?? issue.findingTypeId}',
          issue.recommendation!.trim(),
        ],
      ],
      notes: '<!-- ocideck_openkat_view: portfolio.recommendations -->',
    );
  }

  /// De dekking per control, huidige meting naast de vorige.
  ///
  /// Liggende staven, want controlnamen zijn lang. Bewust zónder streefbanden:
  /// welk percentage "goed genoeg" is staat niet in de meting, en die norm hier
  /// invullen zou een oordeel zijn dat OpenKAT niet heeft geveld.
  ///
  /// Alleen als er dekkingscijfers mét noemer zijn — zonder noemer is er geen
  /// percentage en valt er niets te tekenen.
  Slide? _controlsSlide(PortfolioAggregate portfolio) {
    final current = <String, double>{
      for (final entry in portfolio.current.controls.entries)
        if (entry.value.ratio != null)
          entry.value.name: entry.value.ratio! * 100,
    };
    if (current.isEmpty) return null;

    final previous = <String, double>{
      for (final entry in (portfolio.previous?.controls ?? const {}).entries)
        if (entry.value.ratio != null)
          entry.value.name: entry.value.ratio! * 100,
    };
    final names = current.keys.toList()..sort();

    return _slide(
      id: _id('openkat-portfolio-controls'),
      type: SlideType.chart,
      title: 'Dekking per control',
      customMarkdown: ChartSpec(
        type: ChartType.horizontalBar,
        title: 'Percentage conform',
        x: names,
        series: [
          ChartSeries(
            name: 'Huidig',
            data: [for (final name in names) current[name] ?? 0],
          ),
          if (previous.isNotEmpty)
            ChartSeries(
              name: 'Vorige',
              data: [for (final name in names) previous[name] ?? 0],
            ),
        ],
      ).toBlock(),
      notes: '<!-- ocideck_openkat_view: portfolio.controls -->',
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
    // Het verloop van déze organisatie op haar eigen meetmomenten: geen
    // opvulling nodig, want er is er maar één die meet.
    final orgHistory = aggregator.history([org]);

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
      if (orgHistory.length > 1)
        _slide(
          id: _id('openkat-org-${_safe(org.code)}-history'),
          type: SlideType.chart,
          title: '${org.name} — verloop',
          customMarkdown: _historyChart(
            orgHistory,
            title: 'Findings per meting',
          ).toBlock(),
          notes:
              '<!-- ocideck_openkat_view: org.${_safe(org.code)}.history -->',
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

/// Hoeveel aanbevelingen er op de adviesdia passen. Vijf tussenkoppen met elk
/// een alinea vult een dia; meer wordt een lijst die niemand voorleest.
const int _maxRecommendations = 5;

/// Vaste kleuren per ernstband, zodat critical op élke dia dezelfde kleur
/// heeft. Zonder deze afspraak deelt elke grafiek zijn kleuren uit op volgorde
/// van reeks, en betekent dezelfde kleur op de volgende dia iets anders.
///
/// Aflopend van diep rood naar blauw: de volgorde is ook zonder kleur te zien,
/// wat het voor een lezer die kleuren niet onderscheidt leesbaar houdt.
const Map<String, String> _severityColors = {
  'critical': '#B00020',
  'high': '#EF4444',
  'medium': '#F59E0B',
  'low': '#2563EB',
  openKatOtherSeverity: '#64748B',
};

/// Welke banden een grafiek toont: de vier vaste banden altijd (ook op nul, zo
/// blijft de as tussen twee rapportages hetzelfde), de restband alleen als er
/// iets in valt.
List<String> _visibleBands(Iterable<Map<String, int>> counts) => [
  ...openKatSeverityBands,
  if (counts.any((c) => (c[openKatOtherSeverity] ?? 0) > 0))
    openKatOtherSeverity,
];

/// Het verloop als lijngrafiek: één punt per meetmoment, één lijn per band.
ChartSpec _historyChart(
  List<OpenKatHistoryPoint> history, {
  required String title,
}) {
  final bands = _visibleBands([for (final p in history) p.severityCounts]);
  return ChartSpec(
    type: ChartType.line,
    title: title,
    x: [for (final point in history) _isoDate(point.date)],
    series: [
      for (final band in bands)
        ChartSeries(
          name: _severityLabels[band] ?? band,
          color: _severityColors[band],
          data: [
            for (final point in history)
              (point.severityCounts[band] ?? 0).toDouble(),
          ],
        ),
    ],
  );
}

/// De stand van nu als staafdiagram — wat er te tonen valt zolang er maar één
/// meting is.
ChartSpec _distributionChart(Map<String, int> counts, {required String title}) {
  final bands = _visibleBands([counts]);
  return ChartSpec(
    type: ChartType.bar,
    title: title,
    x: [for (final band in bands) _severityLabels[band] ?? band],
    rowColors: [for (final band in bands) _severityColors[band]],
    series: [
      ChartSeries(
        name: 'Findings',
        data: [for (final band in bands) (counts[band] ?? 0).toDouble()],
      ),
    ],
  );
}

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
