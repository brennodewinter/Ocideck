import 'dart:collection';

import '../../models/deck.dart';
import '../../models/openkat/openkat_models.dart';
import '../../models/openkat/openkat_reporting_models.dart';
import '../../models/openkat/openkat_wizard_models.dart';
import 'openkat_deck_generator.dart';
import 'openkat_import_service.dart';

abstract interface class OpenKatWizardGateway {
  Future<OpenKatWizardScan> prepare(String directory);

  OpenKatReportResult preview(
    OpenKatWizardScan scan,
    OpenKatWizardRecipe recipe,
  );

  OpenKatWizardBuildResult build(
    OpenKatWizardScan scan,
    OpenKatWizardRecipe recipe, {
    Deck? existing,
  });
}

/// Dunne frontendfaçade rond de scanner en de headless rapportagemotor.
class OpenKatWizardService implements OpenKatWizardGateway {
  static const int maximumPreviewHistoryPoints = 120;

  final OpenKatImportService importer;
  final OpenKatReportEngine engine;
  final OpenKatDeckGenerator deckGenerator;

  OpenKatWizardService({
    this.importer = const OpenKatImportService(),
    OpenKatReportEngine? engine,
    this.deckGenerator = const OpenKatDeckGenerator(),
  }) : engine = engine ?? OpenKatReportEngine() {
    final registered = this.engine.registry.descriptors
        .map((descriptor) => descriptor.id)
        .toSet();
    for (final descriptor in scenarioDescriptors) {
      if (!registered.contains(descriptor.id.reportScenarioId)) {
        throw StateError(
          'OpenKAT-wizardscenario ontbreekt in motor: '
          '${descriptor.id.reportScenarioId}',
        );
      }
    }
  }

  static const _portfolioInputs = {
    OpenKatWizardInputKind.organizations,
    OpenKatWizardInputKind.currentAsOf,
    OpenKatWizardInputKind.language,
    OpenKatWizardInputKind.title,
  };
  static const _portfolioComparisonInputs = {
    ..._portfolioInputs,
    OpenKatWizardInputKind.previousAsOf,
  };
  static const _organizationInputs = {
    OpenKatWizardInputKind.organization,
    OpenKatWizardInputKind.currentAsOf,
    OpenKatWizardInputKind.language,
    OpenKatWizardInputKind.title,
  };
  static const _organizationComparisonInputs = {
    ..._organizationInputs,
    OpenKatWizardInputKind.previousAsOf,
  };

