@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/openkat/openkat_wizard_models.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_deck_generator.dart';
import 'package:ocideck/services/openkat/openkat_directory_scanner.dart';
import 'package:ocideck/services/openkat/openkat_import_service.dart';
import 'package:ocideck/services/openkat/openkat_report_facts.dart';
import 'package:ocideck/services/openkat/openkat_report_scenarios.dart';
import 'package:ocideck/services/openkat/openkat_slide_provenance.dart';
import 'package:ocideck/services/openkat/openkat_wizard_service.dart';
import 'package:path/path.dart' as p;

import 'openkat_wizard_test_fakes.dart';

class _PreparedImporter extends OpenKatImportService {
  final OpenKatManifest manifest;
  final List<OpenKatOrganization> organizations;

  const _PreparedImporter({
    required this.manifest,
    required this.organizations,
  });

  @override
  Future<({OpenKatManifest manifest, List<OpenKatOrganization> organizations})>
  prepareDirectory(String directory) async =>
      (manifest: manifest, organizations: organizations);
}

class _CapabilityRequiredManagementScenario implements OpenKatReportScenario {
  const _CapabilityRequiredManagementScenario();

  @override
  OpenKatScenarioDescriptor get descriptor => const OpenKatScenarioDescriptor(
    id: 'management-overview',
    scopes: {OpenKatReportScopeKind.portfolio},
    requiredCapabilities: {OpenKatReportCapability.reliableCveReferences},
  );

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => const OpenKatReportPlan(
    scenarioId: 'management-overview',
    blocks: [
      OpenKatReportBlock(
        id: 'management',
        kind: OpenKatReportBlockKind.managementOverview,
      ),
    ],
  );
}

OpenKatManifest _manifest(int recognized, {int skipped = 0}) => OpenKatManifest(
  parserVersion: 'test',
  importedAt: DateTime.utc(2026, 7, 2),
  directory: '/reports',
  entries: [
    for (var index = 0; index < recognized; index++)
      OpenKatManifestEntry(
        path: 'report-$index.json',
        hash: '$index',
        status: 'ok',
      ),
    for (var index = 0; index < skipped; index++)
      OpenKatManifestEntry(
        path: 'other-$index.json',
        hash: 'other-$index',
        status: 'unrecognized',
      ),
  ],
);

Map<String, ({int size, String contents})> _directoryState(Directory root) => {
  for (final entity in root.listSync(
    recursive: true,
  )..sort((a, b) => a.path.compareTo(b.path)))
    p.relative(entity.path, from: root.path): (
      size: entity is File ? entity.lengthSync() : -1,
      contents: entity is File ? base64Encode(entity.readAsBytesSync()) : '',
    ),
};

