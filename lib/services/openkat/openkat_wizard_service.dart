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

  static const scenarioDescriptors = [
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.portfolio,
      inputs: {
        OpenKatWizardInputKind.period,
        OpenKatWizardInputKind.organizations,
        OpenKatWizardInputKind.language,
        OpenKatWizardInputKind.title,
      },
      recommended: true,
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.organizationProgress,
      inputs: {
        OpenKatWizardInputKind.organization,
        OpenKatWizardInputKind.period,
        OpenKatWizardInputKind.language,
        OpenKatWizardInputKind.title,
      },
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.cveExposure,
      inputs: {
        OpenKatWizardInputKind.cve,
        OpenKatWizardInputKind.period,
        OpenKatWizardInputKind.language,
        OpenKatWizardInputKind.title,
      },
    ),
    OpenKatWizardScenarioDescriptor(
      id: OpenKatWizardScenarioId.dataQuality,
      inputs: {OpenKatWizardInputKind.language, OpenKatWizardInputKind.title},
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
    final assessment = engine.assessScenarioCapabilities(
      organizations,
      OpenKatReportRequest(
        scenarioId: descriptor.id.reportScenarioId,
        scope: const OpenKatReportScope.portfolio(),
        currentAsOf: currentAsOf,
        cveId: cves.isEmpty ? null : cves.first.id,
      ),
    );
    final missing = assessment.missingRequiredCapabilities;
    final inputAvailable =
        descriptor.id != OpenKatWizardScenarioId.cveExposure || cves.isNotEmpty;
    final available =
        assessment.registered && missing.isEmpty && inputAvailable;
    final reason = switch (descriptor.id) {
      OpenKatWizardScenarioId.organizationProgress
          when missing.contains(OpenKatReportCapability.historicalSnapshots) =>
        OpenKatWizardUnavailableReason.oneMeasurement,
      OpenKatWizardScenarioId.cveExposure
          when cves.isEmpty ||
              missing.contains(OpenKatReportCapability.reliableCveReferences) =>
        OpenKatWizardUnavailableReason.noReliableCveReferences,
      _ => null,
    };
    return OpenKatWizardScenarioAvailability(
      descriptor: descriptor,
      available: available,
      reason: reason,
    );
  }

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
