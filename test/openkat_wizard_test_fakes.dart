import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/openkat/openkat_models.dart';
import 'package:ocideck/models/openkat/openkat_reporting_models.dart';
import 'package:ocideck/models/openkat/openkat_wizard_models.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/openkat/openkat_wizard_service.dart';

OpenKatSnapshot wizardSnapshot({
  required DateTime date,
  required String source,
  bool usable = true,
  Set<OpenKatSourceFeature> sourceFeatures = const {},
  List<OpenKatFinding> findings = const [],
  List<OpenKatSystem> systems = const [
    OpenKatSystem(id: 'system.example', hostname: 'system.example'),
  ],
}) => OpenKatSnapshot(
  reportDate: date,
  sourceFile: source,
  sourceHash: 'sha256:$source',
  usable: usable,
  sourceFeatures: sourceFeatures,
  findings: findings,
  systems: systems,
);

OpenKatOrganization wizardOrganization({
  required String code,
  required String name,
  required List<OpenKatSnapshot> snapshots,
}) => OpenKatOrganization(code: code, name: name, snapshots: snapshots);

OpenKatWizardScan wizardScan({
  int reportCount = 3,
  int skippedCount = 1,
  List<OpenKatOrganization>? organizations,
  List<OpenKatWizardScenarioAvailability>? scenarios,
  List<OpenKatWizardCveOption> cveOptions = const [
    OpenKatWizardCveOption(
      id: 'CVE-2026-12345',
      organizationCount: 2,
      systemCount: 3,
    ),
  ],
  String organizationName = 'Een organisatie met een bijzonder lange naam',
}) {
  final snapshots = [
    wizardSnapshot(date: DateTime.utc(2026, 6, 1), source: 'org-previous.json'),
    wizardSnapshot(
      date: DateTime.utc(2026, 7, 1),
      source: 'org-current.json',
      sourceFeatures: const {OpenKatSourceFeature.reliableCveReferences},
      findings: const [
        OpenKatFinding(
          id: 'finding-1',
          findingTypeId: 'KAT-1',
          severity: 'critical',
          systemId: 'system.example',
          cveIds: ['CVE-2026-12345'],
        ),
      ],
    ),
  ];
  final sourceOrganizations =
      organizations ??
      [
        wizardOrganization(
          code: 'org-a',
          name: organizationName,
          snapshots: snapshots,
        ),
        wizardOrganization(
          code: 'org-b',
          name: 'Tweede organisatie',
          snapshots: [
            wizardSnapshot(
              date: DateTime.utc(2026, 6, 1),
              source: 'org-b.json',
              sourceFeatures: const {
                OpenKatSourceFeature.reliableCveReferences,
              },
            ),
          ],
        ),
      ];
  final scenarioValues =
      scenarios ??
      [
        for (final descriptor in OpenKatWizardService.scenarioDescriptors)
          OpenKatWizardScenarioAvailability(
            descriptor: descriptor,
            available: true,
          ),
      ];
  return OpenKatWizardScan(
    directory: '/tmp/openkat-fixture',
    manifest: OpenKatManifest(
      parserVersion: 'test',
      importedAt: DateTime.utc(2026, 7, 2),
      directory: '/tmp/openkat-fixture',
      entries: [
        for (var index = 0; index < reportCount; index++)
          OpenKatManifestEntry(
            path: 'report-$index.json',
            hash: '$index',
            status: 'ok',
          ),
        for (var index = 0; index < skippedCount; index++)
          OpenKatManifestEntry(
            path: 'skipped-$index.json',
            hash: 'skipped-$index',
            status: 'unrecognized',
          ),
      ],
    ),
    organizations: sourceOrganizations,
    organizationOptions: [
      for (final organization in sourceOrganizations)
        OpenKatWizardOrganizationOption(
          code: organization.code,
          name: organization.name,
          latestMeasurement: organization.snapshots.last.reportDate,
          measurementCount: organization.snapshots
              .where((snapshot) => snapshot.usable)
              .length,
        ),
    ],
    cveOptions: cveOptions,
    scenarios: scenarioValues,
    preview: OpenKatWizardPreviewFacts(
      organizationCount: sourceOrganizations.length,
      reportCount: reportCount,
      skippedCount: skippedCount,
      criticalHighCount: 1,
      systemCount: 2,
      findingsByOrganization: {
        for (final organization in sourceOrganizations)
          organization.name: organization.current?.findings.length ?? 0,
      },
      measurementDates: [DateTime.utc(2026, 6, 1), DateTime.utc(2026, 7, 1)],
      findingTrend: const [0, 1],
    ),
    earliestMeasurement: DateTime.utc(2026, 6, 1),
    latestMeasurement: DateTime.utc(2026, 7, 1),
  );
}

OpenKatReportResult wizardReport({
  String scenarioId = 'management-overview',
  Deck? deck,
  List<OpenKatReportDiagnostic> diagnostics = const [],
}) => OpenKatReportResult(
  deck:
      deck ??
      const Deck(
        title: 'OpenKAT-rapport',
        slides: [
          Slide(
            id: 'generated',
            type: SlideType.title,
            title: 'OpenKAT',
            notes:
                '<!-- ocideck_openkat_view: report.management-overview.title -->',
          ),
        ],
      ),
  plan: OpenKatReportPlan(
    scenarioId: scenarioId,
    blocks: const [
      OpenKatReportBlock(
        id: 'availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  ),
  scenarioId: scenarioId,
  scope: const OpenKatReportScope.portfolio(),
  measurements: const [],
  diagnostics: diagnostics,
  missingCapabilities: const {},
  sourceTraces: const [],
);

class FakeOpenKatWizardGateway implements OpenKatWizardGateway {
  OpenKatWizardScan prepared;
  Object? prepareError;
  Object? buildError;
  OpenKatReportResult? report;
  int prepareCalls = 0;
  int previewCalls = 0;
  int buildCalls = 0;
  Deck? lastExisting;
  OpenKatWizardRecipe? lastRecipe;

  FakeOpenKatWizardGateway({
    OpenKatWizardScan? prepared,
    this.prepareError,
    this.buildError,
    this.report,
  }) : prepared = prepared ?? wizardScan();

  @override
  Future<OpenKatWizardScan> prepare(String directory) async {
    prepareCalls++;
    if (prepareError case final error?) throw error;
    return prepared;
  }

  @override
  OpenKatReportResult preview(
    OpenKatWizardScan scan,
    OpenKatWizardRecipe recipe,
  ) {
    previewCalls++;
    lastRecipe = recipe;
    return report ??
        wizardReport(scenarioId: recipe.scenarioId.reportScenarioId);
  }

  @override
  OpenKatWizardBuildResult build(
    OpenKatWizardScan scan,
    OpenKatWizardRecipe recipe, {
    Deck? existing,
  }) {
    buildCalls++;
    lastExisting = existing;
    lastRecipe = recipe;
    if (buildError case final error?) throw error;
    final result = OpenKatWizardBuildResult(
      report:
          report ??
          wizardReport(scenarioId: recipe.scenarioId.reportScenarioId),
      recipe: recipe,
      scan: scan,
      updated: existing != null,
      usedReports: scan.preview.reportCount,
      skippedReports: scan.preview.skippedCount,
    );
    return result;
  }
}
