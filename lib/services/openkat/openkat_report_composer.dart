import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../models/chart.dart';
import '../../models/deck.dart';
import '../../models/display_window_spec.dart';
import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import '../../models/scorecard_spec.dart';
import '../../models/slide.dart';
import '../import/utils/import_text_sanitizer.dart';
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
    final selections = facts
        .selections(request)
        .where((selection) => selection.current != null)
        .toList();
    final comparableOrganizations = {
      for (final selection in selections)
        if (facts.hasComparableCoverage(selection)) selection.organization.code,
    };
    final comparablePortfolio =
        selections.isNotEmpty &&
        selections.every(
          (selection) =>
              selection.previous != null &&
              comparableOrganizations.contains(selection.organization.code),
        );
    final title = request.title ?? _defaultTitle(request);
    var deck = Deck(
      title: _literal(title),
      projectPath: outputPath ?? '',
      version: '1.0',
      language: request.language.code,
      slides: [_titleSlide(title, organizations)],
    );

    for (final block in plan.blocks) {
      switch (block.kind) {
        case OpenKatReportBlockKind.managementOverview:
          final management = generate(
            organizations,
            title: title,
            outputPath: outputPath,
            comparablePortfolio: comparablePortfolio,
            comparableOrganizations: comparableOrganizations,
          );
          deck = deck.copyWith(
            language: request.language.code,
            slides: [...deck.slides, ...management.slides.skip(1)],
          );
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
    bool comparablePortfolio = false,
    Set<String> comparableOrganizations = const {},
  }) {
    final portfolio = facts.aggregatePortfolio(organizations);
    final hasComparison = portfolio.previous != null;
    final slides = <Slide>[
      _titleSlide(title, organizations),
      if (hasComparison && !comparablePortfolio) _comparisonWarningSlide(),
      if (hasComparison && comparablePortfolio) _keyMessageSlide(portfolio),
      _portfolioSummarySlide(portfolio, compare: comparablePortfolio),
      _trendSlide(portfolio, compare: comparablePortfolio),
      _portfolioSurfaceSlide(portfolio),
      if (organizations.length > 1) ...[
        _organizationsComparedSlide(portfolio, compare: comparablePortfolio),
        _severityMatrixSlide(portfolio),
      ],
      _topIssuesSlide(portfolio, compare: comparablePortfolio),
      ?_recommendationsSlide(portfolio),
      _longestOpenSlide(portfolio),
      ?_controlsSlide(portfolio, compare: comparablePortfolio),
      for (final org in organizations)
        ..._organisationSlides(
          org,
          compare: comparableOrganizations.contains(org.code),
        ),
    ];

    return Deck(
      title: _literal(title),
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
          _inline(usage.organizationCode),
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
    final limit = request.policy.tableRowLimit;
    final lifecycle = facts.findingLifecycle(request, maxResults: limit + 1);
    final truncated = lifecycle.length > limit;
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
        for (final item in lifecycle.take(limit))
          [
            _inline(item.organizationCode),
            _inline(item.finding.findingTypeName ?? item.finding.findingTypeId),
            _observationLabel(item.observation, english: english),
            item.comparableCoverage
                ? (english ? 'Yes' : 'Ja')
                : (english ? 'Not demonstrated' : 'Niet aangetoond'),
          ],
        if (truncated) _omittedRow(columns: 4, english: english, shown: limit),
      ],
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
    final limit = request.policy.tableRowLimit;
    final exposure = facts.cveExposure(request, cveId, maxResults: limit + 1);
    final truncated = exposure.length > limit;
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
        for (final item in exposure.take(limit))
          [
            _inline(item.organizationCode),
            _inline(item.finding.findingTypeName ?? item.finding.findingTypeId),
            _inline(item.finding.systemId ?? '-'),
            _inline(item.finding.severity),
          ],
        if (truncated) _omittedRow(columns: 4, english: english, shown: limit),
      ],
      notes:
          '<!-- ocideck_openkat_view: report.${request.scenarioId}.exposure -->',
    );
  }

  Slide _monitoringChangesSlide(OpenKatReportRequest request) {
    final english = request.language == OpenKatReportLanguage.english;
    final limit = request.policy.tableRowLimit;
    final mutations = facts.monitoringMutations(request, maxResults: limit + 1);
    final truncated = mutations.length > limit;
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
        for (final mutation in mutations.take(limit))
          [
            _inline(mutation.organizationCode),
            _inline(mutation.system.id),
            mutation.kind == OpenKatMonitoringMutationKind.added
                ? (english
                      ? 'Added to monitoring'
                      : 'Toegevoegd aan monitoring')
                : (english
                      ? 'Removed from monitoring'
                      : 'Verwijderd uit monitoring'),
          ],
        if (truncated) _omittedRow(columns: 3, english: english, shown: limit),
      ],
      notes:
          '<!-- ocideck_openkat_view: report.${request.scenarioId}.monitoring -->',
    );
  }

  List<String> _omittedRow({
    required int columns,
    required bool english,
    required int shown,
  }) => [
    english
        ? 'More results omitted after the configured limit of $shown'
        : 'Meer resultaten weggelaten na de ingestelde limiet van $shown',
    for (var i = 1; i < columns; i++) '',
  ];

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
    final orgNames = organizations.map((o) => _literal(o.name)).join(', ');
    return _slide(
      id: _id('openkat-title'),
      type: SlideType.title,
      title: _literal(title),
      subtitle: '${_text('Organisaties', 'Organizations')}: $orgNames',
      notes: '<!-- ocideck_openkat_view: title -->',
    );
  }

  Slide _comparisonWarningSlide() => _slide(
    id: _id('openkat-comparison-warning'),
    type: SlideType.bullets,
    title: _text(
      'Vergelijkbaarheid niet aangetoond',
      'Comparability not demonstrated',
    ),
    bullets: [
      _text(
        'De meetdekking kan tussen meetmomenten verschillen. Daarom toont dit '
            'rapport geen normatieve vergelijking van de meetwaarden.',
        'Measurement coverage may differ between measurements. This report '
            'therefore makes no directional comparison of the measured values.',
      ),
    ],
    notes: '<!-- ocideck_openkat_view: portfolio.comparison-warning -->',
  );

  Slide _keyMessageSlide(PortfolioAggregate portfolio) {
    final conclusion = facts.compare(portfolio.current, portfolio.previous);
    return _slide(
      id: _id('openkat-portfolio-key-message'),
      type: SlideType.bullets,
      title: _text('Wat dit rapport zegt', 'What this report says'),
      subtitle:
          '${_text('Ten opzichte van de vorige meting', 'Compared with the previous measurement')}: '
          '${_trendLabel(conclusion)}',
      bullets: _trendLines(conclusion),
      notes: '<!-- ocideck_openkat_view: portfolio.key-message -->',
    );
  }

  Slide _severityMatrixSlide(PortfolioAggregate portfolio) {
    final perOrg = <String, Map<String, int>>{
      for (final org in portfolio.organizations)
        if (org.current != null)
          _literal(org.name): openKatSeverityCounts(org.current!.findings),
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

  Slide _portfolioSummarySlide(
    PortfolioAggregate portfolio, {
    required bool compare,
  }) {
    final c = portfolio.current;
    final p = compare ? portfolio.previous : null;
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

  Slide _organizationsComparedSlide(
    PortfolioAggregate portfolio, {
    required bool compare,
  }) {
    final comparison = facts.organizationComparison(portfolio.organizations);
    return _scorecardSlide(
      id: _id('openkat-portfolio-orgs-compared'),
      title: _text('Organisaties vergeleken', 'Organizations compared'),
      entries: [
        for (final org in comparison)
          ScorecardEntry(
            label: _literal(org.name),
            value: org.findings.toDouble(),
            previous: compare ? org.previousFindings?.toDouble() : null,
            unit: 'findings',
            polarity: compare
                ? ScorecardPolarity.lowerBetter
                : ScorecardPolarity.neutral,
          ),
      ],
      view: 'portfolio.orgs-compared',
    );
  }

  Slide _topIssuesSlide(PortfolioAggregate portfolio, {required bool compare}) {
    final issues = facts.topIssues(portfolio.organizations);
    final showNew =
        compare && portfolio.organizations.any((o) => o.previous != null);
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
          _inline(issues[i].findingTypeName ?? issues[i].findingTypeId),
          _severityLabel(openKatSeverityBand(issues[i].highestSeverity)),
          '${issues[i].affectedSystems}',
          '${issues[i].affectedOrganizations}',
          if (showNew) '${issues[i].deltaSincePrevious}',
        ],
    ];
    return _slide(
      id: _id('openkat-portfolio-top-issues'),
      type: SlideType.table,
      title: _text('Meest voorkomende issues', 'Most common issues'),
      tableRows: rows,
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
          _inline(findings[i].finding.systemId ?? '-'),
          _inline(
            findings[i].finding.findingTypeName ??
                findings[i].finding.findingTypeId,
          ),
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
      viewLimit: const DisplayWindowSpec(limit: 8),
      notes: '<!-- ocideck_openkat_view: portfolio.longest-open -->',
    );
  }

  Slide _trendSlide(PortfolioAggregate portfolio, {required bool compare}) {
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
                      title: compare
                          ? '${_text('Verloop', 'Trend')}: '
                                '${_trendLabel(conclusion)}'
                          : _text(
                              'Meetwaarden per periode',
                              'Values by period',
                            ),
                      english: _english,
                    )
                  : _distributionChart(
                      portfolio.current.severityCounts,
                      title: compare
                          ? _trendLabel(conclusion)
                          : _text('Huidige meetwaarden', 'Current values'),
                      english: _english,
                    ))
              .toBlock(),
      notes: '<!-- ocideck_openkat_view: portfolio.trend -->',
    );
  }

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
          groupHeadingBullet(
            sanitizeImportedText(issue.findingTypeName ?? issue.findingTypeId),
          ),
          sanitizeImportedText(issue.recommendation!),
        ],
      ],
      notes: '<!-- ocideck_openkat_view: portfolio.recommendations -->',
    );
  }

  Slide? _controlsSlide(PortfolioAggregate portfolio, {required bool compare}) {
    final current = <String, double>{
      for (final entry in portfolio.current.controls.entries)
        if (entry.value.ratio != null)
          _literal(entry.value.name): entry.value.ratio! * 100,
    };
    if (current.isEmpty) return null;

    final previous = <String, double>{
      for (final entry in (portfolio.previous?.controls ?? const {}).entries)
        if (entry.value.ratio != null)
          _literal(entry.value.name): entry.value.ratio! * 100,
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
          if (compare && previous.isNotEmpty)
            ChartSeries(
              name: _text('Vorige', 'Previous'),
              data: [for (final name in names) previous[name] ?? 0],
            ),
        ],
      ).toBlock(),
      notes: '<!-- ocideck_openkat_view: portfolio.controls -->',
    );
  }

  List<Slide> _organisationSlides(
    OpenKatOrganization org, {
    required bool compare,
  }) {
    final current = org.current;
    if (current == null) return const [];
    final agg = facts.aggregateSnapshot(current);
    final previous = org.previous;
    final previousAgg = previous == null || !compare
        ? null
        : facts.aggregateSnapshot(previous);
    final systemStats = facts.systemsWithMostFindings(current);
    final improved = compare
        ? facts.mostImprovedSystems(org)
        : const <OpenKatSystemChange>[];
    final orgHistory = facts.history([org]);

    return [
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-section'),
        type: SlideType.section,
        title: _literal(org.name),
        notes: '<!-- ocideck_openkat_view: org.${_safe(org.code)}.section -->',
      ),
      _scorecardSlide(
        id: _id('openkat-org-${_safe(org.code)}-summary'),
        title: '${_literal(org.name)} — ${_text('kerncijfers', 'key figures')}',
        entries: [
          ScorecardEntry(
            label: _text('Systemen', 'Systems'),
            value: agg.totalSystems.toDouble(),
            previous: previousAgg?.totalSystems.toDouble(),
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
          title: '${_literal(org.name)} — ${_text('verloop', 'trend')}',
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
      if (compare && org.previous != null && improved.isNotEmpty)
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
                _inline(improved[i].systemId),
                '${improved[i].oldStats.total}',
                '${improved[i].newStats.total}',
                _inline(improved[i].classification),
              ],
          ],
          viewLimit: const DisplayWindowSpec(limit: 8),
          notes:
              '<!-- ocideck_openkat_view: org.${_safe(org.code)}.improved -->',
        ),
    ];
  }

  String _id(String seed) => _slideId(seed);

  String _safe(String value) => _safeCode(value);

  String _literal(String value) => sanitizeImportedText(value);

  String _inline(String value) => _safeTableText(value);

  String _iso(DateTime value) => _isoDate(value);

  String _severityLabel(String band) =>
      (_english ? _severityLabelsEnglish : _severityLabels)[band] ?? band;

  String _trendLabel(TrendConclusion conclusion) =>
      switch (conclusion.direction) {
        OpenKatTrendDirection.firstMeasurement => _text(
          'Eerste meting',
          'First measurement',
        ),
        OpenKatTrendDirection.improved => _text('Beter', 'Improved'),
        OpenKatTrendDirection.worsened => _text('Slechter', 'Worsened'),
        OpenKatTrendDirection.mixed => _text('Gemengd', 'Mixed'),
      };

  List<String> _trendLines(TrendConclusion conclusion) {
    if (conclusion.direction == OpenKatTrendDirection.firstMeasurement) {
      return [
        _text(
          'Eerste meting; nog geen trend beschikbaar',
          'First measurement; no trend is available yet',
        ),
      ];
    }
    return [for (final fact in conclusion.facts) _trendFact(fact)];
  }

  String _trendFact(OpenKatTrendFact fact) {
    if (fact.metric == OpenKatTrendMetric.controlCoverage) {
      final improved = fact.currentRatio! > fact.previousRatio!;
      final controlId = _literal(fact.controlId ?? '');
      return _english
          ? '$controlId coverage ${improved ? 'improved' : 'worsened'} '
                'from ${_percent(fact.previousRatio!)} to '
                '${_percent(fact.currentRatio!)}'
          : '$controlId-dekking '
                '${improved ? 'verbeterd' : 'verslechterd'} van '
                '${_percent(fact.previousRatio!)} naar '
                '${_percent(fact.currentRatio!)}';
    }
    final count = fact.delta!.abs();
    final more = fact.delta! > 0;
    final metric = switch (fact.metric) {
      OpenKatTrendMetric.criticalFindings => _text(
        'kritieke findings',
        'critical findings',
      ),
      OpenKatTrendMetric.highFindings => _text(
        'hoge findings',
        'high findings',
      ),
      OpenKatTrendMetric.mediumFindings => 'medium findings',
      OpenKatTrendMetric.affectedSystems => _text(
        'getroffen systemen',
        'affected systems',
      ),
      OpenKatTrendMetric.controlCoverage => throw StateError(
        'control coverage is handled above',
      ),
    };
    final direction = _english
        ? (more ? 'more' : 'fewer')
        : (more ? 'meer' : 'minder');
    return '$count $direction $metric';
  }

  String _percent(double value) => '${(value * 100).round()}%';
}

String _slideId(String seed) {
  final bytes = utf8.encode('ocideck-openkat-$seed');
  final hash = md5.convert(bytes);
  return 'ocikat-${hash.toString().substring(0, 16)}';
}

String _safeCode(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');

String _safeTableText(String value) => sanitizeImportedInline(
  value.replaceAll('\r\n', '\n').replaceAll('\r', '\n'),
);

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

const int _maxRecommendations = 5;

const Map<String, String> _severityColors = {
  'critical': '#B00020',
  'high': '#EF4444',
  'medium': '#F59E0B',
  'low': '#2563EB',
  openKatOtherSeverity: '#64748B',
};

List<String> _visibleBands(Iterable<Map<String, int>> counts) => [
  ...openKatSeverityBands,
  if (counts.any((c) => (c[openKatOtherSeverity] ?? 0) > 0))
    openKatOtherSeverity,
];

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
      _safeTableText(stats[i].systemId),
      '${stats[i].total}',
      '${stats[i].critical}',
      '${stats[i].high}',
      '${stats[i].medium}',
      '${stats[i].low}',
      if (showOther) '${stats[i].other}',
    ],
];
