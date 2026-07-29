import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/chart.dart';
import '../../models/deck.dart';
import '../../models/display_window_spec.dart';
import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import '../../models/scorecard_spec.dart';
import '../../models/slide.dart';
import 'openkat_aggregator.dart';
import 'openkat_report_facts.dart';

/// Zet een gevalideerd rapportplan om in gewone OciDeck-dia's.
///
/// Feiten en selectieregels komen uitsluitend uit [facts]. Dit bestand beslist
/// alleen hoe een rapportblok eruitziet.
class OpenKatReportComposer {
  final OpenKatReportFacts facts;
  final OpenKatReportLanguage language;

  const OpenKatReportComposer(
    this.facts, {
    this.language = OpenKatReportLanguage.dutch,
  });

  bool get _english => language == OpenKatReportLanguage.english;

  String _text(String dutch, String english) => _english ? english : dutch;

  Deck compose(
    OpenKatReportRequest request,
    OpenKatReportPlan plan, {
    String? outputPath,
  }) {
    final organizations = facts.selectedOrganizations(request);
    final title = request.title ?? _defaultTitle(request);
    var deck = Deck(
      title: title,
      projectPath: outputPath ?? '',
      version: '1.0',
      language: request.language.code,
      slides: [_titleSlide(title, organizations)],
    );

    for (final block in plan.blocks) {
      switch (block.kind) {
        case OpenKatReportBlockKind.managementOverview:
          deck = generate(
            organizations,
            title: title,
            outputPath: outputPath,
          ).copyWith(language: request.language.code);
        case OpenKatReportBlockKind.measurementAvailability:
          deck = deck.copyWith(
            slides: [...deck.slides, _measurementAvailabilitySlide(request)],
          );
        case OpenKatReportBlockKind.findingLifecycle:
          deck = deck.copyWith(
            slides: [...deck.slides, _findingLifecycleSlide(request)],
          );
        case OpenKatReportBlockKind.cveExposure:
          deck = deck.copyWith(
            slides: [...deck.slides, _cveExposureSlide(request)],
          );
        case OpenKatReportBlockKind.monitoringChanges:
          deck = deck.copyWith(
            slides: [...deck.slides, _monitoringChangesSlide(request)],
          );
      }
    }
    return deck;
  }

  String _defaultTitle(OpenKatReportRequest request) {
    final english = request.language == OpenKatReportLanguage.english;
    return switch (request.scenarioId) {
      'weekly-comparison' =>
        english ? 'OpenKAT weekly comparison' : 'OpenKAT-weekvergelijking',
      'organization-overview' =>
        english
            ? 'OpenKAT organization overview'
            : 'OpenKAT-organisatieoverzicht',
      'cve-exposure' =>
        english ? 'OpenKAT CVE exposure' : 'OpenKAT CVE-blootstelling',
      'monitoring-changes' =>
        english ? 'OpenKAT monitoring changes' : 'OpenKAT-monitoringmutaties',
      _ =>
        english ? 'OpenKAT management overview' : 'OpenKAT managementoverzicht',
    };
  }

