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
import 'openkat_slide_provenance.dart';

part 'openkat_report_composer_helpers.dart';

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
      'data-quality' =>
        english ? 'OpenKAT data quality' : 'OpenKAT-datakwaliteit',
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
      if (organizations.length > 1) _organizationAttentionSlide(portfolio),
      if (hasComparison && comparablePortfolio) _keyMessageSlide(portfolio),
      _portfolioSummarySlide(portfolio, compare: comparablePortfolio),
      _trendSlide(portfolio, compare: comparablePortfolio),
      _portfolioSurfaceSlide(portfolio),
      if (organizations.length > 1) ...[_severityMatrixSlide(portfolio)],
      _topIssuesSlide(portfolio, compare: comparablePortfolio),
      ?_recommendationsSlide(portfolio),
      _longestOpenSlide(portfolio),
      ?_controlsSlide(portfolio),
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
  }) => OpenKatSlideProvenance.markGeneratedOrigin(
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
    ),
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
      title: english ? 'Finding observations' : 'Waarnemingen van bevindingen',
      tableRows: [
        [
          english ? 'Organization' : 'Organisatie',
          english ? 'Finding' : 'Bevinding',
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
          english ? 'Finding' : 'Bevinding',
          english ? 'System' : 'Systeem',
          english ? 'Severity' : 'Ernst',
        ],
        for (final item in exposure.take(limit))
          [
            _inline(item.organizationCode),
            _inline(item.finding.findingTypeName ?? item.finding.findingTypeId),
            _inline(item.finding.systemId ?? '-'),
            _severityLabel(openKatSeverityBand(item.finding.severity)),
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
        title: _text('Bevindingen naar ernst', 'Findings by severity'),
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
        '${c.hostnames} ${_text('hostnamen', 'hostnames')}, '
            '${c.ipv4} IPv4, ${c.ipv6} IPv6',
        '${c.totalFindings} ${_text('bevindingen in', 'findings across')} '
            '${c.uniqueFindingTypes} ${_text('typen', 'types')}',
        '${c.criticalHighSystems} ${_text('systemen met kritieke of hoge bevindingen', 'systems with critical/high findings')}',
        _severityLine(c.severityCounts, english: _english),
      ],
      viewLimit: const DisplayWindowSpec(),
      notes: '<!-- ocideck_openkat_view: portfolio.surface -->',
    );
  }

  Slide _organizationAttentionSlide(PortfolioAggregate portfolio) {
    final organizations = facts
        .organizationAttention(portfolio.organizations)
        .where(
          (organization) => organization.critical > 0 || organization.high > 0,
        )
        .toList();
    if (organizations.isEmpty) {
      return _slide(
        id: _id('openkat-portfolio-orgs-attention'),
        type: SlideType.bullets,
        title: _text(
          'Deze organisaties vragen aandacht',
          'These organizations require attention',
        ),
        bullets: [
          _text(
            'Geen organisatie heeft in de huidige meting kritieke of hoge bevindingen.',
            'No organization has critical or high findings in the current measurement.',
          ),
        ],
        notes: '<!-- ocideck_openkat_view: portfolio.orgs-attention -->',
      );
    }
    return _slide(
      id: _id('openkat-portfolio-orgs-attention'),
      type: SlideType.table,
      title: _text(
        'Deze organisaties vragen aandacht',
        'These organizations require attention',
      ),
      subtitle: _text(
        'Gerangschikt op kritieke bevindingen, hoge bevindingen en getroffen systemen.',
        'Ranked by critical findings, high findings, and affected systems.',
      ),
      tableRows: [
        [
          _text('Organisatie', 'Organization'),
          _text('Waarom aandacht', 'Why attention is needed'),
          _text('Kritiek', 'Critical'),
          _text('Hoog', 'High'),
          _text('Getroffen systemen', 'Affected systems'),
        ],
        for (final organization in organizations)
          [
            _literal(organization.name),
            _attentionReason(organization),
            '${organization.critical}',
            '${organization.high}',
            '${organization.affectedSystems}',
          ],
      ],
      viewLimit: const DisplayWindowSpec(limit: 8),
      notes: '<!-- ocideck_openkat_view: portfolio.orgs-attention -->',
    );
  }

  Slide _topIssuesSlide(PortfolioAggregate portfolio, {required bool compare}) {
    final issues = facts.topIssues(portfolio.organizations);
    final showNew =
        compare && portfolio.organizations.any((o) => o.previous != null);
    final rows = <List<String>>[
      [
        '#',
        _text('Bevinding', 'Finding'),
        _text('Ernst', 'Severity'),
        _text('Systemen', 'Systems'),
        _text('Organisaties', 'Organizations'),
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
      title: _text('Meest voorkomende bevindingen', 'Most common findings'),
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
        _text('Bevinding', 'Finding'),
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
      title: _text(
        'Langst openstaande bevindingen',
        'Longest-observed findings',
      ),
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
      subtitle: history.length > 1 && !compare
          ? _text(
              'De meetdekking verschilt mogelijk. Lees deze meetreeks daarom niet als trend.',
              'Measurement coverage may differ. Do not interpret this series as a trend.',
            )
          : '',
      customMarkdown:
          (history.length > 1
                  ? _historyChart(
                      history,
                      title: compare
                          ? '${_text('Verloop', 'Trend')}: '
                                '${_trendLabel(conclusion)}'
                          : _text(
                              'Let op: meetdekking verschilt mogelijk — lees dit niet als trend',
                              'Caution: measurement coverage may differ — do not read this as a trend',
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

  Slide? _controlsSlide(PortfolioAggregate portfolio) {
    final current =
        portfolio.current.controls.values
            .where((control) => control.ratio != null)
            .toList()
          ..sort(
            (a, b) => _controlLabel(a.name).compareTo(_controlLabel(b.name)),
          );
    if (current.isEmpty) return null;

    return _slide(
      id: _id('openkat-portfolio-controls'),
      type: SlideType.table,
      title: _text('Beveiligingscontroles', 'Security controls'),
      tableRows: [
        [
          _text('Controle', 'Control'),
          _text('Voldoet', 'Compliant'),
          _text('Onderzocht', 'Assessed'),
          _text('Aandeel', 'Share'),
        ],
        for (final control in current)
          [
            _controlLabel(control.name),
            '${control.compliant}',
            '${control.total}',
            '${(control.ratio! * 100).round()}%',
          ],
      ],
      viewLimit: const DisplayWindowSpec(limit: 8),
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
            label: _text('Bevindingen', 'Findings'),
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
            title: _text('Bevindingen per meting', 'Findings by measurement'),
            english: _english,
          ).toBlock(),
          notes:
              '<!-- ocideck_openkat_view: org.${_safe(org.code)}.history -->',
        ),
      _slide(
        id: _id('openkat-org-${_safe(org.code)}-systems'),
        type: SlideType.table,
        title: _text(
          'Systemen met de meeste bevindingen',
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

  String _attentionReason(OpenKatOrganizationAttention organization) {
    if (organization.critical > 0) {
      return _english
          ? 'Critical: ${organization.critical} '
                '${organization.critical == 1 ? 'finding' : 'findings'}'
          : 'Kritiek: ${organization.critical} '
                '${organization.critical == 1 ? 'bevinding' : 'bevindingen'}';
    }
    if (organization.high > 0) {
      return _english
          ? 'High: ${organization.high} '
                '${organization.high == 1 ? 'finding' : 'findings'} across '
                '${organization.affectedSystems} affected '
                '${organization.affectedSystems == 1 ? 'system' : 'systems'}'
          : 'Hoog: ${organization.high} '
                '${organization.high == 1 ? 'bevinding' : 'bevindingen'} op '
                '${organization.affectedSystems} getroffen '
                '${organization.affectedSystems == 1 ? 'systeem' : 'systemen'}';
    }
    return _text(
      'Geen kritieke of hoge bevindingen',
      'No critical or high findings',
    );
  }

  String _controlLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.startsWith('rpki')) return 'RPKI${_termSuffix(value)}';
    if (normalized.startsWith('dnssec')) return 'DNSSEC${_termSuffix(value)}';
    if (normalized.startsWith('hsts')) return 'HSTS${_termSuffix(value)}';
    if (normalized.startsWith('security-txt') ||
        normalized.startsWith('security_txt') ||
        normalized.startsWith('security txt') ||
        normalized.startsWith('security.txt')) {
      return 'security.txt${_termSuffix(value)}';
    }
    if (normalized.startsWith('safe-connections')) {
      return '${_text('Veilige verbindingen', 'Safe connections')}'
          '${_termSuffix(value)}';
    }
    final words = value
        .replaceFirst(RegExp(r'-report$', caseSensitive: false), '')
        .replaceAll(RegExp('[-_]'), ' ')
        .trim();
    if (words.isEmpty) return _literal(value);
    return _literal('${words[0].toUpperCase()}${words.substring(1)}');
  }

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
      final controlId = _controlLabel(fact.controlId ?? '');
      return _english
          ? '$controlId coverage ${improved ? 'improved' : 'worsened'} '
                'from ${_percent(fact.previousRatio!)} to '
                '${_percent(fact.currentRatio!)}'
          : '$controlId: aandeel dat voldoet '
                '${improved ? 'gestegen' : 'gedaald'} van '
                '${_percent(fact.previousRatio!)} naar '
                '${_percent(fact.currentRatio!)}';
    }
    final count = fact.delta!.abs();
    final more = fact.delta! > 0;
    final metric = switch (fact.metric) {
      OpenKatTrendMetric.criticalFindings => _text(
        'kritieke bevindingen',
        'critical findings',
      ),
      OpenKatTrendMetric.highFindings => _text(
        'hoge bevindingen',
        'high findings',
      ),
      OpenKatTrendMetric.mediumFindings => _text(
        'middelzware bevindingen',
        'medium findings',
      ),
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