  static const scenarioDescriptors = [
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.portfolio,
      family: OpenKatReportFamilyId.organizationsManagement,
      inputs: _portfolioInputs,
      previewKind: OpenKatWizardPreviewKind.summary,
      recommended: true,
      order: 0,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.organizationComparison,
      family: OpenKatReportFamilyId.organizationsManagement,
      inputs: _portfolioInputs,
      previewKind: OpenKatWizardPreviewKind.comparison,
      recommended: true,
      order: 1,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.portfolioTrend,
      family: OpenKatReportFamilyId.organizationsManagement,
      inputs: _portfolioComparisonInputs,
      previewKind: OpenKatWizardPreviewKind.trend,
      recommended: true,
      order: 2,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.findingTypePrevalence,
      family: OpenKatReportFamilyId.organizationsManagement,
      inputs: _portfolioInputs,
      previewKind: OpenKatWizardPreviewKind.findings,
      order: 3,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.severityConcentration,
      family: OpenKatReportFamilyId.organizationsManagement,
      inputs: _portfolioInputs,
      previewKind: OpenKatWizardPreviewKind.findings,
      order: 4,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.controlCoverage,
      family: OpenKatReportFamilyId.organizationsManagement,
      inputs: _portfolioInputs,
      previewKind: OpenKatWizardPreviewKind.controls,
      order: 5,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.recommendations,
      family: OpenKatReportFamilyId.organizationsManagement,
      inputs: _portfolioInputs,
      previewKind: OpenKatWizardPreviewKind.findings,
      order: 6,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.organizationOverview,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationInputs,
      previewKind: OpenKatWizardPreviewKind.summary,
      recommended: true,
      order: 0,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.organizationProgress,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationComparisonInputs,
      previewKind: OpenKatWizardPreviewKind.trend,
      recommended: true,
      order: 1,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.findingLifecycle,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationComparisonInputs,
      previewKind: OpenKatWizardPreviewKind.findings,
      recommended: true,
      order: 2,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.findingAge,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationInputs,
      previewKind: OpenKatWizardPreviewKind.findings,
      order: 3,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.systemHotspots,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationInputs,
      previewKind: OpenKatWizardPreviewKind.systems,
      order: 4,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.systemChanges,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationComparisonInputs,
      previewKind: OpenKatWizardPreviewKind.systems,
      order: 5,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.controlChanges,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationComparisonInputs,
      previewKind: OpenKatWizardPreviewKind.controls,
      order: 6,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.assetInventory,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationInputs,
      previewKind: OpenKatWizardPreviewKind.systems,
      order: 7,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.monitoringCoverage,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationInputs,
      previewKind: OpenKatWizardPreviewKind.monitoring,
      order: 8,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.monitoringChanges,
      family: OpenKatReportFamilyId.organizationProgress,
      inputs: _organizationComparisonInputs,
      previewKind: OpenKatWizardPreviewKind.monitoring,
      order: 9,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.cveExposure,
      family: OpenKatReportFamilyId.cves,
      inputs: {
        OpenKatWizardInputKind.cve,
        OpenKatWizardInputKind.currentAsOf,
        OpenKatWizardInputKind.language,
        OpenKatWizardInputKind.title,
      },
      previewKind: OpenKatWizardPreviewKind.cve,
      recommended: true,
      order: 0,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.cveLandscape,
      family: OpenKatReportFamilyId.cves,
      inputs: _portfolioInputs,
      previewKind: OpenKatWizardPreviewKind.cve,
      recommended: true,
      order: 1,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.cveChanges,
      family: OpenKatReportFamilyId.cves,
      inputs: _portfolioComparisonInputs,
      previewKind: OpenKatWizardPreviewKind.cve,
      order: 2,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.dataQuality,
      family: OpenKatReportFamilyId.dataQuality,
      inputs: {OpenKatWizardInputKind.language, OpenKatWizardInputKind.title},
      previewKind: OpenKatWizardPreviewKind.accountability,
      recommended: true,
      order: 0,
      currentAsOfUsesClock: true,
      maximumSnapshotAge: Duration(days: 30),
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.measurementAccountability,
      family: OpenKatReportFamilyId.dataQuality,
      inputs: _portfolioInputs,
      previewKind: OpenKatWizardPreviewKind.accountability,
      recommended: true,
      order: 1,
    ),
  ];

  @override
  Future<OpenKatWizardScan> prepare(String directory) async {
    final prepared = await importer.prepareDirectory(directory);
    final organizations = prepared.organizations;
    final usable = <OpenKatSnapshot>[];
    final options = <OpenKatWizardOrganizationOption>[];
    for (final organization in organizations) {
      final snapshots =
          organization.snapshots.where((item) => item.usable).toList()
            ..sort((a, b) => a.reportDate.compareTo(b.reportDate));
      if (snapshots.isEmpty) continue;
      usable.addAll(snapshots);
      options.add(
        OpenKatWizardOrganizationOption(
          code: organization.code,
          name: organization.name,
          latestMeasurement: snapshots.last.reportDate,
          measurementCount: snapshots.length,
        ),
      );
    }
    options.sort((a, b) => a.name.compareTo(b.name));
    if (usable.isEmpty) {
      final unavailable = [
        for (final descriptor in scenarioDescriptors)
          OpenKatWizardScenarioAvailability(
            descriptor: descriptor,
            available: false,
            reason: OpenKatWizardUnavailableReason.noUsableMeasurements,
          ),
      ];
      return OpenKatWizardScan(
        directory: directory,
        manifest: prepared.manifest,
        organizations: organizations,
        organizationOptions: options,
        cveOptions: const [],
        scenarios: unavailable,
        preview: OpenKatWizardPreviewFacts(
          organizationCount: 0,
          reportCount: prepared.manifest.recognized.length,
          skippedCount:
              prepared.manifest.entries.length -
              prepared.manifest.recognized.length,
          criticalHighCount: 0,
          systemCount: 0,
          findingsByOrganization: const {},
          measurementDates: const [],
          findingTrend: const [],
        ),
        earliestMeasurement: null,
        latestMeasurement: null,
      );
    }
    usable.sort((a, b) => a.reportDate.compareTo(b.reportDate));
    final latestByOrganization = <String, OpenKatSnapshot>{
      for (final organization in organizations)
        if (organization.snapshots.where((item) => item.usable).isNotEmpty)
          organization.code:
              (organization.snapshots.where((item) => item.usable).toList()
                    ..sort((a, b) => a.reportDate.compareTo(b.reportDate)))
                  .last,
    };
    final cves = _cveOptions(latestByOrganization);
    final scenarios = [
      for (final descriptor in scenarioDescriptors)
        _scenarioAvailability(
          descriptor,
          organizations,
          usable.last.reportDate,
          cves,
        ),
    ];
    final findingsByOrganization = <String, int>{};
    var criticalHigh = 0;
    var systems = 0;
    for (final organization in organizations) {
      final latest = latestByOrganization[organization.code];
      if (latest == null) continue;
      findingsByOrganization[organization.name] = latest.findings.length;
      criticalHigh += latest.findings
          .where(
            (finding) =>
                finding.severity.toLowerCase() == 'critical' ||
                finding.severity.toLowerCase() == 'high',
          )
          .length;
      systems += latest.systems.length;
    }
    final reportCount = prepared.manifest.recognized.length;
    return OpenKatWizardScan(
      directory: directory,
      manifest: prepared.manifest,
      organizations: organizations,
      organizationOptions: options,
      cveOptions: cves,
      scenarios: scenarios,
      preview: OpenKatWizardPreviewFacts(
        organizationCount: options.length,
        reportCount: reportCount,
        skippedCount: prepared.manifest.entries.length - reportCount,
        criticalHighCount: criticalHigh,
        systemCount: systems,
        findingsByOrganization: Map.unmodifiable(findingsByOrganization),
        measurementDates: List.unmodifiable(
          usable.map((snapshot) => snapshot.reportDate).toSet().toList()
            ..sort(),
        ),
        findingTrend: List.unmodifiable(_portfolioFindingTrend(organizations)),
      ),
      earliestMeasurement: usable.first.reportDate,
      latestMeasurement: usable.last.reportDate,
    );
  }

  OpenKatWizardScenarioAvailability _scenarioAvailability(
    OpenKatWizardScenarioDescriptor descriptor,
    List<OpenKatOrganization> organizations,
    DateTime currentAsOf,
    List<OpenKatWizardCveOption> cves,
  ) {
    final engineDescriptor = engine.registry.descriptors.firstWhere(
      (item) => item.id == descriptor.id.reportScenarioId,
    );
    final organizationScope = descriptor.inputs.contains(
      OpenKatWizardInputKind.organization,
    );
    final requiresPrevious = descriptor.inputs.contains(
      OpenKatWizardInputKind.previousAsOf,
    );
    final organization = organizationScope
        ? organizations
                  .where(
                    (item) =>
                        item.snapshots
                            .where((snapshot) => snapshot.usable)
                            .length >=
                        (requiresPrevious ? 2 : 1),
                  )
                  .firstOrNull ??
              organizations
                  .where(
                    (item) => item.snapshots.any((snapshot) => snapshot.usable),
                  )
                  .firstOrNull
        : null;
    final scope = organization == null
        ? const OpenKatReportScope.portfolio()
        : OpenKatReportScope.organization(organization.code);
    final previousAsOf = requiresPrevious
        ? _previousAsOf(organizations, organization, currentAsOf)
        : null;
    final assessment = engine.assessScenarioCapabilities(
      organizations,
      OpenKatReportRequest(
        scenarioId: descriptor.id.reportScenarioId,
        scope: scope,
        currentAsOf: currentAsOf,
        previousAsOf: previousAsOf,
        cveId: cves.isEmpty ? null : cves.first.id,
      ),
    );
    final missing = assessment.missingRequiredCapabilities;
    final inputAvailable =
        !descriptor.inputs.contains(OpenKatWizardInputKind.cve) ||
        cves.isNotEmpty;
    final scopeAvailable = engineDescriptor.scopes.contains(scope.kind);
    final previousAvailable = !requiresPrevious || previousAsOf != null;
    final available =
        assessment.registered &&
        missing.isEmpty &&
        inputAvailable &&
        scopeAvailable &&
        previousAvailable;
    final reason = !scopeAvailable
        ? OpenKatWizardUnavailableReason.unsupportedScope
        : !previousAvailable
        ? OpenKatWizardUnavailableReason.oneMeasurement
        : !inputAvailable
        ? OpenKatWizardUnavailableReason.noReliableCveReferences
        : missing.isEmpty
        ? null
        : _unavailableReason(missing.first);
    return OpenKatWizardScenarioAvailability(
      descriptor: descriptor,
      available: available,
      reason: reason,
    );
  }

  DateTime? _previousAsOf(
    List<OpenKatOrganization> organizations,
    OpenKatOrganization? organization,
    DateTime currentAsOf,
  ) {
    final dates = [
      for (final item in organization == null ? organizations : [organization])
        for (final snapshot in item.snapshots)
          if (snapshot.usable && snapshot.reportDate.isBefore(currentAsOf))
            snapshot.reportDate,
    ]..sort();
    return dates.lastOrNull;
  }

  OpenKatWizardUnavailableReason _unavailableReason(
    OpenKatReportCapability capability,
  ) => switch (capability) {
    OpenKatReportCapability.historicalSnapshots =>
      OpenKatWizardUnavailableReason.oneMeasurement,
    OpenKatReportCapability.reliableCveReferences =>
      OpenKatWizardUnavailableReason.noReliableCveReferences,
    OpenKatReportCapability.reliableMonitoringStatus =>
      OpenKatWizardUnavailableReason.noReliableMonitoringStatus,
    OpenKatReportCapability.reliableOpenedAt =>
      OpenKatWizardUnavailableReason.noReliableOpenedAt,
    OpenKatReportCapability.findingLifecycle =>
      OpenKatWizardUnavailableReason.noStableFindingIdentity,
    OpenKatReportCapability.comparableMeasurementCoverage =>
      OpenKatWizardUnavailableReason.noComparableCoverage,
    OpenKatReportCapability.controlsWithDenominator =>
      OpenKatWizardUnavailableReason.noControlDenominators,
    OpenKatReportCapability.stableAssetIdentity =>
      OpenKatWizardUnavailableReason.noStableAssetIdentity,
    _ => OpenKatWizardUnavailableReason.missingRequiredData,
  };

  /// Bouwt één gebeurtenisindex en past per meting alleen het veranderde
  /// organisatietotaal aan. De eerdere implementatie doorliep op iedere datum
  /// opnieuw alle organisaties en snapshots. Alleen de jongste punten blijven
  /// in geheugen, omdat de compacte wizardgrafiek er niet meer kan tonen.
  List<int> _portfolioFindingTrend(List<OpenKatOrganization> organizations) {
    final events =
        SplayTreeMap<DateTime, List<({String code, int findingCount})>>();
    for (final organization in organizations) {
      for (final snapshot in organization.snapshots) {
        if (!snapshot.usable) continue;
        events.putIfAbsent(snapshot.reportDate, () => []).add((
          code: organization.code,
          findingCount: snapshot.findings.length,
        ));
      }
    }
    final currentByOrganization = <String, int>{};
    final trend = ListQueue<int>();
    var total = 0;
    for (final changes in events.values) {
      for (final change in changes) {
        total -= currentByOrganization[change.code] ?? 0;
        total += change.findingCount;
        currentByOrganization[change.code] = change.findingCount;
      }
      trend.addLast(total);
      if (trend.length > maximumPreviewHistoryPoints) trend.removeFirst();
    }
    return List.unmodifiable(trend);
  }

  List<OpenKatWizardCveOption> _cveOptions(
    Map<String, OpenKatSnapshot> latestByOrganization,
  ) {
    final organizationsByCve = <String, Set<String>>{};
    final systemsByCve = <String, Set<String>>{};
    for (final entry in latestByOrganization.entries) {
      for (final finding in entry.value.findings) {
        for (final cve in finding.cveIds) {
          final normalized = cve.trim().toUpperCase();
          if (normalized.isEmpty) continue;
          organizationsByCve.putIfAbsent(normalized, () => {}).add(entry.key);
          final system = finding.systemId;
          if (system != null && system.isNotEmpty) {
            systemsByCve
                .putIfAbsent(normalized, () => {})
                .add('${entry.key}:$system');
          }
        }
      }
    }
    final result = [
      for (final entry in organizationsByCve.entries)
        OpenKatWizardCveOption(
          id: entry.key,
          organizationCount: entry.value.length,
          systemCount: systemsByCve[entry.key]?.length ?? 0,
        ),
    ];
    result.sort((a, b) => a.id.compareTo(b.id));
    return List.unmodifiable(result);
  }

  @override
  OpenKatReportResult preview(
    OpenKatWizardScan scan,
    OpenKatWizardRecipe recipe,
  ) =>
      engine.generate(_selectedOrganizations(scan, recipe), recipe.toRequest());

  List<OpenKatOrganization> _selectedOrganizations(
    OpenKatWizardScan scan,
    OpenKatWizardRecipe recipe,
  ) {
    if (recipe.organizationCodes.isEmpty) return scan.organizations;
    return scan.organizations
        .where(
          (organization) =>
              recipe.organizationCodes.contains(organization.code),
        )
        .toList(growable: false);
  }

  @override
  OpenKatWizardBuildResult build(
    OpenKatWizardScan scan,
    OpenKatWizardRecipe recipe, {
    Deck? existing,
  }) {
    final generated = preview(scan, recipe);
    final fresh = generated.deck;
    final report = existing == null || fresh == null
        ? generated
        : OpenKatReportResult(
            deck: deckGenerator.updateGenerated(existing, fresh),
            plan: generated.plan,
            scenarioId: generated.scenarioId,
            scope: generated.scope,
            measurements: generated.measurements,
            diagnostics: generated.diagnostics,
            missingCapabilities: generated.missingCapabilities,
            sourceTraces: generated.sourceTraces,
          );
    return OpenKatWizardBuildResult(
      report: report,
      recipe: recipe,
      scan: scan,
      updated: existing != null && report.generated,
      usedReports: report.sourceTraces
          .map((trace) => trace.sourceHash)
          .toSet()
          .length,
      skippedReports: scan.preview.skippedCount,
    );
  }
}
