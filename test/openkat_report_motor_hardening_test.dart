import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/services/openkat/openkat_report_capabilities.dart';
import 'package:ocideck/services/openkat/openkat_report_engine.dart';
import 'package:ocideck/services/openkat/openkat_report_facts.dart';
import 'package:ocideck/services/openkat/openkat_report_rankings.dart';
import 'package:ocideck/services/openkat/openkat_report_scenarios.dart';

const _historicalFeatures = {
  OpenKatSourceFeature.stableFindingIdentity,
  OpenKatSourceFeature.reliableCveReferences,
  OpenKatSourceFeature.comparableMeasurementCoverage,
};

OpenKatFinding _finding(
  String id, {
  DateTime? openedAt,
  List<String> cveIds = const [],
  String? recommendation,
}) => OpenKatFinding(
  id: id,
  findingTypeId: 'KAT-$id',
  findingTypeName: 'Type $id',
  severity: 'high',
  systemId: 'asset.example',
  openedAt: openedAt,
  recommendation: recommendation,
  stableIdentity: true,
  cveIds: cveIds,
);

OpenKatSnapshot _snapshot({
  required DateTime date,
  required String source,
  List<OpenKatFinding> findings = const [],
  Map<String, OpenKatControlScore> controls = const {},
  Set<OpenKatSourceFeature> sourceFeatures = _historicalFeatures,
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: source,
  sourceHash: 'sha256:$source',
  schema: 'test',
  findings: findings,
  controls: controls,
  sourceFeatures: sourceFeatures,
  measurementScopeId: 'same-scope',
);

OpenKatOrganization _organization(
  String code,
  List<OpenKatSnapshot> snapshots,
) => OpenKatOrganization(code: code, name: code, snapshots: snapshots);

OpenKatReportRequest _request(
  String scenarioId, {
  DateTime? previousAsOf,
  OpenKatReportPolicy policy = const OpenKatReportPolicy(),
}) => OpenKatReportRequest(
  scenarioId: scenarioId,
  scope: const OpenKatReportScope.portfolio(),
  currentAsOf: DateTime.utc(2026, 7, 20),
  previousAsOf: previousAsOf,
  policy: policy,
);

class _FixedScenario implements OpenKatReportScenario {
  @override
  final OpenKatScenarioDescriptor descriptor;
  final OpenKatReportPlan plan;

  const _FixedScenario(this.descriptor, this.plan);

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => plan;
}

class _CountingList<T> extends ListBase<T> {
  final List<T> values;
  int reads = 0;

  _CountingList(Iterable<T> values) : values = List.of(values);

  @override
  int get length => values.length;

  @override
  set length(int value) => throw UnsupportedError('alleen-lezen');

  @override
  T operator [](int index) {
    reads++;
    return values[index];
  }

  @override
  void operator []=(int index, T value) =>
      throw UnsupportedError('alleen-lezen');
}

void main() {
  test('preflight neemt intrinsieke blokcapabilities mee', () {
    const scenario = _FixedScenario(
      OpenKatScenarioDescriptor(
        id: 'intrinsic-preflight',
        scopes: {OpenKatReportScopeKind.portfolio},
      ),
      OpenKatReportPlan(
        scenarioId: 'intrinsic-preflight',
        blocks: [
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

    final assessment = engine.assessScenarioCapabilities([
      _organization('alpha', [
        _snapshot(
          date: DateTime.utc(2026, 7, 13),
          source: 'current.json',
          sourceFeatures: const {},
        ),
      ]),
    ], _request('intrinsic-preflight'));

    expect(
      assessment.missingRequiredCapabilities,
      contains(OpenKatReportCapability.reliableCveReferences),
    );
  });

  test(
    'controlwijzigingen eisen noemers in beide perioden bij iedere organisatie',
    () {
      const valid = {
        'control': OpenKatControlScore(name: 'Control', compliant: 1, total: 2),
      };
      const invalid = {
        'control': OpenKatControlScore(name: 'Control', compliant: 1),
      };
      final organizations = [
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 6),
            source: 'alpha-previous.json',
            controls: valid,
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'alpha-current.json',
            controls: valid,
          ),
        ]),
        _organization('beta', [
          _snapshot(
            date: DateTime.utc(2026, 7, 6),
            source: 'beta-previous.json',
            controls: invalid,
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'beta-current.json',
            controls: valid,
          ),
        ]),
      ];
      final request = _request(
        'control-changes',
        previousAsOf: DateTime.utc(2026, 7, 7),
      );
      final capabilities = const OpenKatReportCapabilityService().assess(
        OpenKatReportFacts(organizations),
        request,
      );

      expect(
        capabilities[OpenKatReportCapability.controlsWithDenominator]!.status,
        OpenKatCapabilityStatus.available,
        reason: 'de huidige controldekking blijft bruikbaar',
      );
      expect(
        capabilities[OpenKatReportCapability.comparableControlsWithDenominator]!
            .status,
        OpenKatCapabilityStatus.unavailable,
      );
      expect(
        OpenKatReportEngine()
            .generate(organizations, _request('control-coverage'))
            .generated,
        isTrue,
      );
      final changes = OpenKatReportEngine().generate(organizations, request);
      expect(changes.generated, isFalse);
      expect(
        changes.missingCapabilities,
        contains(OpenKatReportCapability.comparableControlsWithDenominator),
      );
    },
  );

  test('toekomstige openedAt sluit ouderdomsrapport fail-closed', () {
    final result = OpenKatReportEngine().generate([
      _organization('alpha', [
        _snapshot(
          date: DateTime.utc(2026, 7, 13),
          source: 'future-opened-at.json',
          findings: [_finding('future', openedAt: DateTime.utc(2026, 7, 14))],
          sourceFeatures: const {OpenKatSourceFeature.reliableOpenedAt},
        ),
      ]),
    ], _request('finding-age'));

    expect(result.generated, isFalse);
    expect(
      result.missingCapabilities,
      contains(OpenKatReportCapability.reliableOpenedAt),
    );
  });

  group('historische brontraces', () {
    test(
      'lifecycle traceert oudere bronnen alleen wanneer zij worden gelezen',
      () {
        List<OpenKatOrganization> data(List<OpenKatFinding> current) => [
          _organization('alpha', [
            _snapshot(
              date: DateTime.utc(2026, 7, 1),
              source: 'historical.json',
              findings: [_finding('returning')],
            ),
            _snapshot(
              date: DateTime.utc(2026, 7, 6),
              source: 'previous.json',
              findings: [_finding('unchanged')],
            ),
            _snapshot(
              date: DateTime.utc(2026, 7, 13),
              source: 'current.json',
              findings: current,
            ),
          ]),
        ];
        final request = _request(
          'finding-lifecycle',
          previousAsOf: DateTime.utc(2026, 7, 7),
        );

        final withoutHistoricalLookup = OpenKatReportEngine().generate(
          data([_finding('unchanged')]),
          request,
        );
        expect(
          withoutHistoricalLookup.sourceTraces.map((trace) => trace.sourceFile),
          isNot(contains('historical.json')),
        );

        final withHistoricalLookup = OpenKatReportEngine().generate(
          data([_finding('returning')]),
          request,
        );
        final historical = withHistoricalLookup.sourceTraces.singleWhere(
          (trace) => trace.sourceFile == 'historical.json',
        );
        expect(historical.role, OpenKatMeasurementRole.historical);
      },
    );

    test('portfolioverloop traceert de oudere bronnen die punten voeden', () {
      final result = OpenKatReportEngine().generate([
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 1),
            source: 'timeline-old.json',
            findings: [_finding('old')],
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 6),
            source: 'timeline-previous.json',
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'timeline-current.json',
          ),
        ]),
      ], _request('portfolio-trend', previousAsOf: DateTime.utc(2026, 7, 7)));

      expect(
        result.sourceTraces
            .where((trace) => trace.role == OpenKatMeasurementRole.historical)
            .map((trace) => trace.sourceFile),
        contains('timeline-old.json'),
      );
    });

    test('CVE-herobservatie traceert de geraadpleegde oudere bronnen', () {
      final result = OpenKatReportEngine().generate([
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 1),
            source: 'cve-old.json',
            findings: [
              _finding('old', cveIds: const ['CVE-2026-1234']),
            ],
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 6),
            source: 'cve-previous.json',
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'cve-current.json',
            findings: [
              _finding('new', cveIds: const ['CVE-2026-1234']),
            ],
          ),
        ]),
      ], _request('cve-changes', previousAsOf: DateTime.utc(2026, 7, 7)));

      expect(
        result.sourceTraces
            .where((trace) => trace.role == OpenKatMeasurementRole.historical)
            .map((trace) => trace.sourceFile),
        contains('cve-old.json'),
      );
    });
  });

  test('portfolioTimeline begrenst datums vóór opbouw en schaalt lineair', () {
    final base = DateTime.utc(2026, 1, 1);
    final snapshots = _CountingList([
      for (var index = 0; index < 100; index++)
        _snapshot(
          date: base.add(Duration(days: index)),
          source: 'timeline-$index.json',
          findings: [_finding('$index')],
        ),
    ]);
    final facts = OpenKatReportFacts([_organization('alpha', snapshots)]);
    final request = OpenKatReportRequest(
      scenarioId: 'timeline',
      scope: const OpenKatReportScope.portfolio(),
      currentAsOf: base.add(const Duration(days: 100)),
    );

    final timeline = facts.portfolioTimeline(request, maxResults: 3);

    expect(timeline, hasLength(3));
    expect(timeline.first.date, base.add(const Duration(days: 97)));
    expect(timeline.last.date, base.add(const Duration(days: 99)));
    expect(
      snapshots.reads,
      lessThanOrEqualTo(320),
      reason: 'de invoer hoort niet eenmaal per tijdlijnpunt te worden gelezen',
    );
  });

  group('aanbevelingsbudget', () {
    test('de groepenpoort stopt vóór onbegrensde materialisatie', () {
      final findings = _CountingList([
        for (var index = 0; index < 100; index++)
          _finding('$index', recommendation: 'Aanbeveling $index'),
      ]);
      final facts = OpenKatReportFacts([
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'recommendations.json',
            findings: findings,
          ),
        ]),
      ]);

      expect(
        () => facts.recommendationItems(
          _request('recommendations-overview'),
          maxGroups: 3,
        ),
        throwsStateError,
      );
      expect(findings.reads, 4);
    });

    test('de motor meldt een resourcefout boven de constructiegrens', () {
      final result = OpenKatReportEngine().generate([
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'recommendations.json',
            findings: [
              for (
                var index = 0;
                index <= OpenKatReportPolicy.maximumTableRowLimit;
                index++
              )
                _finding('$index', recommendation: 'Aanbeveling $index'),
            ],
          ),
        ]),
      ], _request('recommendations-overview'));

      expect(result.generated, isFalse);
      expect(
        result.diagnostics,
        contains(
          isA<OpenKatReportDiagnostic>()
              .having(
                (diagnostic) => diagnostic.code,
                'code',
                OpenKatReportDiagnosticCode.resourceLimitExceeded,
              )
              .having(
                (diagnostic) => diagnostic.arguments['resource'],
                'resource',
                'recommendationGroups',
              ),
        ),
      );
    });
  });
}
