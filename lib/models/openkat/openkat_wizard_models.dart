import 'openkat_models.dart';
import 'openkat_reporting_models.dart';

enum OpenKatWizardStep { scenario, inputs, review }

enum OpenKatWizardScanStatus { idle, scanning, ready, empty, failed }

enum OpenKatWizardBuildStatus { idle, building, succeeded, failed }

enum OpenKatWizardInputKind {
  organization,
  organizations,
  currentAsOf,
  previousAsOf,
  cve,
  language,
  title,
}

enum OpenKatReportFamilyId {
  organizationsManagement,
  organizationProgress,
  cves,
  dataQuality,
}

enum OpenKatWizardPreviewKind {
  summary,
  comparison,
  trend,
  findings,
  systems,
  controls,
  cve,
  monitoring,
  accountability,
}

/// Stabiele, getypepte scenariocode zonder enum-switchketen in de frontend.
class OpenKatWizardScenarioId {
  final String name;
  final String reportScenarioId;

  const OpenKatWizardScenarioId._(this.name, this.reportScenarioId);

  static const portfolio = OpenKatWizardScenarioId._(
    'portfolio',
    'management-overview',
  );
  static const organizationProgress = OpenKatWizardScenarioId._(
    'organizationProgress',
    'weekly-comparison',
  );
  static const cveExposure = OpenKatWizardScenarioId._(
    'cveExposure',
    'cve-exposure',
  );
  static const dataQuality = OpenKatWizardScenarioId._(
    'dataQuality',
    'data-quality',
  );
  static const organizationComparison = OpenKatWizardScenarioId._(
    'organizationComparison',
    'organization-comparison',
  );
  static const portfolioTrend = OpenKatWizardScenarioId._(
    'portfolioTrend',
    'portfolio-trend',
  );
  static const findingTypePrevalence = OpenKatWizardScenarioId._(
    'findingTypePrevalence',
    'finding-type-prevalence',
  );
  static const severityConcentration = OpenKatWizardScenarioId._(
    'severityConcentration',
    'critical-high-concentration',
  );
  static const cveLandscape = OpenKatWizardScenarioId._(
    'cveLandscape',
    'cve-landscape',
  );
  static const cveChanges = OpenKatWizardScenarioId._(
    'cveChanges',
    'cve-changes',
  );
  static const organizationOverview = OpenKatWizardScenarioId._(
    'organizationOverview',
    'organization-overview',
  );
  static const findingLifecycle = OpenKatWizardScenarioId._(
    'findingLifecycle',
    'finding-lifecycle',
  );
  static const findingAge = OpenKatWizardScenarioId._(
    'findingAge',
    'finding-age',
  );
  static const systemHotspots = OpenKatWizardScenarioId._(
    'systemHotspots',
    'system-hotspots',
  );
  static const systemChanges = OpenKatWizardScenarioId._(
    'systemChanges',
    'system-changes',
  );
  static const controlCoverage = OpenKatWizardScenarioId._(
    'controlCoverage',
    'control-coverage',
  );
  static const controlChanges = OpenKatWizardScenarioId._(
    'controlChanges',
    'control-changes',
  );
  static const recommendations = OpenKatWizardScenarioId._(
    'recommendations',
    'recommendations-overview',
  );
  static const assetInventory = OpenKatWizardScenarioId._(
    'assetInventory',
    'asset-inventory',
  );
  static const monitoringCoverage = OpenKatWizardScenarioId._(
    'monitoringCoverage',
    'monitoring-coverage',
  );
  static const monitoringChanges = OpenKatWizardScenarioId._(
    'monitoringChanges',
    'monitoring-changes',
  );
  static const measurementAccountability = OpenKatWizardScenarioId._(
    'measurementAccountability',
    'measurement-accountability',
  );

  static const values = [
    portfolio,
    organizationComparison,
    portfolioTrend,
    findingTypePrevalence,
    severityConcentration,
    controlCoverage,
    recommendations,
    organizationOverview,
    organizationProgress,
    findingLifecycle,
    findingAge,
    systemHotspots,
    systemChanges,
    controlChanges,
    assetInventory,
    monitoringCoverage,
    monitoringChanges,
    cveExposure,
    cveLandscape,
    cveChanges,
    dataQuality,
    measurementAccountability,
  ];

  static OpenKatWizardScenarioId? fromReportScenarioId(String id) {
    for (final value in values) {
      if (value.reportScenarioId == id) return value;
    }
    return null;
  }
}

enum OpenKatWizardUnavailableReason {
  noUsableMeasurements,
  oneMeasurement,
  noReliableCveReferences,
  noReliableMonitoringStatus,
  noReliableOpenedAt,
  noStableFindingIdentity,
  noComparableCoverage,
  noControlDenominators,
  noStableAssetIdentity,
  unsupportedScope,
  missingRequiredData,
}

