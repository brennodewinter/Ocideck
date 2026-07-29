import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/services/openkat/openkat_report_capabilities.dart';
import 'package:ocideck/services/openkat/openkat_report_facts.dart';

OpenKatFinding _finding({
  required String id,
  String severity = 'high',
  bool stableIdentity = true,
  List<String> cveIds = const [],
}) => OpenKatFinding(
  id: id,
  findingTypeId: 'KAT-$id',
  severity: severity,
  systemId: 'asset.example',
  stableIdentity: stableIdentity,
  cveIds: cveIds,
);

OpenKatSnapshot _snapshot({
  required DateTime date,
  required String source,
  List<OpenKatFinding> findings = const [],
  bool usable = true,
  Set<OpenKatSourceFeature> sourceFeatures = const {},
  String? measurementScopeId,
  List<OpenKatSystem> systems = const [
    OpenKatSystem(
      id: 'asset.example',
      stableIdentity: true,
      monitoringStatus: OpenKatMonitoringStatus.monitored,
    ),
  ],
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: source,
  sourceHash: 'sha256:$source',
  findings: findings,
  usable: usable,
  sourceFeatures: sourceFeatures,
  measurementScopeId: measurementScopeId,
  systems: systems,
);

OpenKatOrganization _organization(
  String code,
  List<OpenKatSnapshot> snapshots,
) => OpenKatOrganization(
  code: code,
  name: code.toUpperCase(),
  snapshots: snapshots,
);

OpenKatReportRequest _request({
  DateTime? currentAsOf,
  DateTime? previousAsOf,
  OpenKatReportPolicy policy = const OpenKatReportPolicy(),
}) => OpenKatReportRequest(
  scenarioId: 'weekly-comparison',
  scope: const OpenKatReportScope.portfolio(),
  currentAsOf: currentAsOf ?? DateTime.utc(2026, 7, 14),
  previousAsOf: previousAsOf ?? DateTime.utc(2026, 7, 7),
  policy: policy,
);

void main() {
  group('snapshotkeuze op peildatum', () {
    test('kiest de laatste bruikbare snapshot op of vóór de grens', () {
      final organization = _organization('alpha', [
        _snapshot(
          date: DateTime.utc(2026, 7, 12),
          source: 'unusable.json',
          usable: false,
        ),
        _snapshot(date: DateTime.utc(2026, 7, 20), source: 'future.json'),
        _snapshot(date: DateTime.utc(2026, 7, 5), source: 'older.json'),
        _snapshot(date: DateTime.utc(2026, 7, 11), source: 'chosen.json'),
      ]);
      final facts = OpenKatReportFacts([organization]);

      final selected = facts.snapshotOnOrBefore(
        organization,
        DateTime.utc(2026, 7, 12),
      );

      expect(selected?.sourceFile, 'chosen.json');
      expect(selected?.reportDate, DateTime.utc(2026, 7, 11));
    });

    test('de peildag zelf telt mee', () {
      final organization = _organization('alpha', [
        _snapshot(date: DateTime.utc(2026, 7, 12), source: 'on-cutoff.json'),
      ]);

      expect(
        OpenKatReportFacts([
          organization,
        ]).snapshotOnOrBefore(organization, DateTime.utc(2026, 7, 12)),
        same(organization.snapshots.single),
      );
    });

    test('geen bruikbare voorganger blijft expliciet ontbrekend', () {
      final facts = OpenKatReportFacts([
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'alpha-current.json',
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 6),
            source: 'alpha-previous.json',
          ),
        ]),
        _organization('beta', [
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'beta-current.json',
          ),
        ]),
      ]);

      final selections = facts.selections(_request());
      final alpha = selections.singleWhere(
        (selection) => selection.organization.code == 'alpha',
      );
      final beta = selections.singleWhere(
        (selection) => selection.organization.code == 'beta',
      );

      expect(alpha.current?.sourceFile, 'alpha-current.json');
      expect(alpha.currentAge, const Duration(days: 1));
      expect(alpha.currentMissing, isFalse);
      expect(alpha.previous?.sourceFile, 'alpha-previous.json');
      expect(alpha.previousAge, const Duration(days: 1));
      expect(alpha.previousMissing, isFalse);

      expect(beta.current?.sourceFile, 'beta-current.json');
      expect(beta.currentAge, const Duration(days: 1));
      expect(beta.previous, isNull);
      expect(beta.previousAge, isNull);
      expect(beta.previousMissing, isTrue);
    });
  });

  group('levenscyclus blijft bij wat de metingen bewijzen', () {
    const comparableSource = {
      OpenKatSourceFeature.stableAssetIdentity,
      OpenKatSourceFeature.comparableMeasurementCoverage,
    };

    test(
      'onderscheidt nieuw, niet meer waargenomen en opnieuw waargenomen',
      () {
        final facts = OpenKatReportFacts([
          _organization('alpha', [
            _snapshot(
              date: DateTime.utc(2026, 6, 29),
              source: 'older.json',
              findings: [_finding(id: 'terug')],
              sourceFeatures: comparableSource,
              measurementScopeId: 'scope-v1',
            ),
            _snapshot(
              date: DateTime.utc(2026, 7, 6),
              source: 'previous.json',
              findings: [_finding(id: 'verdwenen')],
              sourceFeatures: comparableSource,
              measurementScopeId: 'scope-v1',
            ),
            _snapshot(
              date: DateTime.utc(2026, 7, 13),
              source: 'current.json',
              findings: [
                _finding(id: 'terug'),
                _finding(id: 'nieuw'),
              ],
              sourceFeatures: comparableSource,
              measurementScopeId: 'scope-v1',
            ),
          ]),
        ]);

        final lifecycle = {
          for (final item in facts.findingLifecycle(_request()))
            item.finding.id: item,
        };

        expect(
          lifecycle['nieuw']?.observation,
          OpenKatFindingObservation.newlyObserved,
        );
        expect(
          lifecycle['verdwenen']?.observation,
          OpenKatFindingObservation.noLongerObserved,
        );
        expect(
          lifecycle['terug']?.observation,
          OpenKatFindingObservation.reobserved,
        );
        expect(
          lifecycle.values.every((item) => item.comparableCoverage),
          isTrue,
        );
      },
    );

    test('een verdwenen finding heet ook bij gelijke dekking niet opgelost', () {
      expect(
        OpenKatFindingObservation.values.map((value) => value.name).toSet(),
        {'newlyObserved', 'noLongerObserved', 'reobserved'},
        reason:
            'twee snapshots bewijzen waarneming, nooit inhoudelijke oplossing',
      );
    });

    test('ongelijke meetdekking wordt naast de waarneming bewaard', () {
      final facts = OpenKatReportFacts([
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 6),
            source: 'previous.json',
            findings: [_finding(id: 'verdwenen')],
            sourceFeatures: comparableSource,
            measurementScopeId: 'scope-v1',
          ),
          _snapshot(
            date: DateTime.utc(2026, 7, 13),
            source: 'current.json',
            sourceFeatures: comparableSource,
            measurementScopeId: 'scope-v2',
          ),
        ]),
      ]);

      final item = facts.findingLifecycle(_request()).single;
      expect(item.observation, OpenKatFindingObservation.noLongerObserved);
      expect(
        item.comparableCoverage,
        isFalse,
        reason:
            'afwezigheid in een andere populatie mag geen vergelijkbaarheid '
            'suggereren',
      );
    });
  });

  group('capabilities komen uit expliciete bronfeiten', () {
    Map<OpenKatReportCapability, OpenKatCapabilityStatus> assess(
      OpenKatReportFacts facts,
    ) => const OpenKatReportCapabilityService()
        .assess(facts, _request())
        .map(
          (capability, assessment) => MapEntry(capability, assessment.status),
        );

    test('gewone snapshots beloven geen CVE- of monitoringfeiten', () {
      final statuses = assess(
        OpenKatReportFacts([
          _organization('alpha', [
            _snapshot(
              date: DateTime.utc(2026, 7, 13),
              source: 'ordinary.json',
              findings: [
                _finding(id: 'f1', cveIds: const ['CVE-2026-1234']),
              ],
            ),
          ]),
        ]),
      );

      expect(
        statuses[OpenKatReportCapability.reliableCveReferences],
        OpenKatCapabilityStatus.unavailable,
      );
      expect(
        statuses[OpenKatReportCapability.reliableMonitoringStatus],
        OpenKatCapabilityStatus.unavailable,
      );
    });

    test(
      'canonieke bronkenmerken schakelen de capabilities aantoonbaar aan',
      () {
        const canonicalSource = {
          OpenKatSourceFeature.stableAssetIdentity,
          OpenKatSourceFeature.reliableCveReferences,
          OpenKatSourceFeature.reliableMonitoringStatus,
          OpenKatSourceFeature.comparableMeasurementCoverage,
        };
        final statuses = assess(
          OpenKatReportFacts([
            _organization('alpha', [
              _snapshot(
                date: DateTime.utc(2026, 7, 6),
                source: 'canonical-previous.json',
                findings: [
                  _finding(id: 'f1', cveIds: const ['CVE-2026-1234']),
                ],
                sourceFeatures: canonicalSource,
                measurementScopeId: 'scope-v1',
              ),
              _snapshot(
                date: DateTime.utc(2026, 7, 13),
                source: 'canonical-current.json',
                findings: [
                  _finding(id: 'f1', cveIds: const ['CVE-2026-1234']),
                ],
                sourceFeatures: canonicalSource,
                measurementScopeId: 'scope-v1',
              ),
            ]),
          ]),
        );

        expect(
          statuses[OpenKatReportCapability.reliableCveReferences],
          OpenKatCapabilityStatus.available,
        );
        expect(
          statuses[OpenKatReportCapability.reliableMonitoringStatus],
          OpenKatCapabilityStatus.available,
        );
        expect(
          statuses[OpenKatReportCapability.stableAssetIdentity],
          OpenKatCapabilityStatus.available,
        );
        expect(
          statuses[OpenKatReportCapability.comparableMeasurementCoverage],
          OpenKatCapabilityStatus.available,
        );
      },
    );

    test(
      'maximumleeftijd is beleid; zonder grens wordt versheid niet beoordeeld',
      () {
        final statuses = assess(
          OpenKatReportFacts([
            _organization('alpha', [
              _snapshot(
                date: DateTime.utc(2025, 1, 1),
                source: 'old-but-not-stale-without-policy.json',
              ),
            ]),
          ]),
        );

        expect(
          statuses[OpenKatReportCapability.sufficientDataFreshness],
          OpenKatCapabilityStatus.notAssessed,
        );
      },
    );
  });
}
