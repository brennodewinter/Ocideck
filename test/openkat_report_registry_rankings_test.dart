import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/openkat/openkat_wizard_models.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_deck_generator.dart';
import 'package:ocideck/services/openkat/openkat_report_composer.dart';
import 'package:ocideck/services/openkat/openkat_report_facts.dart';
import 'package:ocideck/services/openkat/openkat_report_rankings.dart';
import 'package:ocideck/services/openkat/openkat_report_scenarios.dart';
import 'package:ocideck/services/openkat/openkat_wizard_service.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_wizard_strings.dart';
import 'package:ocideck/widgets/dialogs/openkat_report_wizard/openkat_wizard_steps.dart';

const _allSourceFeatures = {
  OpenKatSourceFeature.stableAssetIdentity,
  OpenKatSourceFeature.stableFindingIdentity,
  OpenKatSourceFeature.reliableCveReferences,
  OpenKatSourceFeature.reliableMonitoringStatus,
  OpenKatSourceFeature.reliableOpenedAt,
  OpenKatSourceFeature.comparableMeasurementCoverage,
};

OpenKatFinding _finding({
  required String id,
  required String type,
  String severity = 'medium',
  String? systemId = 'asset.example',
  DateTime? openedAt,
  List<String> cveIds = const [],
}) => OpenKatFinding(
  id: id,
  findingTypeId: type,
  findingTypeName: 'Type $type',
  severity: severity,
  systemId: systemId,
  openedAt: openedAt,
  stableIdentity: true,
  cveIds: cveIds,
);