class OpenKatWizardScenarioDescriptor {
  final OpenKatWizardScenarioId id;
  final OpenKatReportFamilyId family;
  final Set<OpenKatWizardInputKind> inputs;
  final OpenKatWizardPreviewKind previewKind;
  final bool recommended;
  final int order;
  final bool currentAsOfUsesClock;
  final Duration? maximumSnapshotAge;

  const OpenKatWizardScenarioDescriptor({
    required this.id,
    required this.family,
    required this.inputs,
    required this.previewKind,
    this.recommended = false,
    required this.order,
    this.currentAsOfUsesClock = false,
    this.maximumSnapshotAge,
  });
}

class OpenKatWizardScenarioAvailability {
  final OpenKatWizardScenarioDescriptor descriptor;
  final bool available;
  final OpenKatWizardUnavailableReason? reason;

  const OpenKatWizardScenarioAvailability({
    required this.descriptor,
    required this.available,
    this.reason,
  });
}

class OpenKatWizardOrganizationOption {
  final String code;
  final String name;
  final DateTime latestMeasurement;
  final int measurementCount;

  const OpenKatWizardOrganizationOption({
    required this.code,
    required this.name,
    required this.latestMeasurement,
    required this.measurementCount,
  });
}

class OpenKatWizardCveOption {
  final String id;
  final int organizationCount;
  final int systemCount;

  const OpenKatWizardCveOption({
    required this.id,
    required this.organizationCount,
    required this.systemCount,
  });
}

class OpenKatWizardPreviewFacts {
  final int organizationCount;
  final int reportCount;
  final int skippedCount;
  final int criticalHighCount;
  final int systemCount;
  final Map<String, int> findingsByOrganization;
  final List<DateTime> measurementDates;
  final List<int> findingTrend;

  const OpenKatWizardPreviewFacts({
    required this.organizationCount,
    required this.reportCount,
    required this.skippedCount,
    required this.criticalHighCount,
    required this.systemCount,
    required this.findingsByOrganization,
    required this.measurementDates,
    required this.findingTrend,
  });
}

class OpenKatWizardScan {
  final String directory;
  final OpenKatManifest manifest;
  final List<OpenKatOrganization> organizations;
  final List<OpenKatWizardOrganizationOption> organizationOptions;
  final List<OpenKatWizardCveOption> cveOptions;
  final List<OpenKatWizardScenarioAvailability> scenarios;
  final OpenKatWizardPreviewFacts preview;
  final DateTime? earliestMeasurement;
  final DateTime? latestMeasurement;

  const OpenKatWizardScan({
    required this.directory,
    required this.manifest,
    required this.organizations,
    required this.organizationOptions,
    required this.cveOptions,
    required this.scenarios,
    required this.preview,
    required this.earliestMeasurement,
    required this.latestMeasurement,
  });
}

class OpenKatWizardRecipe {
  final OpenKatWizardScenarioId scenarioId;
  final String? organizationCode;
  final Set<String> organizationCodes;
  final DateTime currentAsOf;
  final DateTime? previousAsOf;
  final String? cveId;
  final OpenKatReportLanguage language;
  final String? title;
  final Duration? maximumSnapshotAge;

  const OpenKatWizardRecipe({
    required this.scenarioId,
    required this.currentAsOf,
    this.organizationCode,
    this.organizationCodes = const {},
    this.previousAsOf,
    this.cveId,
    this.language = OpenKatReportLanguage.dutch,
    this.title,
    this.maximumSnapshotAge,
  });

  OpenKatReportRequest toRequest() => OpenKatReportRequest(
    scenarioId: scenarioId.reportScenarioId,
    scope: organizationCode == null
        ? const OpenKatReportScope.portfolio()
        : OpenKatReportScope.organization(organizationCode!),
    currentAsOf: currentAsOf,
    previousAsOf: previousAsOf,
    cveId: cveId,
    language: language,
    title: title?.trim().isEmpty ?? true ? null : title!.trim(),
    policy: OpenKatReportPolicy(maximumSnapshotAge: maximumSnapshotAge),
  );
}

class OpenKatWizardBuildResult {
  final OpenKatReportResult report;
  final OpenKatWizardRecipe recipe;
  final OpenKatWizardScan scan;
  final bool updated;
  final int usedReports;
  final int skippedReports;

  const OpenKatWizardBuildResult({
    required this.report,
    required this.recipe,
    required this.scan,
    required this.updated,
    required this.usedReports,
    required this.skippedReports,
  });
}
