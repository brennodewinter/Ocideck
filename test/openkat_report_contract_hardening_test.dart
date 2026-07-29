import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/services/openkat/openkat_report_engine.dart';
import 'package:ocideck/services/openkat/openkat_report_facts.dart';
import 'package:ocideck/services/openkat/openkat_report_scenarios.dart';

OpenKatFinding _finding({required String id, bool stableIdentity = true}) =>
    OpenKatFinding(
      id: id,
      findingTypeId: 'KAT-$id',
      severity: 'high',
      systemId: 'asset.example',
      stableIdentity: stableIdentity,
    );

OpenKatSnapshot _snapshot({
  required DateTime date,
  required String source,
  List<OpenKatFinding> findings = const [],
  List<OpenKatSystem>? systems,
  Set<OpenKatSourceFeature> sourceFeatures = const {},
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: source,
  sourceHash: 'sha256:$source',
  systems:
      systems ??
      const [OpenKatSystem(id: 'asset.example', stableIdentity: true)],
  findings: findings,
  sourceFeatures: sourceFeatures,
);

OpenKatOrganization _organization(List<OpenKatSnapshot> snapshots) =>
    OpenKatOrganization(code: 'alpha', name: 'Alpha', snapshots: snapshots);

OpenKatReportRequest _weeklyRequest({
  DateTime? currentAsOf,
  DateTime? previousAsOf,
}) => OpenKatReportRequest(
  scenarioId: 'weekly-comparison',
  scope: const OpenKatReportScope.portfolio(),
  currentAsOf: currentAsOf ?? DateTime.utc(2026, 7, 20),
  previousAsOf: previousAsOf ?? DateTime.utc(2026, 7, 10),
);

bool _hasDiagnostic(
  OpenKatReportResult result,
  OpenKatReportDiagnosticCode code,
) => result.diagnostics.any((diagnostic) => diagnostic.code == code);

class _CustomScenario implements OpenKatReportScenario {
  @override
  final OpenKatScenarioDescriptor descriptor;
  final OpenKatReportPlan plan;

  const _CustomScenario({required this.descriptor, required this.plan});

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => plan;
}

void main() {
  group('chronologisch snapshotcontract', () {
    test('previousAsOf moet strikt vóór currentAsOf liggen', () {
      final organization = _organization([
        _snapshot(date: DateTime.utc(2026, 7, 10), source: 'alpha.json'),
      ]);

      for (final previousAsOf in [
        DateTime.utc(2026, 7, 20),
        DateTime.utc(2026, 7, 21),
      ]) {
        final result = OpenKatReportEngine().generate([
          organization,
        ], _weeklyRequest(previousAsOf: previousAsOf));

        expect(result.generated, isFalse);
        expect(
          _hasDiagnostic(
            result,
            OpenKatReportDiagnosticCode.invalidSnapshotChronology,
          ),
          isTrue,
        );
      }
    });

    test(
      'één snapshot onder twee peildata is geen historische vergelijking',
      () {
        final result = OpenKatReportEngine().generate([
          _organization([
            _snapshot(
              date: DateTime.utc(2026, 7, 5),
              source: 'alpha-only.json',
            ),
          ]),
        ], _weeklyRequest());

        expect(result.generated, isFalse);
        expect(
          result.missingCapabilities,
          contains(OpenKatReportCapability.historicalSnapshots),
        );
      },
    );
  });

  group('conditionele weekrapportblokken', () {
    test('laat lifecycle weg wanneer stabiele findingidentiteit ontbreekt', () {
      final result = OpenKatReportEngine().generate([
        _organization([
          _snapshot(
            date: DateTime.utc(2026, 7, 5),
            source: 'alpha-previous.json',
            findings: [_finding(id: 'old', stableIdentity: false)],
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 15),
            source: 'alpha-current.json',
            findings: [_finding(id: 'new', stableIdentity: false)],
          ),
        ]),
      ], _weeklyRequest());

      expect(result.generated, isTrue);
      expect(
        result.missingCapabilities,
        contains(OpenKatReportCapability.findingLifecycle),
      );
      expect(
        result.plan!.blocks.map((block) => block.kind),
        isNot(contains(OpenKatReportBlockKind.findingLifecycle)),
      );
      expect(
        result.plan!.blocks.map((block) => block.kind),
        containsAll([
          OpenKatReportBlockKind.portfolioSummary,
          OpenKatReportBlockKind.portfolioTrend,
          OpenKatReportBlockKind.measurementAvailability,
        ]),
      );
    });

    test('behoudt lifecycle wanneer de capability aantoonbaar is', () {
      final result = OpenKatReportEngine().generate([
        _organization([
          _snapshot(
            date: DateTime.utc(2026, 7, 5),
            source: 'alpha-previous.json',
            findings: [_finding(id: 'old')],
            sourceFeatures: const {OpenKatSourceFeature.stableFindingIdentity},
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 15),
            source: 'alpha-current.json',
            findings: [_finding(id: 'new')],
            sourceFeatures: const {OpenKatSourceFeature.stableFindingIdentity},
          ),
        ]),
      ], _weeklyRequest());

      expect(result.generated, isTrue);
      expect(
        result.plan!.blocks.map((block) => block.kind),
        contains(OpenKatReportBlockKind.findingLifecycle),
      );
    });
  });

  test(
    'managementvergelijking zonder dekkingsbewijs waarschuwt in diagnose en trend',
    () {
      final result = OpenKatReportEngine().generate(
        [
          _organization([
            _snapshot(
              date: DateTime.utc(2026, 7, 5),
              source: 'alpha-previous.json',
              findings: [_finding(id: 'old')],
            ),
            _snapshot(
              date: DateTime.utc(2026, 7, 15),
              source: 'alpha-current.json',
              findings: [_finding(id: 'new')],
            ),
          ]),
        ],
        OpenKatReportRequest(
          scenarioId: 'management-overview',
          scope: const OpenKatReportScope.portfolio(),
          currentAsOf: DateTime.utc(2026, 7, 20),
        ),
      );

      expect(result.generated, isTrue);
      expect(
        _hasDiagnostic(
          result,
          OpenKatReportDiagnosticCode.incomparableMeasurementCoverage,
        ),
        isTrue,
      );
      final trend = result.deck!.slides.singleWhere(
        (slide) => slide.notes.contains(
          'ocideck_openkat_view: '
          'report.management-overview.portfolio-trend.severity',
        ),
      );
      final chartTitle = ChartSpec.parse(trend.customMarkdown).title;
      expect(
        chartTitle,
        allOf(contains('meetdekking'), contains('niet als trend')),
      );
      expect(
        trend.subtitle,
        allOf(contains('meetdekking'), contains('niet als trend')),
      );
    },
  );

  test('monitoringcapability sluit bij een onbekende assetstatus', () {
    const features = {
      OpenKatSourceFeature.stableAssetIdentity,
      OpenKatSourceFeature.reliableMonitoringStatus,
    };
    final result = OpenKatReportEngine().generate(
      [
        _organization([
          _snapshot(
            date: DateTime.utc(2026, 7, 5),
            source: 'previous.json',
            sourceFeatures: features,
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 15),
            source: 'current.json',
            sourceFeatures: features,
          ),
        ]),
      ],
      OpenKatReportRequest(
        scenarioId: 'monitoring-changes',
        scope: const OpenKatReportScope.portfolio(),
        currentAsOf: DateTime.utc(2026, 7, 20),
        previousAsOf: DateTime.utc(2026, 7, 10),
      ),
    );

    expect(result.generated, isFalse);
    expect(
      result.missingCapabilities,
      contains(OpenKatReportCapability.reliableMonitoringStatus),
    );
  });

  group('fail-closed custom scenario', () {
    test('weigert twee blokken met dezelfde soort', () {
      const scenario = _CustomScenario(
        descriptor: OpenKatScenarioDescriptor(
          id: 'custom-duplicate-kind',
          scopes: {OpenKatReportScopeKind.portfolio},
        ),
        plan: OpenKatReportPlan(
          scenarioId: 'custom-duplicate-kind',
          blocks: [
            OpenKatReportBlock(
              id: 'management-a',
              kind: OpenKatReportBlockKind.managementOverview,
            ),
            OpenKatReportBlock(
              id: 'management-b',
              kind: OpenKatReportBlockKind.managementOverview,
            ),
          ],
        ),
      );
      final result =
          OpenKatReportEngine(
            registry: OpenKatReportScenarioRegistry(
              scenarios: const [scenario],
            ),
          ).generate(
            [
              _organization([
                _snapshot(
                  date: DateTime.utc(2026, 7, 15),
                  source: 'alpha.json',
                ),
              ]),
            ],
            OpenKatReportRequest(
              scenarioId: 'custom-duplicate-kind',
              scope: const OpenKatReportScope.portfolio(),
              currentAsOf: DateTime.utc(2026, 7, 20),
            ),
          );

      expect(result.generated, isFalse);
      expect(
        result.diagnostics
            .singleWhere(
              (diagnostic) =>
                  diagnostic.code ==
                  OpenKatReportDiagnosticCode.invalidReportPlan,
            )
            .arguments['reason'],
        'duplicateBlockKind',
      );
    });

    test('een blok kan zijn intrinsieke capability niet omzeilen', () {
      const scenario = _CustomScenario(
        descriptor: OpenKatScenarioDescriptor(
          id: 'custom-cve',
          scopes: {OpenKatReportScopeKind.portfolio},
        ),
        plan: OpenKatReportPlan(
          scenarioId: 'custom-cve',
          blocks: [
            OpenKatReportBlock(
              id: 'management',
              kind: OpenKatReportBlockKind.managementOverview,
            ),
            OpenKatReportBlock(
              id: 'cve',
              kind: OpenKatReportBlockKind.cveExposure,
            ),
          ],
        ),
      );
      final engine = OpenKatReportEngine(
        registry: OpenKatReportScenarioRegistry(scenarios: const [scenario]),
      );

      final result = engine.generate(
        [
          _organization([
            _snapshot(date: DateTime.utc(2026, 7, 15), source: 'ordinary.json'),
          ]),
        ],
        OpenKatReportRequest(
          scenarioId: 'custom-cve',
          scope: const OpenKatReportScope.portfolio(),
          currentAsOf: DateTime.utc(2026, 7, 20),
        ),
      );

      expect(result.generated, isFalse);
      expect(result.plan, isNull);
      expect(
        result.missingCapabilities,
        contains(OpenKatReportCapability.reliableCveReferences),
      );
      expect(
        _hasDiagnostic(result, OpenKatReportDiagnosticCode.invalidCveId),
        isTrue,
      );
      expect(
        _hasDiagnostic(result, OpenKatReportDiagnosticCode.missingCapability),
        isTrue,
      );
    });

    test(
      'een CVE-blok blijft verplicht als een custom descriptor het optioneel noemt',
      () {
        const scenario = _CustomScenario(
          descriptor: OpenKatScenarioDescriptor(
            id: 'custom-optional-cve',
            scopes: {OpenKatReportScopeKind.portfolio},
            optionalCapabilities: {
              OpenKatReportCapability.reliableCveReferences,
            },
          ),
          plan: OpenKatReportPlan(
            scenarioId: 'custom-optional-cve',
            blocks: [
              OpenKatReportBlock(
                id: 'management',
                kind: OpenKatReportBlockKind.managementOverview,
              ),
              OpenKatReportBlock(
                id: 'cve',
                kind: OpenKatReportBlockKind.cveExposure,
              ),
            ],
          ),
        );
        final result =
            OpenKatReportEngine(
              registry: OpenKatReportScenarioRegistry(
                scenarios: const [scenario],
              ),
            ).generate(
              [
                _organization([
                  _snapshot(
                    date: DateTime.utc(2026, 7, 15),
                    source: 'ordinary.json',
                  ),
                ]),
              ],
              OpenKatReportRequest(
                scenarioId: 'custom-optional-cve',
                scope: const OpenKatReportScope.portfolio(),
                currentAsOf: DateTime.utc(2026, 7, 20),
                cveId: 'CVE-2026-1234',
              ),
            );

        expect(result.generated, isFalse);
        expect(
          _hasDiagnostic(result, OpenKatReportDiagnosticCode.missingCapability),
          isTrue,
        );
      },
    );

    test('een plan voor een ander scenario wordt geweigerd', () {
      const scenario = _CustomScenario(
        descriptor: OpenKatScenarioDescriptor(
          id: 'custom-plan',
          scopes: {OpenKatReportScopeKind.portfolio},
        ),
        plan: OpenKatReportPlan(
          scenarioId: 'other-plan',
          blocks: [
            OpenKatReportBlock(
              id: 'management',
              kind: OpenKatReportBlockKind.managementOverview,
            ),
          ],
        ),
      );
      final result =
          OpenKatReportEngine(
            registry: OpenKatReportScenarioRegistry(
              scenarios: const [scenario],
            ),
          ).generate(
            [
              _organization([
                _snapshot(
                  date: DateTime.utc(2026, 7, 15),
                  source: 'alpha.json',
                ),
              ]),
            ],
            OpenKatReportRequest(
              scenarioId: 'custom-plan',
              scope: const OpenKatReportScope.portfolio(),
              currentAsOf: DateTime.utc(2026, 7, 20),
            ),
          );

      expect(result.generated, isFalse);
      expect(result.plan, isNull);
      expect(
        result.diagnostics
            .singleWhere(
              (diagnostic) =>
                  diagnostic.code ==
                  OpenKatReportDiagnosticCode.invalidReportPlan,
            )
            .arguments['reason'],
        'scenarioIdMismatch',
      );
    });
  });

  group('runtime rapportbeleid', () {
    test('weigert ongeldige en buitensporige tabelgrenzen getypept', () {
      for (final value in [
        0,
        -1,
        OpenKatReportPolicy.maximumTableRowLimit + 1,
      ]) {
        final result = OpenKatReportEngine().generate(
          [
            _organization([
              _snapshot(date: DateTime.utc(2026, 7, 15), source: 'alpha.json'),
            ]),
          ],
          OpenKatReportRequest(
            scenarioId: 'management-overview',
            scope: const OpenKatReportScope.portfolio(),
            currentAsOf: DateTime.utc(2026, 7, 20),
            policy: OpenKatReportPolicy(tableRowLimit: value),
          ),
        );

        expect(result.generated, isFalse);
        final diagnostic = result.diagnostics.singleWhere(
          (item) => item.code == OpenKatReportDiagnosticCode.invalidPolicy,
        );
        expect(diagnostic.arguments['field'], 'tableRowLimit');
        expect(diagnostic.arguments['value'], '$value');
      }
    });

    test('weigert een ongeldige historische werkgrens getypept', () {
      final result = OpenKatReportEngine().generate(
        [
          _organization([
            _snapshot(date: DateTime.utc(2026, 7, 15), source: 'alpha.json'),
          ]),
        ],
        OpenKatReportRequest(
          scenarioId: 'management-overview',
          scope: const OpenKatReportScope.portfolio(),
          currentAsOf: DateTime.utc(2026, 7, 20),
          policy: const OpenKatReportPolicy(historicalFindingWorkLimit: 0),
        ),
      );

      expect(result.generated, isFalse);
      expect(
        result.diagnostics
            .singleWhere(
              (item) => item.code == OpenKatReportDiagnosticCode.invalidPolicy,
            )
            .arguments['field'],
        'historicalFindingWorkLimit',
      );
    });

    test(
      'stopt lifecycle getypept vóór de historische index te groot wordt',
      () {
        final result = OpenKatReportEngine().generate(
          [
            _organization([
              _snapshot(
                date: DateTime.utc(2026, 7, 1),
                source: 'alpha-history.json',
                findings: [
                  _finding(id: 'history-a'),
                  _finding(id: 'history-b'),
                ],
                sourceFeatures: const {
                  OpenKatSourceFeature.stableFindingIdentity,
                },
              ),
              _snapshot(
                date: DateTime.utc(2026, 7, 5),
                source: 'alpha-previous.json',
                findings: [_finding(id: 'previous')],
                sourceFeatures: const {
                  OpenKatSourceFeature.stableFindingIdentity,
                },
              ),
              _snapshot(
                date: DateTime.utc(2026, 7, 15),
                source: 'alpha-current.json',
                findings: [_finding(id: 'current')],
                sourceFeatures: const {
                  OpenKatSourceFeature.stableFindingIdentity,
                },
              ),
            ]),
          ],
          OpenKatReportRequest(
            scenarioId: 'weekly-comparison',
            scope: const OpenKatReportScope.portfolio(),
            currentAsOf: DateTime.utc(2026, 7, 20),
            previousAsOf: DateTime.utc(2026, 7, 10),
            policy: const OpenKatReportPolicy(historicalFindingWorkLimit: 1),
          ),
        );

        expect(result.generated, isFalse);
        expect(
          result.diagnostics
              .singleWhere(
                (item) =>
                    item.code ==
                    OpenKatReportDiagnosticCode.resourceLimitExceeded,
              )
              .arguments,
          containsPair('resource', 'historicalFindings'),
        );
      },
    );
  });
}