OpenKatSnapshot _snapshot({
  required DateTime date,
  required String source,
  required List<OpenKatFinding> findings,
  List<OpenKatSystem>? systems,
  Set<OpenKatSourceFeature> sourceFeatures = _allSourceFeatures,
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: source,
  sourceHash: 'sha256:$source',
  schema: 'test-adapter',
  findings: findings,
  systems:
      systems ??
      const [
        OpenKatSystem(
          id: 'asset.example',
          stableIdentity: true,
          monitoringStatus: OpenKatMonitoringStatus.monitored,
        ),
      ],
  controls: const {
    'control-a': OpenKatControlScore(name: 'Control A', compliant: 1, total: 2),
  },
  sourceFeatures: sourceFeatures,
  measurementScopeId: 'same-scope',
);

OpenKatOrganization _organization({
  required String code,
  String? name,
  required List<OpenKatSnapshot> snapshots,
}) => OpenKatOrganization(code: code, name: name ?? code, snapshots: snapshots);

OpenKatReportRequest _request(
  String scenarioId, {
  OpenKatReportScope? scope,
  OpenKatReportLanguage language = OpenKatReportLanguage.dutch,
  DateTime? currentAsOf,
  DateTime? previousAsOf,
  String? cveId,
}) => OpenKatReportRequest(
  scenarioId: scenarioId,
  scope: scope ?? const OpenKatReportScope.portfolio(),
  currentAsOf: currentAsOf ?? DateTime.utc(2026, 7, 20),
  previousAsOf: previousAsOf,
  cveId: cveId,
  language: language,
);

String _viewMarker(Slide slide) {
  final match = RegExp(
    r'<!--\s*ocideck_openkat_view:\s*([^\s>]+)\s*-->',
  ).firstMatch(slide.notes);
  return match?.group(1) ?? '';
}

void main() {
  group('scenario- en presentatieregisters', () {
    test(
      'registreert exact 22 unieke scenario-ID’s en behoudt de oude zes',
      () {
        final descriptors = OpenKatReportScenarioRegistry().descriptors;
        final ids = descriptors.map((descriptor) => descriptor.id).toList();

        expect(ids, hasLength(22));
        expect(ids.toSet(), hasLength(ids.length));
        expect(
          ids,
          containsAll(const {
            'management-overview',
            'weekly-comparison',
            'organization-overview',
            'cve-exposure',
            'monitoring-changes',
            'data-quality',
          }),
        );
        expect(
          ids.toSet(),
          OpenKatWizardScenarioId.values
              .map((id) => id.reportScenarioId)
              .toSet(),
        );
      },
    );

    test('ieder scenario gebruikt unieke, geregistreerde blokken', () {
      final registeredKinds = OpenKatReportBlockRegistry.definitions.keys
          .toSet();

      expect(
        registeredKinds,
        OpenKatReportBlockKind.values.toSet(),
        reason: 'een nieuw blok moet een intrinsiek contract krijgen',
      );
      for (final descriptor in OpenKatReportScenarioRegistry().descriptors) {
        expect(
          descriptor.blocks,
          isNotEmpty,
          reason: '${descriptor.id} mag geen leeg recept zijn',
        );
        expect(
          descriptor.blocks.map((block) => block.id).toSet(),
          hasLength(descriptor.blocks.length),
          reason: '${descriptor.id} heeft dubbele blok-ID’s',
        );
        expect(
          descriptor.blocks.map((block) => block.kind).toSet(),
          hasLength(descriptor.blocks.length),
          reason: '${descriptor.id} heeft dezelfde bloksoort dubbel',
        );
        for (final block in descriptor.blocks) {
          expect(
            registeredKinds,
            contains(block.kind),
            reason: '${descriptor.id}/${block.id} omzeilt het blokregister',
          );
        }
      }
    });

    test('ieder recept beantwoordt onafhankelijk zijn beloofde hoofdvraag', () {
      const expectedPrimaryBlock = <String, OpenKatReportBlockKind>{
        'management-overview': OpenKatReportBlockKind.portfolioSummary,
        'weekly-comparison': OpenKatReportBlockKind.portfolioTrend,
        'organization-overview': OpenKatReportBlockKind.organizationOverview,
        'cve-exposure': OpenKatReportBlockKind.cveExposure,
        'monitoring-changes': OpenKatReportBlockKind.monitoringChanges,
        'data-quality': OpenKatReportBlockKind.measurementAvailability,
        'organization-comparison':
            OpenKatReportBlockKind.organizationComparison,
        'portfolio-trend': OpenKatReportBlockKind.portfolioTrend,
        'finding-type-prevalence': OpenKatReportBlockKind.findingTypePrevalence,
        'critical-high-concentration':
            OpenKatReportBlockKind.severityConcentration,
        'cve-landscape': OpenKatReportBlockKind.cveLandscape,
        'cve-changes': OpenKatReportBlockKind.cveChanges,
        'finding-lifecycle': OpenKatReportBlockKind.findingLifecycle,
        'finding-age': OpenKatReportBlockKind.findingAge,
        'system-hotspots': OpenKatReportBlockKind.systemHotspots,
        'system-changes': OpenKatReportBlockKind.systemChanges,
        'control-coverage': OpenKatReportBlockKind.controlCoverage,
        'control-changes': OpenKatReportBlockKind.controlChanges,
        'recommendations-overview': OpenKatReportBlockKind.recommendations,
        'asset-inventory': OpenKatReportBlockKind.assetInventory,
        'monitoring-coverage': OpenKatReportBlockKind.monitoringCoverage,
        'measurement-accountability':
            OpenKatReportBlockKind.measurementAccountability,
      };
      final recipes = {
        for (final descriptor in OpenKatReportScenarioRegistry().descriptors)
          descriptor.id: descriptor,
      };

      expect(recipes.keys.toSet(), expectedPrimaryBlock.keys.toSet());
      for (final entry in expectedPrimaryBlock.entries) {
        expect(
          recipes[entry.key]!.blocks.map((block) => block.kind),
          contains(entry.value),
          reason: '${entry.key} moet ${entry.value.name} werkelijk bouwen',
        );
      }
      expect(recipes['cve-exposure']!.requiresCveId, isTrue);
      for (final id in const [
        'weekly-comparison',
        'portfolio-trend',
        'cve-changes',
        'finding-lifecycle',
        'system-changes',
        'control-changes',
        'monitoring-changes',
      ]) {
        expect(
          recipes[id]!.requiresPreviousAsOf,
          isTrue,
          reason:
              '$id belooft een vergelijking en moet een eerdere datum eisen',
        );
      }
    });

    test(
      'wizard-, familie- en tekstregisters dekken hun contract volledig',
      () {
        final wizard = OpenKatWizardService.scenarioDescriptors;

        expect(
          wizard.map((descriptor) => descriptor.id).toSet(),
          OpenKatWizardScenarioId.values.toSet(),
        );
        expect(
          wizard.map((descriptor) => descriptor.family).toSet(),
          OpenKatReportFamilyId.values.toSet(),
        );
        expect(
          wizard.expand((descriptor) => descriptor.inputs).toSet(),
          OpenKatWizardInputKind.values.toSet(),
          reason: 'iedere invoersoort moet door een recept bereikbaar zijn',
        );
        expect(
          openKatWizardInputRenderers.keys.toSet(),
          OpenKatWizardInputKind.values.toSet(),
          reason: 'iedere gedeclareerde invoersoort moet een renderer hebben',
        );
        expect(
          openKatFamilyTitleRegistry.keys.toSet(),
          OpenKatReportFamilyId.values.toSet(),
        );
        expect(
          openKatFamilyDescriptionRegistry.keys.toSet(),
          OpenKatReportFamilyId.values.toSet(),
        );
        expect(
          openKatScenarioTitleRegistry.keys.toSet(),
          OpenKatWizardScenarioId.values.toSet(),
        );
        expect(
          openKatScenarioDescriptionRegistry.keys.toSet(),
          OpenKatWizardScenarioId.values.toSet(),
        );
        expect(
          openKatBlockTitleRegistry.keys.toSet(),
          OpenKatReportBlockKind.values.toSet(),
        );
      },
    );

    test('intrinsieke blokvoorwaarden dragen gevoelige bronpreconditions', () {
      final definitions = OpenKatReportBlockRegistry.definitions;

      expect(definitions[OpenKatReportBlockKind.organizationOverview]!.scopes, {
        OpenKatReportScopeKind.organization,
      });
      expect(definitions[OpenKatReportBlockKind.cveExposure]!.capabilities, {
        OpenKatReportCapability.reliableCveReferences,
      });
      expect(
        definitions[OpenKatReportBlockKind.cveExposure]!.requiresCveId,
        isTrue,
      );
      expect(
        definitions[OpenKatReportBlockKind.cveChanges]!.capabilities,
        containsAll({
          OpenKatReportCapability.reliableCveReferences,
          OpenKatReportCapability.historicalSnapshots,
          OpenKatReportCapability.comparableMeasurementCoverage,
        }),
      );
      expect(definitions[OpenKatReportBlockKind.findingAge]!.capabilities, {
        OpenKatReportCapability.reliableOpenedAt,
      });
      expect(
        definitions[OpenKatReportBlockKind.monitoringCoverage]!.capabilities,
        {OpenKatReportCapability.reliableMonitoringStatus},
      );
      expect(
        definitions[OpenKatReportBlockKind.systemChanges]!.requiresPreviousAsOf,
        isTrue,
      );
      expect(
        definitions[OpenKatReportBlockKind.controlChanges]!.capabilities,
        contains(OpenKatReportCapability.comparableControlsWithDenominator),
      );
    });
  });

  group('deterministische rankings en begrenzing', () {
    test('organisaties sorteren critical, high, systemen en dan naam', () {
      OpenKatOrganization ranked(
        String code,
        String name, {
        required int critical,
        required int high,
        required int systems,
      }) {
        final findings = <OpenKatFinding>[
          for (var i = 0; i < critical; i++)
            _finding(
              id: '$code-c-$i',
              type: 'critical-$i',
              severity: 'critical',
              systemId: '$code-system-${i % systems}',
            ),
          for (var i = 0; i < high; i++)
            _finding(
              id: '$code-h-$i',
              type: 'high-$i',
              severity: 'high',
              systemId: '$code-system-${(critical + i) % systems}',
            ),
        ];
        return _organization(
          code: code,
          name: name,
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 7, 1),
              source: '$code.json',
              findings: findings,
            ),
          ],
        );
      }

      final facts = OpenKatReportFacts([
        ranked('critical', 'Z', critical: 2, high: 0, systems: 1),
        ranked('high', 'Z', critical: 1, high: 2, systems: 2),
        ranked('systems', 'Z', critical: 1, high: 1, systems: 2),
        ranked('name-z', 'Zulu', critical: 1, high: 1, systems: 1),
        ranked('name-a', 'Alpha', critical: 1, high: 1, systems: 1),
      ]);

      expect(
        facts
            .organizationRanking(_request('organization-comparison'))
            .map((item) => item.code),
        ['critical', 'high', 'systems', 'name-a', 'name-z'],
      );
    });

    test('findingtypen breken volledige ties op stabiele ID', () {
      final facts = OpenKatReportFacts([
        _organization(
          code: 'alpha',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 7, 1),
              source: 'alpha.json',
              findings: [
                _finding(id: 'z', type: 'KAT-Z'),
                _finding(id: 'a', type: 'KAT-A'),
              ],
            ),
          ],
        ),
      ]);

      expect(
        facts
            .findingTypePrevalence(_request('finding-type-prevalence'))
            .map((item) => item.findingTypeId),
        ['KAT-A', 'KAT-Z'],
      );
    });

    test(
      'meer dan zeven resultaten blijven in data en krijgen viewlimit 7',
      () {
        final organization = _organization(
          code: 'alpha',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 7, 1),
              source: 'alpha.json',
              findings: [
                for (var i = 0; i < 9; i++)
                  _finding(id: 'finding-$i', type: 'KAT-$i'),
              ],
            ),
          ],
        );
        final result = OpenKatReportEngine().generate([
          organization,
        ], _request('finding-type-prevalence'));
        final ranking = result.deck!.slides.singleWhere(
          (slide) =>
              _viewMarker(slide).endsWith('.finding-type-prevalence.ranking'),
        );

        expect(ranking.tableRows, hasLength(10));
        expect(ranking.viewLimit?.limit, 7);
        expect(
          ranking.tableRows.skip(1).map((row) => row.first).toSet(),
          hasLength(9),
        );
      },
    );
  });

  group('CVE-deduplicatie', () {
    test('dedupliceert per CVE, organisatie, systeem en finding', () {
      final duplicate = _finding(
        id: 'same-finding',
        type: 'KAT-CVE',
        severity: 'high',
        systemId: 'shared.example',
        cveIds: const ['cve-2026-1234', 'CVE-2026-1234'],
      );
      final facts = OpenKatReportFacts([
        _organization(
          code: 'alpha',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 7, 1),
              source: 'alpha.json',
              findings: [
                duplicate,
                duplicate,
                _finding(
                  id: 'same-finding',
                  type: 'KAT-CVE',
                  systemId: 'other.example',
                  cveIds: const ['CVE-2026-1234'],
                ),
              ],
            ),
          ],
        ),
        _organization(
          code: 'beta',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 7, 1),
              source: 'beta.json',
              findings: [duplicate],
            ),
          ],
        ),
      ]);

      final cve = facts.cveLandscape(_request('cve-landscape')).single;
      expect(cve.cveId, 'CVE-2026-1234');
      expect(cve.organizationCount, 2);
      expect(cve.systemCount, 3);
      expect(cve.observationCount, 3);
      expect(cve.severityCounts.values.fold(0, (a, b) => a + b), 3);
    });
  });

  group('presentatiecontract', () {
    test('ouderdom gebruikt de meetdatum en blijft klok-onafhankelijk', () {
      final organization = _organization(
        code: 'alpha',
        snapshots: [
          _snapshot(
            date: DateTime.utc(2026, 3, 3),
            source: 'alpha.json',
            findings: [
              _finding(
                id: 'old',
                type: 'KAT-OLD',
                openedAt: DateTime.utc(2026, 1, 1),
              ),
            ],
          ),
        ],
      );
      final result = OpenKatReportEngine().generate([
        organization,
      ], _request('finding-age', currentAsOf: DateTime.utc(2026, 7, 20)));
      final slide = result.deck!.slides.singleWhere(
        (item) => _viewMarker(item).endsWith('.finding-age.ranking'),
      );

      expect(slide.tableRows[1].last, '61');
      expect(slide.tableRows.first.last, 'Dagen op meetdatum');
    });

    test(
      'Nederlands en Engels delen stabiele views maar niet zichtbare tekst',
      () {
        final organizations = [
          _organization(
            code: 'alpha',
            snapshots: [
              _snapshot(
                date: DateTime.utc(2026, 7, 1),
                source: 'alpha.json',
                findings: [_finding(id: 'f1', type: 'KAT-1')],
              ),
            ],
          ),
        ];
        final engine = OpenKatReportEngine();
        final dutch = engine.generate(
          organizations,
          _request('finding-type-prevalence'),
        );
        final english = engine.generate(
          organizations,
          _request(
            'finding-type-prevalence',
            language: OpenKatReportLanguage.english,
          ),
        );
        final dutchSlide = dutch.deck!.slides.singleWhere(
          (slide) => _viewMarker(slide).endsWith('.ranking'),
        );
        final englishSlide = english.deck!.slides.singleWhere(
          (slide) => _viewMarker(slide).endsWith('.ranking'),
        );

        expect(_viewMarker(dutchSlide), _viewMarker(englishSlide));
        expect(dutchSlide.title, contains('Findingtypen'));
        expect(englishSlide.title, contains('Finding types'));
        expect(dutch.deck!.language, 'nl');
        expect(english.deck!.language, 'en');
      },
    );

    test('ieder blok krijgt een scenario- en blokgebonden viewmarker', () {
      final organizations = [
        _organization(
          code: 'alpha',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              source: 'alpha-previous.json',
              findings: [
                _finding(
                  id: 'old',
                  type: 'KAT-OLD',
                  openedAt: DateTime.utc(2026, 1, 1),
                  cveIds: const ['CVE-2026-1234'],
                ),
              ],
            ),
            _snapshot(
              date: DateTime.utc(2026, 7, 1),
              source: 'alpha-current.json',
              findings: [
                _finding(
                  id: 'new',
                  type: 'KAT-NEW',
                  openedAt: DateTime.utc(2026, 2, 1),
                  cveIds: const ['CVE-2026-5678'],
                ),
              ],
            ),
          ],
        ),
        _organization(
          code: 'beta',
          snapshots: [
            _snapshot(
              date: DateTime.utc(2026, 6, 1),
              source: 'beta-previous.json',
              findings: [
                _finding(
                  id: 'old-beta',
                  type: 'KAT-OLD',
                  openedAt: DateTime.utc(2026, 1, 2),
                ),
              ],
            ),
            _snapshot(
              date: DateTime.utc(2026, 7, 1),
              source: 'beta-current.json',
              findings: [
                _finding(
                  id: 'new-beta',
                  type: 'KAT-NEW',
                  openedAt: DateTime.utc(2026, 2, 2),
                ),
              ],
            ),
          ],
        ),
      ];
      final facts = OpenKatReportFacts(organizations);

      for (final descriptor in OpenKatScenarioCatalog.recipes) {
        final request = _request(
          descriptor.id,
          scope:
              descriptor.scopes.length == 1 &&
                  descriptor.scopes.single ==
                      OpenKatReportScopeKind.organization
              ? OpenKatReportScope.organization('alpha')
              : const OpenKatReportScope.portfolio(),
          previousAsOf: descriptor.requiresPreviousAsOf
              ? DateTime.utc(2026, 6, 15)
              : null,
          cveId: descriptor.requiresCveId ? 'CVE-2026-5678' : null,
        );
        final deck = OpenKatReportComposer(facts).compose(
          request,
          OpenKatReportPlan(
            scenarioId: descriptor.id,
            blocks: descriptor.blocks,
          ),
        );
        final markers = deck.slides.map(_viewMarker).toList();

        expect(
          markers,
          everyElement(startsWith('report.${descriptor.id}.')),
          reason: descriptor.id,
        );
        expect(
          markers.toSet(),
          hasLength(markers.length),
          reason: '${descriptor.id} heeft dubbele viewmarkers',
        );
        for (final block in descriptor.blocks) {
          expect(
            markers.any(
              (marker) =>
                  marker.startsWith('report.${descriptor.id}.${block.id}.'),
            ),
            isTrue,
            reason: '${descriptor.id}/${block.id} mist een stabiele view',
          );
        }
      }
    });

    test('scenariowissel bewaart handmatige dia en ruimt oude views op', () {
      final organization = _organization(
        code: 'alpha',
        snapshots: [
          _snapshot(
            date: DateTime.utc(2026, 7, 1),
            source: 'alpha.json',
            findings: [_finding(id: 'f1', type: 'KAT-1')],
          ),
        ],
      );
      final engine = OpenKatReportEngine();
      final oldDeck = engine.generate([
        organization,
      ], _request('finding-type-prevalence')).deck!;
      const manual = Slide(
        id: 'manual-analysis',
        type: SlideType.bullets,
        title: 'Handmatige analyse',
        bullets: ['Blijft behouden'],
      );
      final existing = oldDeck.copyWith(slides: [...oldDeck.slides, manual]);
      final fresh = engine.generate([
        organization,
      ], _request('system-hotspots')).deck!;

      final updated = const OpenKatDeckGenerator().updateGenerated(
        existing,
        fresh,
      );

      expect(updated.slides, contains(manual));
      expect(
        updated.slides.map(_viewMarker),
        isNot(contains(startsWith('report.finding-type-prevalence.'))),
      );
      expect(
        updated.slides.map(_viewMarker),
        contains(startsWith('report.system-hotspots.')),
      );
    });
  });
}
