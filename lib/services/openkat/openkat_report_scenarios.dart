import '../../models/openkat/openkat_reporting_models.dart';
import 'openkat_report_facts.dart';

class OpenKatScenarioDescriptor {
  final String id;
  final Set<OpenKatReportScopeKind> scopes;
  final Set<OpenKatReportCapability> requiredCapabilities;
  final Set<OpenKatReportCapability> optionalCapabilities;
  final bool requiresPreviousAsOf;
  final bool requiresCveId;

  const OpenKatScenarioDescriptor({
    required this.id,
    required this.scopes,
    this.requiredCapabilities = const {},
    this.optionalCapabilities = const {},
    this.requiresPreviousAsOf = false,
    this.requiresCveId = false,
  });
}

abstract interface class OpenKatReportScenario {
  OpenKatScenarioDescriptor get descriptor;

  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  );
}

class OpenKatManagementScenario implements OpenKatReportScenario {
  const OpenKatManagementScenario();

  @override
  OpenKatScenarioDescriptor get descriptor => const OpenKatScenarioDescriptor(
    id: 'management-overview',
    scopes: {
      OpenKatReportScopeKind.portfolio,
      OpenKatReportScopeKind.organization,
    },
    optionalCapabilities: {
      OpenKatReportCapability.multipleOrganizations,
      OpenKatReportCapability.historicalSnapshots,
      OpenKatReportCapability.comparableMeasurementCoverage,
      OpenKatReportCapability.controlsWithDenominator,
      OpenKatReportCapability.sufficientDataFreshness,
    },
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
      OpenKatReportBlock(
        id: 'availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );
}

class OpenKatWeeklyComparisonScenario implements OpenKatReportScenario {
  const OpenKatWeeklyComparisonScenario();

  @override
  OpenKatScenarioDescriptor get descriptor => const OpenKatScenarioDescriptor(
    id: 'weekly-comparison',
    scopes: {
      OpenKatReportScopeKind.portfolio,
      OpenKatReportScopeKind.organization,
    },
    requiredCapabilities: {OpenKatReportCapability.historicalSnapshots},
    optionalCapabilities: {
      OpenKatReportCapability.comparableMeasurementCoverage,
      OpenKatReportCapability.findingLifecycle,
      OpenKatReportCapability.controlsWithDenominator,
      OpenKatReportCapability.sufficientDataFreshness,
    },
    requiresPreviousAsOf: true,
  );

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => const OpenKatReportPlan(
    scenarioId: 'weekly-comparison',
    blocks: [
      OpenKatReportBlock(
        id: 'management',
        kind: OpenKatReportBlockKind.managementOverview,
      ),
      OpenKatReportBlock(
        id: 'availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
      OpenKatReportBlock(
        id: 'lifecycle',
        kind: OpenKatReportBlockKind.findingLifecycle,
      ),
    ],
  );
}

class OpenKatOrganizationScenario implements OpenKatReportScenario {
  const OpenKatOrganizationScenario();

  @override
  OpenKatScenarioDescriptor get descriptor => const OpenKatScenarioDescriptor(
    id: 'organization-overview',
    scopes: {OpenKatReportScopeKind.organization},
    optionalCapabilities: {
      OpenKatReportCapability.historicalSnapshots,
      OpenKatReportCapability.comparableMeasurementCoverage,
      OpenKatReportCapability.controlsWithDenominator,
      OpenKatReportCapability.sufficientDataFreshness,
    },
  );

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => const OpenKatReportPlan(
    scenarioId: 'organization-overview',
    blocks: [
      OpenKatReportBlock(
        id: 'management',
        kind: OpenKatReportBlockKind.managementOverview,
      ),
      OpenKatReportBlock(
        id: 'availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );
}

class OpenKatCveExposureScenario implements OpenKatReportScenario {
  const OpenKatCveExposureScenario();

  @override
  OpenKatScenarioDescriptor get descriptor => const OpenKatScenarioDescriptor(
    id: 'cve-exposure',
    scopes: {
      OpenKatReportScopeKind.portfolio,
      OpenKatReportScopeKind.organization,
    },
    requiredCapabilities: {OpenKatReportCapability.reliableCveReferences},
    requiresCveId: true,
  );

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => const OpenKatReportPlan(
    scenarioId: 'cve-exposure',
    blocks: [
      OpenKatReportBlock(
        id: 'cve-exposure',
        kind: OpenKatReportBlockKind.cveExposure,
      ),
      OpenKatReportBlock(
        id: 'availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );
}

class OpenKatMonitoringChangesScenario implements OpenKatReportScenario {
  const OpenKatMonitoringChangesScenario();

  @override
  OpenKatScenarioDescriptor get descriptor => const OpenKatScenarioDescriptor(
    id: 'monitoring-changes',
    scopes: {
      OpenKatReportScopeKind.portfolio,
      OpenKatReportScopeKind.organization,
    },
    requiredCapabilities: {
      OpenKatReportCapability.historicalSnapshots,
      OpenKatReportCapability.reliableMonitoringStatus,
      OpenKatReportCapability.stableAssetIdentity,
    },
    requiresPreviousAsOf: true,
  );

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => const OpenKatReportPlan(
    scenarioId: 'monitoring-changes',
    blocks: [
      OpenKatReportBlock(
        id: 'monitoring-changes',
        kind: OpenKatReportBlockKind.monitoringChanges,
      ),
      OpenKatReportBlock(
        id: 'availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );
}

/// Feitelijke dekking en actualiteit, zonder managementscore of risicomodel.
class OpenKatDataQualityScenario implements OpenKatReportScenario {
  const OpenKatDataQualityScenario();

  @override
  OpenKatScenarioDescriptor get descriptor => const OpenKatScenarioDescriptor(
    id: 'data-quality',
    scopes: {
      OpenKatReportScopeKind.portfolio,
      OpenKatReportScopeKind.organization,
    },
    optionalCapabilities: {
      OpenKatReportCapability.historicalSnapshots,
      OpenKatReportCapability.sufficientDataFreshness,
    },
  );

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => const OpenKatReportPlan(
    scenarioId: 'data-quality',
    blocks: [
      OpenKatReportBlock(
        id: 'availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );
}

/// Centraal, injecteerbaar register. Duplicaten zijn een programmeerfout.
class OpenKatReportScenarioRegistry {
  final Map<String, OpenKatReportScenario> _byId;

  OpenKatReportScenarioRegistry({List<OpenKatReportScenario>? scenarios})
    : _byId = _index(
        scenarios ??
            const [
              OpenKatManagementScenario(),
              OpenKatWeeklyComparisonScenario(),
              OpenKatOrganizationScenario(),
              OpenKatCveExposureScenario(),
              OpenKatMonitoringChangesScenario(),
              OpenKatDataQualityScenario(),
            ],
      );

  static Map<String, OpenKatReportScenario> _index(
    List<OpenKatReportScenario> scenarios,
  ) {
    final byId = <String, OpenKatReportScenario>{};
    for (final scenario in scenarios) {
      final id = scenario.descriptor.id;
      if (byId.containsKey(id)) {
        throw ArgumentError.value(id, 'scenarios', 'dubbel scenario-ID');
      }
      byId[id] = scenario;
    }
    return Map.unmodifiable(byId);
  }

  OpenKatReportScenario? find(String id) => _byId[id];

  List<OpenKatScenarioDescriptor> get descriptors => _byId.values
      .map((scenario) => scenario.descriptor)
      .toList(growable: false);
}