void main() {
  group('wizardregister', () {
    test('ieder scenario declareert alleen zijn noodzakelijke invoer', () {
      final descriptors = {
        for (final item in OpenKatWizardService.scenarioDescriptors)
          item.id: item,
      };

      expect(descriptors.keys, OpenKatWizardScenarioId.values.toSet());
      expect(
        descriptors[OpenKatWizardScenarioId.portfolio]!.recommended,
        isTrue,
      );
      expect(
        descriptors[OpenKatWizardScenarioId.portfolio]!.inputs,
        containsAll({
          OpenKatWizardInputKind.currentAsOf,
          OpenKatWizardInputKind.organizations,
          OpenKatWizardInputKind.language,
          OpenKatWizardInputKind.title,
        }),
      );
      expect(
        descriptors[OpenKatWizardScenarioId.portfolioTrend]!.inputs,
        contains(OpenKatWizardInputKind.previousAsOf),
      );
      expect(
        descriptors[OpenKatWizardScenarioId.organizationProgress]!.inputs,
        contains(OpenKatWizardInputKind.organization),
      );
      expect(
        descriptors[OpenKatWizardScenarioId.cveExposure]!.inputs,
        contains(OpenKatWizardInputKind.cve),
      );
      expect(descriptors[OpenKatWizardScenarioId.dataQuality]!.inputs, {
        OpenKatWizardInputKind.language,
        OpenKatWizardInputKind.title,
      }, reason: 'datakwaliteit heeft geen verzonnen periode of scope nodig');
    });
  });

  group('voorbereiden', () {
    for (final layout in ['legacy', 'raw-data']) {
      test('de gezamenlijke bestandsgrens sluit $layout fail-closed', () async {
        final root = Directory.systemTemp.createTempSync(
          'openkat-entry-limit-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final source = layout == 'raw-data'
            ? (Directory(p.join(root.path, layout))..createSync()).path
            : root.path;
        File(p.join(source, 'one.json')).writeAsStringSync('{}');
        File(p.join(source, 'two.json')).writeAsStringSync('{}');
        const importer = OpenKatImportService(
          scanner: OpenKatDirectoryScanner(maxEntryCount: 1),
        );

        await expectLater(
          importer.prepareDirectory(root.path),
          throwsA(
            isA<OpenKatScanLimitException>().having(
              (error) => error.toString(),
              'begrijpelijke fout',
              allOf(contains('meer dan 1'), contains('Verklein')),
            ),
          ),
        );
      });
    }

    test('de gezamenlijke diepte- en bytegrenzen sluiten vóór lezen', () async {
      final deepRoot = Directory.systemTemp.createTempSync(
        'openkat-depth-limit-',
      );
      final byteRoot = Directory.systemTemp.createTempSync(
        'openkat-byte-limit-',
      );
      addTearDown(() => deepRoot.deleteSync(recursive: true));
      addTearDown(() => byteRoot.deleteSync(recursive: true));
      final nested = Directory(p.join(deepRoot.path, 'nested'))..createSync();
      File(p.join(nested.path, 'report.json')).writeAsStringSync('{}');
      File(p.join(byteRoot.path, 'one.json')).writeAsStringSync('{}');
      File(p.join(byteRoot.path, 'two.json')).writeAsStringSync('{}');

      await expectLater(
        const OpenKatDirectoryScanner(maxDirectoryDepth: 0).scan(deepRoot.path),
        throwsA(
          isA<OpenKatScanLimitException>().having(
            (error) => error.toString(),
            'dieptefout',
            contains('dieper dan 0'),
          ),
        ),
      );
      await expectLater(
        const OpenKatDirectoryScanner(
          maxTotalReportBytes: 3,
        ).scan(byteRoot.path),
        throwsA(
          isA<OpenKatScanLimitException>().having(
            (error) => error.toString(),
            'bytefout',
            allOf(contains('samen groter'), contains('3 bytes')),
          ),
        ),
      );
    });

    test('exacte scannergrenzen blijven toegestaan', () async {
      final root = Directory.systemTemp.createTempSync('openkat-exact-limits-');
      addTearDown(() => root.deleteSync(recursive: true));
      final nested = Directory(p.join(root.path, 'nested'))..createSync();
      File(p.join(nested.path, 'one.json')).writeAsStringSync('{}');

      final result = await const OpenKatDirectoryScanner(
        maxEntryCount: 2,
        maxDirectoryDepth: 1,
        maxTotalReportBytes: 2,
      ).scan(root.path);

      expect(result.manifest.entries, hasLength(1));
      expect(result.manifest.entries.single.status, 'unrecognized');
    });

    test('exacte bestandsgrens wordt gelezen en één byte extra niet', () async {
      final root = Directory.systemTemp.createTempSync(
        'openkat-exact-file-limit-',
      );
      addTearDown(() => root.deleteSync(recursive: true));
      final exact = File(p.join(root.path, 'exact.json'));
      exact.writeAsBytesSync(
        List<int>.filled(OpenKatDirectoryScanner.maxReportBytes, 0x20),
      );
      final over = File(p.join(root.path, 'over.json'));
      over.writeAsBytesSync(
        List<int>.filled(OpenKatDirectoryScanner.maxReportBytes + 1, 0x20),
      );

      final result = await const OpenKatDirectoryScanner().scan(root.path);
      final statuses = {
        for (final entry in result.manifest.entries) entry.path: entry.status,
      };

      expect(statuses['exact.json'], 'error: invalid json');
      expect(statuses['over.json'], contains('too large'));
    });

    test(
      'prepareDirectory verandert de gekozen boom byte voor byte niet',
      () async {
        final root = Directory.systemTemp.createTempSync('openkat-read-only-');
        addTearDown(() => root.deleteSync(recursive: true));
        final raw = Directory(p.join(root.path, 'raw-data'))..createSync();
        File(p.join(raw.path, 'not-a-report.json')).writeAsStringSync(
          '{"purpose":"read-only regression","nested":{"value":42}}',
        );
        File(p.join(root.path, 'keep.txt')).writeAsStringSync('blijf staan');
        final before = _directoryState(root);

        final prepared = await const OpenKatImportService().prepareDirectory(
          root.path,
        );

        expect(prepared.organizations, isEmpty);
        expect(_directoryState(root), before);
        expect(
          Directory(p.join(root.path, 'processed-data')).existsSync(),
          isFalse,
        );
        expect(
          Directory(p.join(root.path, 'presentations')).existsSync(),
          isFalse,
        );
      },
    );

    test(
      'beschikbaarheid en standaardfeiten komen uit bruikbare metingen',
      () async {
        const reliable = {OpenKatSourceFeature.reliableCveReferences};
        final organizations = [
          wizardOrganization(
            code: 'z',
            name: 'Zulu',
            snapshots: [
              wizardSnapshot(
                date: DateTime.utc(2026, 5, 1),
                source: 'z-old.json',
                sourceFeatures: reliable,
              ),
              wizardSnapshot(
                date: DateTime.utc(2026, 7, 1),
                source: 'z-new.json',
                sourceFeatures: reliable,
                findings: const [
                  OpenKatFinding(
                    id: 'z-1',
                    findingTypeId: 'KAT-1',
                    severity: 'HIGH',
                    systemId: 'shared',
                    cveIds: [' cve-2026-12345 '],
                  ),
                ],
                systems: const [OpenKatSystem(id: 'shared')],
              ),
            ],
          ),
          wizardOrganization(
            code: 'a',
            name: 'Alpha',
            snapshots: [
              wizardSnapshot(
                date: DateTime.utc(2026, 6, 1),
                source: 'a.json',
                sourceFeatures: reliable,
                findings: const [
                  OpenKatFinding(
                    id: 'a-1',
                    findingTypeId: 'KAT-1',
                    severity: 'critical',
                    systemId: 'shared',
                    cveIds: ['CVE-2026-12345'],
                  ),
                ],
                systems: const [
                  OpenKatSystem(id: 'shared'),
                  OpenKatSystem(id: 'other'),
                ],
              ),
              wizardSnapshot(
                date: DateTime.utc(2026, 8, 1),
                source: 'a-unusable.json',
                usable: false,
              ),
            ],
          ),
        ];
        final service = OpenKatWizardService(
          importer: _PreparedImporter(
            manifest: _manifest(3, skipped: 2),
            organizations: organizations,
          ),
        );

        final scan = await service.prepare('/reports');

        expect(scan.organizationOptions.map((item) => item.name), [
          'Alpha',
          'Zulu',
        ]);
        expect(scan.earliestMeasurement, DateTime.utc(2026, 5, 1));
        expect(scan.latestMeasurement, DateTime.utc(2026, 7, 1));
        expect(scan.preview.reportCount, 3);
        expect(scan.preview.skippedCount, 2);
        expect(scan.preview.organizationCount, 2);
        expect(scan.preview.criticalHighCount, 2);
        expect(scan.preview.systemCount, 3);
        expect(scan.preview.measurementDates, [
          DateTime.utc(2026, 5, 1),
          DateTime.utc(2026, 6, 1),
          DateTime.utc(2026, 7, 1),
        ]);
        expect(
          scan.preview.findingTrend,
          [0, 1, 2],
          reason:
              'de preview gebruikt dezelfde portfoliohistorie als het rapport',
        );
        expect(scan.cveOptions.single.id, 'CVE-2026-12345');
        expect(scan.cveOptions.single.organizationCount, 2);
        expect(scan.cveOptions.single.systemCount, 2);
        final availability = {
          for (final scenario in scan.scenarios)
            scenario.descriptor.id: scenario,
        };
        expect(availability, hasLength(OpenKatWizardScenarioId.values.length));
        expect(
          availability[OpenKatWizardScenarioId.portfolio]!.available,
          isTrue,
        );
        expect(
          availability[OpenKatWizardScenarioId.organizationProgress]!.available,
          isTrue,
        );
        expect(
          availability[OpenKatWizardScenarioId.cveExposure]!.available,
          isTrue,
        );
        expect(
          availability[OpenKatWizardScenarioId.dataQuality]!.available,
          isTrue,
        );
      },
    );

    test(
      'onbetrouwbare CVE-bron en één meetmoment sluiten alleen die kaarten',
      () async {
        final service = OpenKatWizardService(
          importer: _PreparedImporter(
            manifest: _manifest(1),
            organizations: [
              wizardOrganization(
                code: 'a',
                name: 'Alpha',
                snapshots: [
                  wizardSnapshot(
                    date: DateTime.utc(2026, 7, 1),
                    source: 'a.json',
                    findings: const [
                      OpenKatFinding(
                        id: 'f',
                        findingTypeId: 'KAT-1',
                        cveIds: ['CVE-2026-12345'],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );

        final scan = await service.prepare('/reports');
        final availability = {
          for (final scenario in scan.scenarios)
            scenario.descriptor.id: scenario,
        };
        expect(
          availability[OpenKatWizardScenarioId.portfolio]!.available,
          isTrue,
          reason: '${availability[OpenKatWizardScenarioId.portfolio]!.reason}',
        );
        expect(
          availability[OpenKatWizardScenarioId.dataQuality]!.available,
          isTrue,
        );
        expect(
          availability[OpenKatWizardScenarioId.organizationProgress]!.reason,
          OpenKatWizardUnavailableReason.oneMeasurement,
        );
        expect(
          availability[OpenKatWizardScenarioId.cveExposure]!.reason,
          OpenKatWizardUnavailableReason.noReliableCveReferences,
        );
      },
    );

    test(
      'custom enginevereiste bepaalt wizardbeschikbaarheid zonder tweede boom',
      () async {
        final engine = OpenKatReportEngine(
          registry: OpenKatReportScenarioRegistry(
            scenarios: [
              const _CapabilityRequiredManagementScenario(),
              for (final descriptor in OpenKatScenarioCatalog.recipes)
                if (descriptor.id != 'management-overview')
                  OpenKatDeclarativeScenario(descriptor),
            ],
          ),
        );
        final service = OpenKatWizardService(
          engine: engine,
          importer: _PreparedImporter(
            manifest: _manifest(1),
            organizations: [
              wizardOrganization(
                code: 'a',
                name: 'Alpha',
                snapshots: [
                  wizardSnapshot(
                    date: DateTime.utc(2026, 7, 1),
                    source: 'a.json',
                  ),
                ],
              ),
            ],
          ),
        );

        final scan = await service.prepare('/reports');
        final portfolio = scan.scenarios.singleWhere(
          (scenario) =>
              scenario.descriptor.id == OpenKatWizardScenarioId.portfolio,
        );
        final assessment = engine.assessScenarioCapabilities(
          scan.organizations,
          OpenKatReportRequest(
            scenarioId: 'management-overview',
            scope: const OpenKatReportScope.portfolio(),
            currentAsOf: DateTime.utc(2026, 7, 1),
          ),
        );

        expect(portfolio.available, isFalse);
        expect(assessment.missingRequiredCapabilities, {
          OpenKatReportCapability.reliableCveReferences,
        });
      },
    );

    test(
      'previewhistorie blijft bij veel meetpunten exact en begrensd',
      () async {
        final snapshots = [
          for (var index = 0; index < 1000; index++)
            wizardSnapshot(
              date: DateTime.utc(2020, 1, 1).add(Duration(days: index)),
              source: 'report-$index.json',
              findings: [
                for (var finding = 0; finding < index % 3; finding++)
                  OpenKatFinding(
                    id: '$index-$finding',
                    findingTypeId: 'KAT-$finding',
                    severity: 'medium',
                  ),
              ],
            ),
        ];
        final service = OpenKatWizardService(
          importer: _PreparedImporter(
            manifest: _manifest(snapshots.length),
            organizations: [
              wizardOrganization(
                code: 'a',
                name: 'Alpha',
                snapshots: snapshots,
              ),
            ],
          ),
        );

        final scan = await service.prepare('/reports');

        expect(
          scan.preview.findingTrend,
          hasLength(OpenKatWizardService.maximumPreviewHistoryPoints),
        );
        expect(scan.preview.findingTrend.first, 1);
        expect(scan.preview.findingTrend.last, 0);
      },
    );

    test('zonder bruikbare meting levert een eerlijke lege scan', () async {
      final service = OpenKatWizardService(
        importer: _PreparedImporter(
          manifest: _manifest(1),
          organizations: [
            wizardOrganization(
              code: 'a',
              name: 'Alpha',
              snapshots: [
                wizardSnapshot(
                  date: DateTime.utc(2026, 7, 1),
                  source: 'bad.json',
                  usable: false,
                ),
              ],
            ),
          ],
        ),
      );

      final scan = await service.prepare('/reports');

      expect(scan.organizationOptions, isEmpty);
      expect(scan.earliestMeasurement, isNull);
      expect(scan.latestMeasurement, isNull);
      expect(scan.preview.findingTrend, isEmpty);
      expect(
        scan.scenarios,
        everyElement(
          isA<OpenKatWizardScenarioAvailability>()
              .having((item) => item.available, 'available', isFalse)
              .having(
                (item) => item.reason,
                'reason',
                OpenKatWizardUnavailableReason.noUsableMeasurements,
              ),
        ),
      );
    });
  });

  test(
    'algemeen bijwerken vervangt views en bewaart handmatige dia’s en kopieën',
    () {
      const generatedNotes =
          '<!-- ocideck_openkat_view: report.management-overview.title -->';
      const manual = Slide(
        id: 'manual',
        type: SlideType.bullets,
        title: 'Mijn analyse',
      );
      final originalGenerated = OpenKatSlideProvenance.markGeneratedOrigin(
        const Slide(
          id: 'new',
          type: SlideType.title,
          title: 'Oud',
          notes: generatedNotes,
        ),
      );
      final copiedGenerated = Slide.duplicate(
        originalGenerated,
      ).copyWith(title: 'Bewuste kopie');
      const replacement = Slide(
        id: 'new',
        type: SlideType.title,
        title: 'Nieuw',
        notes: generatedNotes,
      );
      final existing = Deck(
        title: 'Bestaand',
        author: 'Auteur blijft',
        slides: [manual, originalGenerated, copiedGenerated],
      );
      const fresh = Deck(title: 'Vers', slides: [replacement]);

      final updated = const OpenKatDeckGenerator().updateGenerated(
        existing,
        fresh,
      );

      expect(updated.title, 'Vers');
      expect(updated.author, 'Auteur blijft');
      expect(updated.slides.map((slide) => slide.id), [
        manual.id,
        replacement.id,
        copiedGenerated.id,
      ]);
      expect(updated.slides.map((slide) => slide.title), [
        manual.title,
        replacement.title,
        copiedGenerated.title,
      ]);
    },
  );
}
