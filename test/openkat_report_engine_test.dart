import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_report_engine.dart';

OpenKatFinding _finding({
  required String id,
  String severity = 'high',
  List<String> cveIds = const [],
  bool stableIdentity = true,
}) => OpenKatFinding(
  id: id,
  findingTypeId: 'KAT-$id',
  findingTypeName: 'Bevinding $id',
  severity: severity,
  systemId: 'asset.example',
  stableIdentity: stableIdentity,
  cveIds: cveIds,
);

OpenKatSnapshot _snapshot({
  required DateTime date,
  required String source,
  List<OpenKatFinding> findings = const [],
  Set<OpenKatSourceFeature> sourceFeatures = const {},
  String? measurementScopeId,
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: source,
  sourceHash: 'sha256:$source',
  schema: 'openkat-test-v1',
  systems: const [
    OpenKatSystem(
      id: 'asset.example',
      hostname: 'asset.example',
      stableIdentity: true,
      monitoringStatus: OpenKatMonitoringStatus.monitored,
    ),
  ],
  findings: findings,
  sourceFeatures: sourceFeatures,
  measurementScopeId: measurementScopeId,
);

OpenKatOrganization _organization(
  String code,
  List<OpenKatSnapshot> snapshots,
) => OpenKatOrganization(
  code: code,
  name: code.toUpperCase(),
  snapshots: snapshots,
);

OpenKatReportRequest _request(
  String scenarioId, {
  OpenKatReportScope scope = const OpenKatReportScope.portfolio(),
  DateTime? currentAsOf,
  DateTime? previousAsOf,
  String? cveId,
  OpenKatReportLanguage language = OpenKatReportLanguage.dutch,
  OpenKatReportPolicy policy = const OpenKatReportPolicy(),
}) => OpenKatReportRequest(
  scenarioId: scenarioId,
  scope: scope,
  currentAsOf: currentAsOf ?? DateTime.utc(2026, 7, 20),
  previousAsOf: previousAsOf,
  cveId: cveId,
  language: language,
  policy: policy,
);

bool _hasDiagnostic(
  OpenKatReportResult result,
  OpenKatReportDiagnosticCode code,
) => result.diagnostics.any((diagnostic) => diagnostic.code == code);

void main() {
  final engine = OpenKatReportEngine();

  group('scenarioregister en verzoekvalidatie', () {
    test('de vijf publieke scenario-id’s zijn aangesloten', () {
      const ids = {
        'management-overview',
        'weekly-comparison',
        'organization-overview',
        'cve-exposure',
        'monitoring-changes',
      };
      expect(
        engine.registry.descriptors.map((descriptor) => descriptor.id).toSet(),
        ids,
      );
      final organizations = [
        _organization('alpha', [
          _snapshot(date: DateTime.utc(2026, 7, 13), source: 'alpha.json'),
        ]),
      ];

      for (final id in ids) {
        final scope = id == 'organization-overview'
            ? OpenKatReportScope.organization('alpha')
            : const OpenKatReportScope.portfolio();
        final result = engine.generate(
          organizations,
          _request(
            id,
            scope: scope,
            previousAsOf: id == 'weekly-comparison'
                ? DateTime.utc(2026, 7, 13)
                : null,
            cveId: id == 'cve-exposure' ? 'CVE-2026-1234' : null,
          ),
        );

        expect(
          _hasDiagnostic(result, OpenKatReportDiagnosticCode.unknownScenario),
          isFalse,
          reason: '$id staat in het publieke register en moet bereikbaar zijn',
        );
        expect(result.scenarioId, id);
      }
    });

    test('een onbekend scenario levert geen half rapport op', () {
      final result = engine.generate(const [], _request('management-overveiw'));

      expect(result.deck, isNull);
      expect(result.plan, isNull);
      expect(result.hasErrors, isTrue);
      expect(
        result.diagnostics.map((diagnostic) => diagnostic.code),
        contains(OpenKatReportDiagnosticCode.unknownScenario),
      );
      expect(result.measurements, isEmpty);
      expect(result.sourceTraces, isEmpty);
    });

    test('een portfolioscope wordt geweigerd voor een organisatierapport', () {
      final result = engine.generate([
        _organization('alpha', [
          _snapshot(date: DateTime.utc(2026, 7, 20), source: 'alpha.json'),
        ]),
      ], _request('organization-overview'));

      expect(result.generated, isFalse);
      expect(
        _hasDiagnostic(result, OpenKatReportDiagnosticCode.unsupportedScope),
        isTrue,
      );
    });

    test('een organisatiescope kan niet zonder organisatiecode bestaan', () {
      expect(() => OpenKatReportScope.organization('  '), throwsArgumentError);
    });

    test('een onbekende organisatie wordt niet als leeg rapport behandeld', () {
      final result = engine.generate(
        [
          _organization('alpha', [
            _snapshot(date: DateTime.utc(2026, 7, 20), source: 'alpha.json'),
          ]),
        ],
        _request(
          'organization-overview',
          scope: OpenKatReportScope.organization('beta'),
        ),
      );

      expect(result.generated, isFalse);
      expect(
        _hasDiagnostic(
          result,
          OpenKatReportDiagnosticCode.organizationNotFound,
        ),
        isTrue,
      );
    });

    test('CVE-validatie gebeurt vóór capabilityselectie', () {
      final result = engine.generate([
        _organization('alpha', [
          _snapshot(date: DateTime.utc(2026, 7, 20), source: 'alpha.json'),
        ]),
      ], _request('cve-exposure', cveId: '2026-1234'));

      expect(result.generated, isFalse);
      expect(
        _hasDiagnostic(result, OpenKatReportDiagnosticCode.invalidCveId),
        isTrue,
      );
    });
  });

  group('capabilitypoorten', () {
    test('CVE en monitoring zijn met gewone snapshots niet beschikbaar', () {
      final organizations = [
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 20),
            source: 'alpha.json',
            findings: [
              _finding(id: 'f1', cveIds: const ['CVE-2026-1234']),
            ],
          ),
        ]),
      ];

      final cve = engine.generate(
        organizations,
        _request('cve-exposure', cveId: 'CVE-2026-1234'),
      );
      final monitoring = engine.generate(
        organizations,
        _request('monitoring-changes'),
      );

      expect(cve.generated, isFalse);
      expect(
        cve.missingCapabilities,
        contains(OpenKatReportCapability.reliableCveReferences),
      );
      expect(monitoring.generated, isFalse);
      expect(
        monitoring.missingCapabilities,
        contains(OpenKatReportCapability.reliableMonitoringStatus),
      );
    });

    test('expliciete canonieke bronkenmerken openen het CVE-scenario', () {
      const canonicalFeatures = {
        OpenKatSourceFeature.stableAssetIdentity,
        OpenKatSourceFeature.reliableCveReferences,
        OpenKatSourceFeature.comparableMeasurementCoverage,
      };
      final result = engine.generate([
        _organization('alpha', [
          _snapshot(
            date: DateTime.utc(2026, 7, 20),
            source: 'canonical-alpha.json',
            findings: [
              _finding(id: 'f1', cveIds: const ['CVE-2026-1234']),
            ],
            sourceFeatures: canonicalFeatures,
            measurementScopeId: 'portfolio-v1',
          ),
        ]),
      ], _request('cve-exposure', cveId: 'CVE-2026-1234'));

      expect(result.generated, isTrue);
      expect(result.missingCapabilities, isEmpty);
      expect(result.deck, isA<Deck>());
      expect(result.deck!.slides, isNotEmpty);
      expect(
        result.deck!.slides.every((slide) => slide.runtimeType == Slide),
        isTrue,
      );
      expect(
        result.deck!.slides.every(
          (slide) => SlideType.values.contains(slide.type),
        ),
        isTrue,
        reason:
            'de motor bouwt gewone OciDeck-dia’s, geen parallel uitvoermodel',
      );
    });

    test('canonieke monitoringfeiten openen ook het mutatiescenario', () {
      const canonicalFeatures = {
        OpenKatSourceFeature.stableAssetIdentity,
        OpenKatSourceFeature.reliableMonitoringStatus,
      };
      final result = engine.generate(
        [
          _organization('alpha', [
            _snapshot(
              date: DateTime.utc(2026, 7, 6),
              source: 'canonical-alpha-previous.json',
              sourceFeatures: canonicalFeatures,
            ),
            _snapshot(
              date: DateTime.utc(2026, 7, 13),
              source: 'canonical-alpha-current.json',
              sourceFeatures: canonicalFeatures,
            ),
          ]),
        ],
        _request(
          'monitoring-changes',
          currentAsOf: DateTime.utc(2026, 7, 14),
          previousAsOf: DateTime.utc(2026, 7, 7),
        ),
      );

      expect(result.generated, isTrue);
      expect(result.missingCapabilities, isEmpty);
      expect(
        result.plan!.blocks.map((block) => block.kind),
        contains(OpenKatReportBlockKind.monitoringChanges),
      );
    });
  });

  group('meetkeuze en herleidbaarheid', () {
    test(
      'weekvergelijking gebruikt de laatste bruikbare stand per peildatum',
      () {
        final result = engine.generate(
          [
            _organization('alpha', [
              _snapshot(
                date: DateTime.utc(2026, 7, 5),
                source: 'alpha-05.json',
              ),
              _snapshot(
                date: DateTime.utc(2026, 7, 12),
                source: 'alpha-12.json',
              ),
              _snapshot(
                date: DateTime.utc(2026, 7, 19),
                source: 'alpha-19.json',
              ),
            ]),
          ],
          _request(
            'weekly-comparison',
            currentAsOf: DateTime.utc(2026, 7, 18),
            previousAsOf: DateTime.utc(2026, 7, 11),
          ),
        );

        final current = result.measurements.singleWhere(
          (measurement) => measurement.role == OpenKatMeasurementRole.current,
        );
        final previous = result.measurements.singleWhere(
          (measurement) => measurement.role == OpenKatMeasurementRole.previous,
        );
        expect(current.measuredAt, DateTime.utc(2026, 7, 12));
        expect(current.age, const Duration(days: 6));
        expect(previous.measuredAt, DateTime.utc(2026, 7, 5));
        expect(previous.age, const Duration(days: 6));
        expect(
          _hasDiagnostic(result, OpenKatReportDiagnosticCode.snapshotTooOld),
          isFalse,
          reason:
              'zonder ingestelde maximumleeftijd bestaat geen stale-oordeel',
        );
      },
    );

    test('onvolledige portfoliodekking blijft zichtbaar als waarschuwing', () {
      final result = engine.generate(
        [
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
        ],
        _request(
          'weekly-comparison',
          currentAsOf: DateTime.utc(2026, 7, 14),
          previousAsOf: DateTime.utc(2026, 7, 7),
        ),
      );

      expect(
        result.measurements.any(
          (measurement) =>
              measurement.organizationCode == 'beta' &&
              measurement.role == OpenKatMeasurementRole.previous &&
              measurement.missing,
        ),
        isTrue,
      );
      expect(
        result.diagnostics.any(
          (diagnostic) =>
              diagnostic.code ==
                  OpenKatReportDiagnosticCode.incompletePortfolio &&
              diagnostic.severity == OpenKatReportDiagnosticSeverity.warning,
        ),
        isTrue,
      );
      expect(
        result.generated,
        isTrue,
        reason:
            'een bruikbaar deel van het portfolio blijft rapporteerbaar; '
            'de ontbrekende organisatie staat expliciet in de waarschuwing',
      );
    });

    test('een ingestelde maximumleeftijd markeert een oude meting', () {
      final result = engine.generate(
        [
          _organization('alpha', [
            _snapshot(date: DateTime.utc(2026, 6, 1), source: 'alpha-old.json'),
          ]),
        ],
        _request(
          'management-overview',
          currentAsOf: DateTime.utc(2026, 7, 20),
          policy: const OpenKatReportPolicy(
            maximumSnapshotAge: Duration(days: 30),
          ),
        ),
      );

      expect(
        result.diagnostics.any(
          (diagnostic) =>
              diagnostic.code == OpenKatReportDiagnosticCode.snapshotTooOld &&
              diagnostic.severity == OpenKatReportDiagnosticSeverity.warning,
        ),
        isTrue,
      );
    });

    test('resultaat noemt exact de gebruikte bestanden en hashes', () {
      final result = engine.generate(
        [
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
        ],
        _request(
          'weekly-comparison',
          currentAsOf: DateTime.utc(2026, 7, 14),
          previousAsOf: DateTime.utc(2026, 7, 7),
        ),
      );

      expect(
        result.sourceTraces
            .map(
              (trace) => (
                trace.role,
                trace.reportDate,
                trace.sourceFile,
                trace.sourceHash,
                trace.schema,
              ),
            )
            .toSet(),
        {
          (
            OpenKatMeasurementRole.current,
            DateTime.utc(2026, 7, 13),
            'alpha-current.json',
            'sha256:alpha-current.json',
            'openkat-test-v1',
          ),
          (
            OpenKatMeasurementRole.previous,
            DateTime.utc(2026, 7, 6),
            'alpha-previous.json',
            'sha256:alpha-previous.json',
            'openkat-test-v1',
          ),
        },
      );
    });

    test('de getypepte rapporttaal bereikt het gewone Deck-model', () {
      final result = engine.generate(
        [
          _organization('alpha', [
            _snapshot(date: DateTime.utc(2026, 7, 20), source: 'alpha.json'),
          ]),
        ],
        _request(
          'management-overview',
          language: OpenKatReportLanguage.english,
        ),
      );

      expect(result.generated, isTrue);
      expect(result.deck!.language, 'en');
      expect(result.deck!.title, 'OpenKAT management overview');
      expect(
        result.deck!.slides
            .firstWhere(
              (slide) => slide.notes.contains(
                'ocideck_openkat_view: portfolio.summary',
              ),
            )
            .title,
        'Key figures',
      );
      expect(
        result.deck!.slides
            .firstWhere(
              (slide) => slide.notes.contains(
                'ocideck_openkat_view: report.management-overview.availability',
              ),
            )
            .title,
        'Measurements used',
      );
    });
  });
}
