import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/models/scorecard_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_safety.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/openkat/openkat_aggregator.dart';
import 'package:ocideck/services/openkat/openkat_report_composer.dart';
import 'package:ocideck/services/openkat/openkat_report_facts.dart';

OpenKatFinding _finding(
  String id, {
  String severity = 'high',
  String? name,
  String? typeId,
  String? systemId,
  String? recommendation,
  List<String> cveIds = const [],
  bool stableIdentity = true,
}) => OpenKatFinding(
  id: id,
  findingTypeId: typeId ?? 'KAT-$id',
  findingTypeName: name ?? 'Finding $id',
  severity: severity,
  systemId: systemId ?? 'asset-$id.example',
  recommendation: recommendation,
  cveIds: cveIds,
  stableIdentity: stableIdentity,
);

OpenKatSnapshot _snapshot(
  DateTime date, {
  required String source,
  List<OpenKatFinding> findings = const [],
  Set<OpenKatSourceFeature> sourceFeatures = const {},
  String? measurementScopeId,
  Map<String, OpenKatControlScore> controls = const {},
  List<OpenKatSystem>? systems,
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: source,
  sourceHash: 'sha256:$source',
  systems:
      systems ??
      [
        for (final finding in findings)
          OpenKatSystem(
            id: finding.systemId!,
            hostname: finding.systemId,
            stableIdentity: true,
          ),
      ],
  findings: findings,
  sourceFeatures: sourceFeatures,
  measurementScopeId: measurementScopeId,
  controls: controls,
);

OpenKatOrganization _organization(
  List<OpenKatSnapshot> snapshots, {
  String code = 'alpha',
  String name = 'Alpha',
}) => OpenKatOrganization(code: code, name: name, snapshots: snapshots);

OpenKatReportRequest _request(
  String scenarioId, {
  OpenKatReportLanguage language = OpenKatReportLanguage.dutch,
  OpenKatReportPolicy policy = const OpenKatReportPolicy(),
  String? cveId,
  DateTime? previousAsOf,
}) => OpenKatReportRequest(
  scenarioId: scenarioId,
  scope: const OpenKatReportScope.portfolio(),
  currentAsOf: DateTime.utc(2026, 7, 20),
  language: language,
  policy: policy,
  cveId: cveId,
  previousAsOf: previousAsOf,
);

Slide _slideWithTitle(Iterable<Slide> slides, String title) =>
    slides.singleWhere((slide) => slide.title == title);

String _visibleText(Iterable<Slide> slides) {
  final parts = <String>[];
  for (final slide in slides) {
    parts.addAll([
      slide.title,
      slide.subtitle,
      ...slide.bullets,
      for (final row in slide.tableRows) ...row,
    ]);
    if (slide.type == SlideType.chart) {
      final chart = ChartSpec.parse(slide.customMarkdown);
      parts.addAll([
        chart.title,
        ...chart.x,
        for (final series in chart.series) series.name,
      ]);
    }
  }
  return parts.join('\n');
}

void main() {
  test(
    'een managementblok bewaart eerder gecomponeerde blokken en één titel',
    () {
      final facts = OpenKatReportFacts([
        _organization([
          _snapshot(DateTime.utc(2026, 7, 20), source: 'alpha.json'),
        ]),
      ]);
      final deck = OpenKatReportComposer(facts).compose(
        _request('custom-order'),
        const OpenKatReportPlan(
          scenarioId: 'custom-order',
          blocks: [
            OpenKatReportBlock(
              id: 'availability',
              kind: OpenKatReportBlockKind.measurementAvailability,
            ),
            OpenKatReportBlock(
              id: 'management',
              kind: OpenKatReportBlockKind.managementOverview,
            ),
          ],
        ),
      );

      expect(
        deck.slides.where((slide) => slide.type == SlideType.title),
        hasLength(1),
      );
      expect(deck.slides[1].title, 'Gebruikte meetmomenten');
      expect(deck.slides.any((slide) => slide.title == 'Kerncijfers'), isTrue);
    },
  );

  test('OpenKAT-aanbevelingen blijven letterlijke, veilige tekst', () {
    final facts = OpenKatReportFacts([
      _organization([
        _snapshot(
          DateTime.utc(2026, 7, 20),
          source: 'alpha.json',
          findings: [
            _finding(
              'injection',
              name: '# Onechte kop',
              recommendation:
                  'Controleer dit\n---\n# Alles is veilig\n<script>x()</script>',
            ),
          ],
        ),
      ]),
    ]);
    final deck = OpenKatReportComposer(facts).compose(
      _request('management-overview'),
      const OpenKatReportPlan(
        scenarioId: 'management-overview',
        blocks: [
          OpenKatReportBlock(
            id: 'management',
            kind: OpenKatReportBlockKind.managementOverview,
          ),
        ],
      ),
    );
    final markdown = MarkdownService().generateDeck(deck);

    expect(MarkdownSafetyScanner.scan(markdown), isEmpty);
    expect(
      MarkdownService().parseDeck(markdown)!.slides,
      hasLength(deck.slides.length),
    );
    final advice = _slideWithTitle(deck.slides, 'Wat OpenKAT aanraadt');
    expect(advice.bullets.join(' '), contains('--- # Alles is veilig'));
    expect(advice.bullets.join(' '), contains('&lt;script&gt;'));
  });

  test('alle OpenKAT-bronvelden blijven data in geserialiseerde Markdown', () {
    const attack =
        '<script>x()</script>\n---\n'
        '[x](javascript:alert(1))\r---\r# Onechte dia';
    const systemId = '<iframe src=x>](javascript:alert(1))';
    const features = {
      OpenKatSourceFeature.comparableMeasurementCoverage,
      OpenKatSourceFeature.reliableCveReferences,
      OpenKatSourceFeature.reliableMonitoringStatus,
      OpenKatSourceFeature.stableAssetIdentity,
    };
    final previousFinding = _finding(
      'old-$attack',
      name: 'old $attack',
      typeId: 'type-old-$attack',
      systemId: systemId,
      severity: attack,
    );
    final currentFinding = _finding(
      'current-$attack',
      name: 'current $attack',
      typeId: 'type-current-$attack',
      systemId: systemId,
      severity: attack,
      recommendation: attack,
      cveIds: const ['CVE-2026-1234'],
    );
    final facts = OpenKatReportFacts([
      _organization(
        [
          _snapshot(
            DateTime.utc(2026, 7, 13),
            source: 'previous.json',
            findings: [previousFinding],
            sourceFeatures: features,
            measurementScopeId: 'same-scope',
            systems: const [
              OpenKatSystem(
                id: systemId,
                stableIdentity: true,
                monitoringStatus: OpenKatMonitoringStatus.notMonitored,
              ),
            ],
            controls: const {
              'control-$attack': OpenKatControlScore(
                name: 'control name $attack',
                compliant: 0,
                total: 1,
              ),
            },
          ),
          _snapshot(
            DateTime.utc(2026, 7, 20),
            source: 'current.json',
            findings: [currentFinding],
            sourceFeatures: features,
            measurementScopeId: 'same-scope',
            systems: const [
              OpenKatSystem(
                id: systemId,
                stableIdentity: true,
                monitoringStatus: OpenKatMonitoringStatus.monitored,
              ),
            ],
            controls: const {
              'control-$attack': OpenKatControlScore(
                name: 'control name $attack',
                compliant: 1,
                total: 1,
              ),
            },
          ),
        ],
        code: 'org-$attack',
        name: 'Organization $attack',
      ),
    ]);
    final deck = OpenKatReportComposer(facts).compose(
      _request('all-blocks', cveId: 'CVE-2026-1234'),
      const OpenKatReportPlan(
        scenarioId: 'all-blocks',
        blocks: [
          OpenKatReportBlock(
            id: 'management',
            kind: OpenKatReportBlockKind.managementOverview,
          ),
          OpenKatReportBlock(
            id: 'availability',
            kind: OpenKatReportBlockKind.measurementAvailability,
          ),
          OpenKatReportBlock(
            id: 'lifecycle',
            kind: OpenKatReportBlockKind.findingLifecycle,
          ),
          OpenKatReportBlock(
            id: 'cve',
            kind: OpenKatReportBlockKind.cveExposure,
          ),
          OpenKatReportBlock(
            id: 'monitoring',
            kind: OpenKatReportBlockKind.monitoringChanges,
          ),
        ],
      ),
    );
    final markdown = MarkdownService().generateDeck(deck);

    expect(MarkdownSafetyScanner.scan(markdown), isEmpty);
    expect(markdown, isNot(contains('<script>')));
    expect(markdown, isNot(contains('<iframe')));
    expect(
      MarkdownService().parseDeck(markdown)!.slides,
      hasLength(deck.slides.length),
    );
  });

  test(
    'zonder vergelijkbare dekking blijven conclusies en delta-opmaak weg',
    () {
      final previous = _snapshot(
        DateTime.utc(2026, 7, 13),
        source: 'previous.json',
        findings: [_finding('old', severity: 'critical')],
      );
      final current = _snapshot(
        DateTime.utc(2026, 7, 20),
        source: 'current.json',
        findings: [_finding('new', severity: 'medium')],
      );
      final facts = OpenKatReportFacts([
        _organization([previous, current]),
      ]);
      final deck = OpenKatReportComposer(facts).compose(
        _request('management-overview'),
        const OpenKatReportPlan(
          scenarioId: 'management-overview',
          blocks: [
            OpenKatReportBlock(
              id: 'management',
              kind: OpenKatReportBlockKind.managementOverview,
            ),
          ],
        ),
      );

      expect(
        deck.slides.any(
          (slide) => slide.notes.contains(
            'ocideck_openkat_view: portfolio.comparison-warning',
          ),
        ),
        isFalse,
        reason:
            'de trendbeperking hoort bij de trend en niet op een losse '
            'technische waarschuwingsdia',
      );
      expect(
        deck.slides.any(
          (slide) =>
              slide.title == 'Wat dit rapport zegt' ||
              slide.title.contains('meest verbeterden'),
        ),
        isFalse,
      );
      final summary = _slideWithTitle(deck.slides, 'Kerncijfers');
      final scorecard = ScorecardSpec.fromSlide(
        summary.title,
        summary.tableRows,
      );
      expect(
        scorecard.entries.every((entry) => entry.previous == null),
        isTrue,
      );
      final trend = deck.slides.singleWhere(
        (slide) =>
            slide.notes.contains('ocideck_openkat_view: portfolio.trend'),
      );
      final trendText = [
        trend.title,
        trend.subtitle,
        ...trend.bullets,
        ChartSpec.parse(trend.customMarkdown).title,
      ].join(' ').toLowerCase();
      expect(trendText, isNot(contains('verbeter')));
      expect(trendText, isNot(contains('verslechter')));
      expect(
        deck.slides
            .expand((slide) => [slide.title, slide.subtitle, ...slide.bullets])
            .join(' '),
        isNot(anyOf(contains('Beter'), contains('Slechter'))),
      );
    },
  );

  test(
    'een Nederlands managementdeck gebruikt begrijpelijke Nederlandse taal',
    () {
      final facts = OpenKatReportFacts([
        _organization([
          _snapshot(
            DateTime.utc(2026, 7, 20),
            source: 'alpha.json',
            findings: [
              _finding('kritiek', severity: 'critical', name: 'Onveilige bron'),
              _finding('hoog', severity: 'high', name: 'Open beheerpoort'),
              _finding(
                'middel',
                severity: 'medium',
                name: 'Verouderd protocol',
              ),
              _finding('laag', severity: 'low', name: 'Ontbrekende koptekst'),
            ],
            controls: const {
              'rpki-report': OpenKatControlScore(
                name: 'rpki-report',
                compliant: 1,
                total: 2,
              ),
            },
          ),
        ], name: 'Voorbeeldorganisatie'),
      ]);
      final deck = OpenKatReportComposer(facts).compose(
        _request('management-overview'),
        const OpenKatReportPlan(
          scenarioId: 'management-overview',
          blocks: [
            OpenKatReportBlock(
              id: 'management',
              kind: OpenKatReportBlockKind.managementOverview,
            ),
          ],
        ),
      );
      final visible = _visibleText(deck.slides);
      final lower = visible.toLowerCase();

      expect(visible, contains('Kritiek'));
      expect(visible, contains('Hoog'));
      expect(visible, contains('Middel'));
      expect(visible, contains('Laag'));
      for (final forbidden in [
        RegExp(r'\bfindings?\b'),
        RegExp(r'\bcritical\b'),
        RegExp(r'\bhigh\b'),
        RegExp(r'\bernstband\b'),
        RegExp(r'\bpercentage conform\b'),
        RegExp(r'\bgetroffen system(?:en)?\b'),
      ]) {
        expect(
          forbidden.hasMatch(lower),
          isFalse,
          reason: 'zichtbare rapporttekst bevat nog `$forbidden`:\n$visible',
        );
      }
    },
  );

  test('de rijlimiet begrenst CVE-rijen vóór deckmaterialisatie', () {
    final findings = [
      for (var i = 0; i < 100; i++)
        _finding('$i', cveIds: const ['CVE-2026-1234']),
    ];
    final facts = OpenKatReportFacts([
      _organization([
        _snapshot(
          DateTime.utc(2026, 7, 20),
          source: 'alpha.json',
          findings: findings,
          sourceFeatures: const {OpenKatSourceFeature.reliableCveReferences},
        ),
      ]),
    ]);
    final deck = OpenKatReportComposer(facts).compose(
      _request(
        'cve-exposure',
        cveId: 'CVE-2026-1234',
        policy: const OpenKatReportPolicy(tableRowLimit: 3),
      ),
      const OpenKatReportPlan(
        scenarioId: 'cve-exposure',
        blocks: [
          OpenKatReportBlock(
            id: 'cve',
            kind: OpenKatReportBlockKind.cveExposure,
          ),
        ],
      ),
    );
    final exposure = _slideWithTitle(
      deck.slides,
      'Blootstelling aan CVE-2026-1234',
    );

    expect(exposure.tableRows, hasLength(5));
    expect(exposure.tableRows.last.first, contains('Meer resultaten'));
    expect(exposure.viewLimit, isNull);
  });

  test('assetinventaris kapt zichtbaar af en is standaard weggelaten', () {
    final facts = OpenKatReportFacts([
      _organization([
        _snapshot(
          DateTime.utc(2026, 7, 20),
          source: 'assets.json',
          systems: [
            for (var i = 0; i < 4; i++)
              OpenKatSystem(
                id: 'asset-$i.example',
                hostname: 'asset-$i.example',
                ip: '192.0.2.${i + 1}',
              ),
          ],
        ),
      ]),
    ]);
    final deck = OpenKatReportComposer(facts).compose(
      _request(
        'asset-inventory',
        policy: const OpenKatReportPolicy(tableRowLimit: 2),
      ),
      const OpenKatReportPlan(
        scenarioId: 'asset-inventory',
        blocks: [
          OpenKatReportBlock(
            id: 'assets',
            kind: OpenKatReportBlockKind.assetInventory,
          ),
        ],
      ),
    );
    final inventory = _slideWithTitle(
      deck.slides,
      'Systemen in de gekozen metingen',
    );

    expect(inventory.privacy, PrivacyDisposition.redact);
    expect(inventory.tableRows, hasLength(4));
    expect(inventory.tableRows.last.first, contains('Meer resultaten'));
    expect(inventory.viewLimit, isNull);
  });

  test('severityconcentratie begrenst grafiek en tabellen zichtbaar', () {
    final facts = OpenKatReportFacts([
      for (var i = 0; i < 4; i++)
        _organization(
          [
            _snapshot(
              DateTime.utc(2026, 7, 20),
              source: 'org-$i.json',
              findings: [
                _finding(
                  '$i',
                  severity: 'critical',
                  typeId: 'TYPE-$i',
                  systemId: 'asset-$i.example',
                ),
              ],
            ),
          ],
          code: 'org-$i',
          name: 'Organisatie $i',
        ),
    ]);
    final deck = OpenKatReportComposer(facts).compose(
      _request(
        'critical-high-concentration',
        policy: const OpenKatReportPolicy(tableRowLimit: 2),
      ),
      const OpenKatReportPlan(
        scenarioId: 'critical-high-concentration',
        blocks: [
          OpenKatReportBlock(
            id: 'concentration',
            kind: OpenKatReportBlockKind.severityConcentration,
          ),
        ],
      ),
    );
    final chart = _slideWithTitle(deck.slides, 'Critical/high per organisatie');
    final systems = _slideWithTitle(
      deck.slides,
      'Systemen met de meeste critical/high findings',
    );
    final types = _slideWithTitle(
      deck.slides,
      'Findingtypen achter de concentratie',
    );

    expect(ChartSpec.parse(chart.customMarkdown).x, hasLength(2));
    expect(chart.subtitle, contains('Meer organisaties weggelaten'));
    for (final table in [systems, types]) {
      expect(table.tableRows.last.first, contains('Meer resultaten'));
      expect(table.viewLimit, isNull);
    }
  });

  test('minste organisaties gebruikt dezelfde critical-high-rangschikking', () {
    OpenKatOrganization organization(
      String code, {
      int critical = 0,
      int high = 0,
    }) => _organization(
      [
        _snapshot(
          DateTime.utc(2026, 7, 20),
          source: '$code.json',
          findings: [
            for (var i = 0; i < critical; i++)
              _finding('$code-c$i', severity: 'critical'),
            for (var i = 0; i < high; i++)
              _finding('$code-h$i', severity: 'high'),
          ],
        ),
      ],
      code: code,
      name: code.toUpperCase(),
    );

    final deck =
        OpenKatReportComposer(
          OpenKatReportFacts([
            organization('alpha', critical: 2),
            organization('beta', high: 1),
            organization('gamma'),
          ]),
        ).compose(
          _request(
            'organization-comparison',
            policy: const OpenKatReportPolicy(tableRowLimit: 2),
          ),
          const OpenKatReportPlan(
            scenarioId: 'organization-comparison',
            blocks: [
              OpenKatReportBlock(
                id: 'organizations',
                kind: OpenKatReportBlockKind.organizationComparison,
              ),
            ],
          ),
        );
    final least = _slideWithTitle(
      deck.slides,
      'Minste waargenomen critical/high findings',
    );

    expect(least.tableRows[1].first, 'GAMMA');
    expect(least.tableRows[2].first, 'BETA');
    expect(least.tableRows.last.first, contains('Meer resultaten'));
    expect(least.viewLimit, isNull);
  });

  test('trenddekking gebruikt de viewlimiet uit het blokregister', () {
    final facts = OpenKatReportFacts([
      _organization([
        _snapshot(DateTime.utc(2026, 7, 13), source: 'previous.json'),
        _snapshot(DateTime.utc(2026, 7, 20), source: 'current.json'),
      ]),
    ]);
    final deck = OpenKatReportComposer(facts).compose(
      _request('portfolio-trend'),
      const OpenKatReportPlan(
        scenarioId: 'portfolio-trend',
        blocks: [
          OpenKatReportBlock(
            id: 'trend',
            kind: OpenKatReportBlockKind.portfolioTrend,
          ),
        ],
      ),
    );
    final coverage = _slideWithTitle(
      deck.slides,
      'Bijdrage en carried-forward metingen',
    );

    expect(
      coverage.viewLimit?.limit,
      OpenKatReportBlockRegistry.definition(
        OpenKatReportBlockKind.portfolioTrend,
      ).viewLimit,
    );
  });

  test('Engelse trendtekst wordt uit getypepte feiten opgebouwd', () {
    final previous = _snapshot(
      DateTime.utc(2026, 7, 13),
      source: 'previous.json',
      findings: [_finding('old', severity: 'critical')],
      sourceFeatures: const {
        OpenKatSourceFeature.comparableMeasurementCoverage,
      },
      measurementScopeId: 'same-scope',
    );
    final current = _snapshot(
      DateTime.utc(2026, 7, 20),
      source: 'current.json',
      sourceFeatures: const {
        OpenKatSourceFeature.comparableMeasurementCoverage,
      },
      measurementScopeId: 'same-scope',
    );
    final facts = OpenKatReportFacts([
      _organization([previous, current]),
    ]);
    final deck =
        OpenKatReportComposer(
          facts,
          language: OpenKatReportLanguage.english,
        ).compose(
          _request(
            'management-overview',
            language: OpenKatReportLanguage.english,
            previousAsOf: DateTime.utc(2026, 7, 13),
          ),
          const OpenKatReportPlan(
            scenarioId: 'management-overview',
            blocks: [
              OpenKatReportBlock(
                id: 'management',
                kind: OpenKatReportBlockKind.managementOverview,
              ),
            ],
          ),
        );
    final keyMessage = _slideWithTitle(deck.slides, 'What this report says');

    expect(keyMessage.bullets, contains('1 fewer critical findings'));
    final conclusion = facts.compare(
      facts.aggregateSnapshot(current),
      facts.aggregateSnapshot(previous),
    );
    final critical = conclusion.facts.singleWhere(
      (fact) => fact.metric == OpenKatTrendMetric.criticalFindings,
    );
    expect(critical.delta, -1);
  });
}
