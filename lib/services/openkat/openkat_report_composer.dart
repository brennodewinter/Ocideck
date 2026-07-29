import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import '../../models/chart.dart';
import '../../models/deck.dart';
import '../../models/display_window_spec.dart';
import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import '../../models/privacy_disposition.dart';
import '../../models/scorecard_spec.dart';
import '../../models/slide.dart';
import '../import/utils/import_text_sanitizer.dart';
import 'openkat_aggregator.dart';
import 'openkat_report_facts.dart';
import 'openkat_report_rankings.dart';
import 'openkat_slide_provenance.dart';

part 'openkat_report_composer_helpers.dart';
part 'openkat_report_composer_context.dart';
part 'openkat_report_composer_blocks.dart';
part 'openkat_report_composer_assets.dart';
part 'openkat_report_composer_security.dart';

const _openKatReportTitles = <String, ({String dutch, String english})>{
  'management-overview': (
    dutch: 'OpenKAT managementoverzicht',
    english: 'OpenKAT management overview',
  ),
  'weekly-comparison': (
    dutch: 'OpenKAT-weekvergelijking',
    english: 'OpenKAT weekly comparison',
  ),
  'organization-overview': (
    dutch: 'OpenKAT-organisatieoverzicht',
    english: 'OpenKAT organization overview',
  ),
  'cve-exposure': (
    dutch: 'OpenKAT CVE-blootstelling',
    english: 'OpenKAT CVE exposure',
  ),
  'monitoring-changes': (
    dutch: 'OpenKAT-monitoringmutaties',
    english: 'OpenKAT monitoring changes',
  ),
  'data-quality': (
    dutch: 'OpenKAT-datakwaliteit',
    english: 'OpenKAT data quality',
  ),
  'organization-comparison': (
    dutch: 'OpenKAT-organisatievergelijking',
    english: 'OpenKAT organization comparison',
  ),
  'portfolio-trend': (
    dutch: 'OpenKAT-portfolioverloop',
    english: 'OpenKAT portfolio trend',
  ),
  'finding-type-prevalence': (
    dutch: 'OpenKAT-veelvoorkomende findingtypen',
    english: 'OpenKAT common finding types',
  ),
  'critical-high-concentration': (
    dutch: 'OpenKAT-concentratie critical/high',
    english: 'OpenKAT critical/high concentration',
  ),
  'cve-landscape': (
    dutch: 'OpenKAT-CVE-landschap',
    english: 'OpenKAT CVE landscape',
  ),
  'cve-changes': (
    dutch: 'OpenKAT-CVE-veranderingen',
    english: 'OpenKAT CVE changes',
  ),
  'finding-lifecycle': (
    dutch: 'OpenKAT-findingveranderingen',
    english: 'OpenKAT finding changes',
  ),
  'finding-age': (
    dutch: 'OpenKAT-langst waargenomen findings',
    english: 'OpenKAT longest-observed findings',
  ),
  'system-hotspots': (
    dutch: 'OpenKAT-systeemaandacht',
    english: 'OpenKAT system hotspots',
  ),
  'system-changes': (
    dutch: 'OpenKAT-systeemveranderingen',
    english: 'OpenKAT system changes',
  ),
  'control-coverage': (
    dutch: 'OpenKAT-controldekking',
    english: 'OpenKAT control coverage',
  ),
  'control-changes': (
    dutch: 'OpenKAT-controlveranderingen',
    english: 'OpenKAT control changes',
  ),
  'recommendations-overview': (
    dutch: 'OpenKAT-aanbevelingenoverzicht',
    english: 'OpenKAT recommendations',
  ),
  'asset-inventory': (
    dutch: 'OpenKAT-assetinventaris',
    english: 'OpenKAT asset inventory',
  ),
  'monitoring-coverage': (
    dutch: 'OpenKAT-monitoringdekking',
    english: 'OpenKAT monitoring coverage',
  ),
  'measurement-accountability': (
    dutch: 'OpenKAT-meetverantwoording',
    english: 'OpenKAT measurement accountability',
  ),
};

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

  static const _legacyManagementViewAliases = <String, String>{
    'portfolio.summary': 'report.management-overview.portfolio-summary.summary',
    'portfolio.key-message':
        'report.management-overview.portfolio-summary.key-message',
    'portfolio.surface': 'report.management-overview.portfolio-summary.scope',
    'portfolio.orgs-attention':
        'report.management-overview.organization-comparison.most',
    'portfolio.orgs-compared':
        'report.management-overview.organization-comparison.most',
    'portfolio.trend': 'report.management-overview.portfolio-trend.severity',
    'portfolio.severity-matrix':
        'report.management-overview.severity-concentration.organizations',
    'portfolio.recommendations':
        'report.management-overview.recommendations.ranking',
    'portfolio.controls':
        'report.management-overview.control-coverage.coverage',
    'portfolio.longest-open': 'report.management-overview.finding-age.ranking',
    'portfolio.top-issues':
        'report.management-overview.finding-type-prevalence.ranking',
  };

  static String canonicalManagementViewId(String view) {
    final alias = _legacyManagementViewAliases[view];
    if (alias != null) return alias;
    if (view.startsWith('org.')) {
      return 'report.management-overview.system-hotspots.$view';
    }
    return view;
  }

  Deck compose(
    OpenKatReportRequest request,
    OpenKatReportPlan plan, {
    String? outputPath,
  }) {
    final selections =
        (request.scenarioId == 'management-overview'
                ? facts.comparisonSelections(request)
                : facts.selections(request))
            .where((selection) => selection.current != null)
            .toList();
    final organizations = [
      for (final selection in selections)
        selection.organization.copyWith(
          snapshots: [
            if (selection.previous != null) selection.previous!,
            selection.current!,
          ],
        ),
    ];
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
    final blocks = _OpenKatReportBlockRenderer(this);
    var deck = Deck(
      title: _literal(title),
      projectPath: outputPath ?? '',
      version: '1.0',
      language: request.language.code,
      slides: [blocks.reportTitle(request, title, organizations)],
    );

    final security = _OpenKatReportSecurityRenderer(this);
    final assets = _OpenKatReportAssetRenderer(this);
    final renderers =
        <OpenKatReportBlockKind, List<Slide> Function(OpenKatReportBlock)>{
          OpenKatReportBlockKind.managementOverview: (block) =>
              blocks.legacyManagement(
                request,
                block,
                organizations: organizations,
                comparablePortfolio: comparablePortfolio,
                comparableOrganizations: comparableOrganizations,
              ),
          OpenKatReportBlockKind.portfolioSummary: (block) =>
              blocks.portfolioSummary(request, block),
          OpenKatReportBlockKind.organizationComparison: (block) =>
              blocks.organizationComparison(request, block),
          OpenKatReportBlockKind.severityConcentration: (block) =>
              blocks.severityConcentration(request, block),
          OpenKatReportBlockKind.portfolioTrend: (block) =>
              blocks.portfolioTrend(request, block),
          OpenKatReportBlockKind.findingTypePrevalence: (block) =>
              blocks.findingTypePrevalence(request, block),
          OpenKatReportBlockKind.measurementAvailability: (block) =>
              blocks.measurementAvailability(request, block),
          OpenKatReportBlockKind.measurementAccountability: (block) =>
              blocks.measurementAccountability(request, block),
          OpenKatReportBlockKind.findingLifecycle: (block) =>
              blocks.findingLifecycle(request, block),
          OpenKatReportBlockKind.findingAge: (block) =>
              blocks.findingAge(request, block),
          OpenKatReportBlockKind.systemHotspots: (block) =>
              blocks.systemHotspots(request, block),
          OpenKatReportBlockKind.systemChanges: (block) =>
              blocks.systemChanges(request, block),
          OpenKatReportBlockKind.cveExposure: (block) =>
              security.cveExposure(request, block),
          OpenKatReportBlockKind.cveLandscape: (block) =>
              security.cveLandscape(request, block),
          OpenKatReportBlockKind.cveChanges: (block) =>
              security.cveChanges(request, block),
          OpenKatReportBlockKind.controlCoverage: (block) =>
              security.controlCoverage(request, block),
          OpenKatReportBlockKind.controlChanges: (block) =>
              security.controlChanges(request, block),
          OpenKatReportBlockKind.recommendations: (block) =>
              security.recommendations(request, block),
          OpenKatReportBlockKind.assetInventory: (block) =>
              assets.assetInventory(request, block),
          OpenKatReportBlockKind.monitoringCoverage: (block) =>
              assets.monitoringCoverage(request, block),
          OpenKatReportBlockKind.monitoringChanges: (block) =>
              assets.monitoringChanges(request, block),
          OpenKatReportBlockKind.organizationOverview: (block) =>
              assets.organizationOverview(request, block),
        };
    for (final block in plan.blocks) {
      final legacySlides = request.scenarioId == 'management-overview'
          ? blocks.declarativeManagement(
              request,
              block,
              organizations: organizations,
              comparablePortfolio: comparablePortfolio,
              comparableOrganizations: comparableOrganizations,
            )
          : null;
      final slides = legacySlides ?? renderers[block.kind]!(block);
      deck = deck.copyWith(
        language: request.language.code,
        slides: [...deck.slides, ...slides],
      );
    }
    return deck;
  }

  String _defaultTitle(OpenKatReportRequest request) {
    final titles =
        _openKatReportTitles[request.scenarioId] ??
        _openKatReportTitles['management-overview']!;
    return request.language == OpenKatReportLanguage.english
        ? titles.english
        : titles.dutch;
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
    PrivacyDisposition? privacy,
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
      privacy: privacy,
    ),
  );

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

  List<String> _emptyResultRow({required int columns}) => [
    _text(
      'Geen betrouwbare resultaten binnen de gekozen metingen',
      'No reliable results within the selected measurements',
    ),
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
          label: _text('Kwetsbare systemen', 'Vulnerable systems'),
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
        'Gerangschikt op kritieke bevindingen, hoge bevindingen en kwetsbare systemen.',
        'Ranked by critical findings, high findings, and vulnerable systems.',
      ),
      tableRows: [
        [
          _text('Organisatie', 'Organization'),
          _text('Waarom aandacht', 'Why attention is needed'),
          _text('Kritiek', 'Critical'),
          _text('Hoog', 'High'),
          _text('Kwetsbare systemen', 'Vulnerable systems'),
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
                '${organization.affectedSystems} '
                '${organization.affectedSystems == 1 ? 'vulnerable system' : 'vulnerable systems'}'
          : 'Hoog: ${organization.high} '
                '${organization.high == 1 ? 'bevinding' : 'bevindingen'} op '
                '${organization.affectedSystems} '
                '${organization.affectedSystems == 1 ? 'kwetsbaar systeem' : 'kwetsbare systemen'}';
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
        'kwetsbare systemen',
        'vulnerable systems',
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