  /// Generates a fresh deck from the scanned organisations.
  Deck generate(
    List<OpenKatOrganization> organizations, {
    String title = 'OpenKAT managementoverzicht',
    String? outputPath,
  }) {
    final portfolio = facts.aggregatePortfolio(organizations);
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

  Slide _measurementAvailabilitySlide(OpenKatReportRequest request) {
    final english = request.language == OpenKatReportLanguage.english;
    final rows = <List<String>>[
      [
        english ? 'Organization' : 'Organisatie',
        english ? 'Period' : 'Periode',
        english ? 'Cut-off' : 'Peildatum',
        english ? 'Measurement' : 'Meting',
        english ? 'Age (days)' : 'Ouderdom (dagen)',
      ],
      for (final usage in facts.measurementUsages(request))
        [
          usage.organizationCode,
          usage.role == OpenKatMeasurementRole.current
              ? (english ? 'Current' : 'Huidig')
              : (english ? 'Previous' : 'Vorig'),
          _iso(usage.requestedAsOf),
          usage.measuredAt == null ? '-' : _iso(usage.measuredAt!),
          usage.age == null ? '-' : '${usage.age!.inDays}',
        ],
    ];
    return _slide(
      id: _id('openkat-${request.scenarioId}-availability'),
      type: SlideType.table,
      title: english ? 'Measurements used' : 'Gebruikte meetmomenten',
      tableRows: rows,
      viewLimit: DisplayWindowSpec(limit: request.policy.tableRowLimit),
      notes:
          '<!-- ocideck_openkat_view: report.${request.scenarioId}.availability -->',
    );
  }

  Slide _findingLifecycleSlide(OpenKatReportRequest request) {
    final english = request.language == OpenKatReportLanguage.english;
    final lifecycle = facts.findingLifecycle(request);
    return _slide(
      id: _id('openkat-${request.scenarioId}-lifecycle'),
      type: SlideType.table,
      title: english ? 'Finding observations' : 'Waarnemingen van findings',
      tableRows: [
        [
          english ? 'Organization' : 'Organisatie',
          'Finding',
          english ? 'Observation' : 'Waarneming',
          english ? 'Comparable coverage' : 'Vergelijkbare dekking',
        ],
        for (final item in lifecycle)
          [
            item.organizationCode,
            item.finding.findingTypeName ?? item.finding.findingTypeId,
            _observationLabel(item.observation, english: english),
            item.comparableCoverage
                ? (english ? 'Yes' : 'Ja')
                : (english ? 'Not demonstrated' : 'Niet aangetoond'),
          ],
      ],
      viewLimit: DisplayWindowSpec(limit: request.policy.tableRowLimit),
      notes:
          '<!-- ocideck_openkat_view: report.${request.scenarioId}.lifecycle -->',
    );
  }

  String _observationLabel(
    OpenKatFindingObservation observation, {
    required bool english,
  }) => switch (observation) {
    OpenKatFindingObservation.newlyObserved =>
      english ? 'Newly observed' : 'Nieuw waargenomen',
    OpenKatFindingObservation.noLongerObserved =>
      english ? 'No longer observed' : 'Niet meer waargenomen',
    OpenKatFindingObservation.reobserved =>
      english ? 'Observed again' : 'Opnieuw waargenomen',
  };

  Slide _cveExposureSlide(OpenKatReportRequest request) {
    final english = request.language == OpenKatReportLanguage.english;
    final cveId = request.cveId!.trim().toUpperCase();
    final exposure = facts.cveExposure(request, cveId);
    return _slide(
      id: _id('openkat-${request.scenarioId}-$cveId'),
      type: SlideType.table,
      title: english ? 'Exposure to $cveId' : 'Blootstelling aan $cveId',
      tableRows: [
        [
          english ? 'Organization' : 'Organisatie',
          'Finding',
          english ? 'System' : 'Systeem',
          english ? 'Severity' : 'Ernst',
        ],
        for (final item in exposure)
          [
            item.organizationCode,
            item.finding.findingTypeName ?? item.finding.findingTypeId,
            item.finding.systemId ?? '-',
            item.finding.severity,
          ],
      ],
      viewLimit: DisplayWindowSpec(limit: request.policy.tableRowLimit),
      notes:
          '<!-- ocideck_openkat_view: report.${request.scenarioId}.exposure -->',
    );
  }

  Slide _monitoringChangesSlide(OpenKatReportRequest request) {
    final english = request.language == OpenKatReportLanguage.english;
    final mutations = facts.monitoringMutations(request);
    return _slide(
      id: _id('openkat-${request.scenarioId}-mutations'),
      type: SlideType.table,
      title: english ? 'Monitoring changes' : 'Monitoringmutaties',
      tableRows: [
        [
          english ? 'Organization' : 'Organisatie',
          english ? 'Asset' : 'Asset',
          english ? 'Change' : 'Verandering',
        ],
        for (final mutation in mutations)
          [
            mutation.organizationCode,
            mutation.system.id,
            mutation.kind == OpenKatMonitoringMutationKind.added
                ? (english
                      ? 'Added to monitoring'
                      : 'Toegevoegd aan monitoring')
                : (english
                      ? 'Removed from monitoring'
                      : 'Verwijderd uit monitoring'),
          ],
      ],
      viewLimit: DisplayWindowSpec(limit: request.policy.tableRowLimit),
      notes:
          '<!-- ocideck_openkat_view: report.${request.scenarioId}.monitoring -->',
    );
  }

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
    label: _severityLabel(band),
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
      subtitle: '${_text('Organisaties', 'Organizations')}: $orgNames',
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
    final conclusion = facts.compare(portfolio.current, portfolio.previous);
    return _slide(
      id: _id('openkat-portfolio-key-message'),
      type: SlideType.bullets,
      title: _text('Wat dit rapport zegt', 'What this report says'),
      subtitle:
          '${_text('Ten opzichte van de vorige meting', 'Compared with the previous measurement')}: '
          '${_trendLabel(conclusion.label)}',
      bullets: [for (final line in conclusion.lines) _trendLine(line)],
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
      title: _text('Ernst per organisatie', 'Severity by organization'),
      customMarkdown: ChartSpec(
        type: ChartType.heatmap,
        title: _text('Findings per ernstband', 'Findings by severity'),
        x: [for (final band in bands) _severityLabel(band)],
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
      title: _text('Kerncijfers', 'Key figures'),
      entries: [
        for (final band in openKatSeverityBands)
          _severityEntry(band, c.severityCounts, p?.severityCounts),
        ScorecardEntry(
          label: _text('Getroffen systemen', 'Affected systems'),
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
      title: _text('Wat er in beeld is', 'Observed scope'),
      bullets: [
        '${c.totalSystems} ${_text('systemen', 'systems')}',
        '${c.hostnames} hostnames, ${c.ipv4} IPv4, ${c.ipv6} IPv6',
        '${c.totalFindings} findings ${_text('in', 'across')} ${c.uniqueFindingTypes} types',
        '${c.criticalHighSystems} ${_text('systemen met critical/high', 'systems with critical/high')}',
        _severityLine(c.severityCounts, english: _english),
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
    final comparison = facts.organizationComparison(portfolio.organizations);
    return _scorecardSlide(
      id: _id('openkat-portfolio-orgs-compared'),
      title: _text('Organisaties vergeleken', 'Organizations compared'),
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
    final issues = facts.topIssues(portfolio.organizations);
    // Hoeveel er sinds de vorige meting bijkwamen wordt al geteld, maar zonder
    // vorige meting is die kolom overal nul en zegt hij niets.
    final showNew = portfolio.organizations.any((o) => o.previous != null);
    final rows = <List<String>>[
      [
        '#',
        'Finding',
        _text('Ernst', 'Severity'),
        _text('Systemen', 'Systems'),
        _text('Orgs', 'Orgs'),
        if (showNew) _text('Nieuw', 'New'),
      ],
      for (var i = 0; i < issues.length; i++)
        [
          '${i + 1}',
          issues[i].findingTypeName ?? issues[i].findingTypeId,
          _severityLabel(openKatSeverityBand(issues[i].highestSeverity)),
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
      title: _text('Meest voorkomende issues', 'Most common issues'),
      tableRows: rows,
      // De aggregator sorteert al op zwaarte; 'first' toont die rangorde.
      // ('top' op kolom 0 — het volgnummer — keerde de lijst juist om.)
      viewLimit: const DisplayWindowSpec(limit: 5),
      notes: '<!-- ocideck_openkat_view: portfolio.top-issues -->',
    );
  }

  Slide _longestOpenSlide(PortfolioAggregate portfolio) {
    final findings = facts.longestOpenFindings(portfolio.organizations);
    final rows = <List<String>>[
      [
        '#',
        _text('Systeem', 'System'),
        'Finding',
        _text('Ernst', 'Severity'),
        _text('Open sinds', 'Observed since'),
        _text('Dagen', 'Days'),
      ],
      for (var i = 0; i < findings.length; i++)
        [
          '${i + 1}',
          findings[i].finding.systemId ?? '-',
          findings[i].finding.findingTypeName ??
              findings[i].finding.findingTypeId,
          _severityLabel(openKatSeverityBand(findings[i].finding.severity)),
          findings[i].finding.openedAt == null
              ? '-'
              : _iso(findings[i].finding.openedAt!),
          '${findings[i].daysOpen}',
        ],
    ];
    return _slide(
      id: _id('openkat-portfolio-longest-open'),
      type: SlideType.table,
      title: _text('Langst openstaande findings', 'Longest-observed findings'),
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
    final conclusion = facts.compare(portfolio.current, portfolio.previous);
    final history = facts.history(portfolio.organizations);
    return _slide(
      id: _id('openkat-portfolio-trend'),
      type: SlideType.chart,
      title: history.length > 1
          ? _text('Verloop over de tijd', 'Trend over time')
          : _text('Stand van nu', 'Current measurement'),
      customMarkdown:
          (history.length > 1
                  ? _historyChart(
                      history,
                      title:
                          '${_text('Verloop', 'Trend')}: ${_trendLabel(conclusion.label)}',
                      english: _english,
                    )
                  : _distributionChart(
                      portfolio.current.severityCounts,
                      title: _trendLabel(conclusion.label),
                      english: _english,
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
    final withAdvice = facts
        .topIssues(portfolio.organizations)
        .where((i) => (i.recommendation ?? '').trim().isNotEmpty)
        .take(_maxRecommendations)
        .toList();
    if (withAdvice.isEmpty) return null;

    return _slide(
      id: _id('openkat-portfolio-recommendations'),
      type: SlideType.bullets,
      title: _text('Wat OpenKAT aanraadt', 'OpenKAT recommendations'),
      bullets: [
        for (final issue in withAdvice) ...[
          groupHeadingBullet(issue.findingTypeName ?? issue.findingTypeId),
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
      title: _text('Dekking per control', 'Coverage by control'),
      customMarkdown: ChartSpec(
        type: ChartType.horizontalBar,
        title: _text('Percentage conform', 'Percentage compliant'),
        x: names,
        series: [
          ChartSeries(
            name: _text('Huidig', 'Current'),
            data: [for (final name in names) current[name] ?? 0],
          ),
          if (previous.isNotEmpty)
            ChartSeries(
              name: _text('Vorige', 'Previous'),
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
    final agg = facts.aggregateSnapshot(current);
    final previous = org.previous;
    final previousAgg = previous == null
        ? null
        : facts.aggregateSnapshot(previous);
    final systemStats = facts.systemsWithMostFindings(current);
    final improved = facts.mostImprovedSystems(org);
    // Het verloop van déze organisatie op haar eigen meetmomenten: geen
    // opvulling nodig, want er is er maar één die meet.
    final orgHistory = facts.history([org]);

    return [
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-section'),
        type: SlideType.section,
        title: org.name,
        notes: '<!-- ocideck_openkat_view: org.${_safe(org.code)}.section -->',
      ),
      _scorecardSlide(
        id: _id('openkat-org-${_safe(org.code)}-summary'),
        title: '${org.name} — ${_text('kerncijfers', 'key figures')}',
        entries: [
          ScorecardEntry(
            label: _text('Systemen', 'Systems'),
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
          title: '${org.name} — ${_text('verloop', 'trend')}',
          customMarkdown: _historyChart(
            orgHistory,
            title: _text('Findings per meting', 'Findings by measurement'),
            english: _english,
          ).toBlock(),
          notes:
              '<!-- ocideck_openkat_view: org.${_safe(org.code)}.history -->',
        ),
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-systems'),
        type: SlideType.table,
        title: _text(
          'Systemen met de meeste findings',
          'Systems with the most findings',
        ),
        tableRows: _systemsTable(
          systemStats,
          showOther: agg.hasOtherSeverities,
          english: _english,
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
          title: _text(
            'Systemen die het meest verbeterden',
            'Systems with the largest improvement',
          ),
          tableRows: [
            [
              '#',
              _text('Systeem', 'System'),
              _text('Was', 'Previous'),
              _text('Is', 'Current'),
              _text('Classificatie', 'Classification'),
            ],
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

  String _severityLabel(String band) =>
      (_english ? _severityLabelsEnglish : _severityLabels)[band] ?? band;

  String _trendLabel(String label) => switch (label) {
    'Eerste meting' => _text('Eerste meting', 'First measurement'),
    'Beter' => _text('Beter', 'Improved'),
    'Slechter' => _text('Slechter', 'Worsened'),
    'Gemengd' => _text('Gemengd', 'Mixed'),
    _ => label,
  };

  String _trendLine(String line) {
    if (!_english) return line;
    if (line == 'Eerste meting; nog geen trend beschikbaar') {
      return 'First measurement; no trend is available yet';
    }
    final delta = RegExp(
      r'^([0-9]+) (meer|minder) (kritieke|hoge|medium) findings$',
    ).firstMatch(line);
    if (delta != null) {
      final direction = delta.group(2) == 'meer' ? 'more' : 'fewer';
      final severity = switch (delta.group(3)) {
        'kritieke' => 'critical',
        'hoge' => 'high',
        _ => 'medium',
      };
      return '${delta.group(1)} $direction $severity findings';
    }
    final affected = RegExp(
      r'^([0-9]+) (meer|minder) getroffen systemen$',
    ).firstMatch(line);
    if (affected != null) {
      final direction = affected.group(2) == 'meer' ? 'more' : 'fewer';
      return '${affected.group(1)} $direction affected systems';
    }
    return line
        .replaceFirst('-dekking verbeterd van ', ' coverage improved from ')
        .replaceFirst('-dekking verslechterd van ', ' coverage worsened from ')
        .replaceFirst(' naar ', ' to ');
  }
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
  required bool english,
}) {
  final bands = _visibleBands([for (final p in history) p.severityCounts]);
  final labels = english ? _severityLabelsEnglish : _severityLabels;
  return ChartSpec(
    type: ChartType.line,
    title: title,
    x: [for (final point in history) _isoDate(point.date)],
    series: [
      for (final band in bands)
        ChartSeries(
          name: labels[band] ?? band,
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
ChartSpec _distributionChart(
  Map<String, int> counts, {
  required String title,
  required bool english,
}) {
  final bands = _visibleBands([counts]);
  final labels = english ? _severityLabelsEnglish : _severityLabels;
  return ChartSpec(
    type: ChartType.bar,
    title: title,
    x: [for (final band in bands) labels[band] ?? band],
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

const Map<String, String> _severityLabelsEnglish = {
  'critical': 'Critical',
  'high': 'High',
  'medium': 'Medium',
  'low': 'Low',
  openKatOtherSeverity: 'Other',
};

/// De ernstverdeling op één regel. De restcategorie staat er alleen als hij
/// gevuld is, maar dán ook altijd: een uitsplitsing die het totaal niet
/// verklaart laat de lezer met een gat achter dat hij niet kan thuisbrengen.
String _severityLine(Map<String, int> counts, {required bool english}) {
  final parts = [
    'Critical: ${counts['critical'] ?? 0}',
    'High: ${counts['high'] ?? 0}',
    'Medium: ${counts['medium'] ?? 0}',
    'Low: ${counts['low'] ?? 0}',
    if ((counts[openKatOtherSeverity] ?? 0) > 0)
      '${english ? 'Other' : 'Overig'}: ${counts[openKatOtherSeverity]}',
  ];
  return parts.join(', ');
}

/// De tabel "Systemen met de meeste findings": alle banden, zodat de kolommen
/// optellen tot het totaal. De restkolom verschijnt alleen als er findings in
/// vallen — een kolom die overal nul is kost breedte en zegt niets.
List<List<String>> _systemsTable(
  List<OpenKatSystemStats> stats, {
  required bool showOther,
  required bool english,
}) => [
  [
    '#',
    english ? 'System' : 'Systeem',
    english ? 'Total' : 'Totaal',
    'Critical',
    'High',
    'Medium',
    'Low',
    if (showOther) english ? 'Other' : 'Overig',
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
