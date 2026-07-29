import 'openkat_models.dart';
import 'openkat_reporting_models.dart';

enum OpenKatWizardStep { scenario, inputs, review }

enum OpenKatWizardScanStatus { idle, scanning, ready, empty, failed }

enum OpenKatWizardBuildStatus { idle, building, succeeded, failed }

enum OpenKatWizardInputKind {
  organization,
  period,
  cve,
  language,
  title,
  organizations,
}

enum OpenKatWizardScenarioId {
  portfolio('management-overview'),
  organizationProgress('weekly-comparison'),
  cveExposure('cve-exposure'),
  dataQuality('data-quality');

  final String reportScenarioId;
  const OpenKatWizardScenarioId(this.reportScenarioId);
}

enum OpenKatWizardUnavailableReason {
  noUsableMeasurements,
  oneMeasurement,
  noReliableCveReferences,
}

class OpenKatWizardScenarioDescriptor {
  final OpenKatWizardScenarioId id;
  final Set<OpenKatWizardInputKind> inputs;
  final bool recommended;

  const OpenKatWizardScenarioDescriptor({
    required this.id,
    required this.inputs,
    this.recommended = false,
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
