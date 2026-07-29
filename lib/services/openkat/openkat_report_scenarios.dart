import '../../models/openkat/openkat_reporting_models.dart';
import 'openkat_report_facts.dart';

class OpenKatScenarioDescriptor {
  final String id;
  final Set<OpenKatReportScopeKind> scopes;
  final Set<OpenKatReportCapability> requiredCapabilities;
  final Set<OpenKatReportCapability> optionalCapabilities;
  final bool requiresPreviousAsOf;
  final bool requiresCveId;
  final List<OpenKatReportBlock> blocks;

  const OpenKatScenarioDescriptor({
    required this.id,
    required this.scopes,
    this.requiredCapabilities = const {},
    this.optionalCapabilities = const {},
    this.requiresPreviousAsOf = false,
    this.requiresCveId = false,
    this.blocks = const [],
  });
}

abstract interface class OpenKatReportScenario {
  OpenKatScenarioDescriptor get descriptor;

  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  );
}

/// Vast rapportrecept. Alleen werkelijk feitafhankelijke compositie hoort in
/// een aparte scenarioklasse; de standaardcatalogus bestaat uit deze recepten.
class OpenKatDeclarativeScenario implements OpenKatReportScenario {
  @override
  final OpenKatScenarioDescriptor descriptor;

  const OpenKatDeclarativeScenario(this.descriptor);

  @override
  OpenKatReportPlan compose(
    OpenKatReportFacts facts,
    OpenKatReportRequest request,
  ) => OpenKatReportPlan(scenarioId: descriptor.id, blocks: descriptor.blocks);
}

abstract final class OpenKatScenarioCatalog {
  static const portfolioScopes = {
    OpenKatReportScopeKind.portfolio,
    OpenKatReportScopeKind.organization,
  };

  static const management = OpenKatScenarioDescriptor(
    id: 'management-overview',
    scopes: portfolioScopes,
    optionalCapabilities: {
      OpenKatReportCapability.multipleOrganizations,
      OpenKatReportCapability.historicalSnapshots,
      OpenKatReportCapability.comparableMeasurementCoverage,
      OpenKatReportCapability.controlsWithDenominator,
      OpenKatReportCapability.reliableOpenedAt,
      OpenKatReportCapability.sufficientDataFreshness,
    },
    blocks: [
      OpenKatReportBlock(
        id: 'organization-comparison',
        kind: OpenKatReportBlockKind.organizationComparison,
      ),
      OpenKatReportBlock(
        id: 'portfolio-summary',
        kind: OpenKatReportBlockKind.portfolioSummary,
      ),
      OpenKatReportBlock(
        id: 'portfolio-trend',
        kind: OpenKatReportBlockKind.portfolioTrend,
      ),
      OpenKatReportBlock(
        id: 'severity-concentration',
        kind: OpenKatReportBlockKind.severityConcentration,
      ),
      OpenKatReportBlock(
        id: 'finding-type-prevalence',
        kind: OpenKatReportBlockKind.findingTypePrevalence,
      ),
      OpenKatReportBlock(
        id: 'recommendations',
        kind: OpenKatReportBlockKind.recommendations,
      ),
      OpenKatReportBlock(
        id: 'finding-age',
        kind: OpenKatReportBlockKind.findingAge,
      ),
      OpenKatReportBlock(
        id: 'control-coverage',
        kind: OpenKatReportBlockKind.controlCoverage,
      ),
      OpenKatReportBlock(
        id: 'system-hotspots',
        kind: OpenKatReportBlockKind.systemHotspots,
      ),
      OpenKatReportBlock(
        id: 'measurement-availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );

  static const weeklyComparison = OpenKatScenarioDescriptor(
    id: 'weekly-comparison',
    scopes: portfolioScopes,
    requiredCapabilities: {OpenKatReportCapability.historicalSnapshots},
    optionalCapabilities: {
      OpenKatReportCapability.comparableMeasurementCoverage,
      OpenKatReportCapability.findingLifecycle,
      OpenKatReportCapability.controlsWithDenominator,
      OpenKatReportCapability.stableAssetIdentity,
      OpenKatReportCapability.sufficientDataFreshness,
    },
    requiresPreviousAsOf: true,
    blocks: [
      OpenKatReportBlock(
        id: 'portfolio-summary',
        kind: OpenKatReportBlockKind.portfolioSummary,
      ),
      OpenKatReportBlock(
        id: 'portfolio-trend',
        kind: OpenKatReportBlockKind.portfolioTrend,
      ),
      OpenKatReportBlock(
        id: 'finding-lifecycle',
        kind: OpenKatReportBlockKind.findingLifecycle,
      ),
      OpenKatReportBlock(
        id: 'measurement-availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );

  static const organizationOverview = OpenKatScenarioDescriptor(
    id: 'organization-overview',
    scopes: {OpenKatReportScopeKind.organization},
    optionalCapabilities: {
      OpenKatReportCapability.controlsWithDenominator,
      OpenKatReportCapability.sufficientDataFreshness,
    },
    blocks: [
      OpenKatReportBlock(
        id: 'organization-overview',
        kind: OpenKatReportBlockKind.organizationOverview,
      ),
      OpenKatReportBlock(
        id: 'finding-type-prevalence',
        kind: OpenKatReportBlockKind.findingTypePrevalence,
      ),
      OpenKatReportBlock(
        id: 'system-hotspots',
        kind: OpenKatReportBlockKind.systemHotspots,
      ),
      OpenKatReportBlock(
        id: 'measurement-availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );

  static const cveExposure = OpenKatScenarioDescriptor(
    id: 'cve-exposure',
    scopes: portfolioScopes,
    requiredCapabilities: {OpenKatReportCapability.reliableCveReferences},
    requiresCveId: true,
    blocks: [
      OpenKatReportBlock(
        id: 'cve-exposure',
        kind: OpenKatReportBlockKind.cveExposure,
      ),
      OpenKatReportBlock(
        id: 'measurement-availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );

  static const monitoringChanges = OpenKatScenarioDescriptor(
    id: 'monitoring-changes',
    scopes: portfolioScopes,
    requiredCapabilities: {
      OpenKatReportCapability.historicalSnapshots,
      OpenKatReportCapability.reliableMonitoringStatus,
      OpenKatReportCapability.stableAssetIdentity,
    },
    requiresPreviousAsOf: true,
    blocks: [
      OpenKatReportBlock(
        id: 'monitoring-changes',
        kind: OpenKatReportBlockKind.monitoringChanges,
      ),
      OpenKatReportBlock(
        id: 'measurement-availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );

  static const dataQuality = OpenKatScenarioDescriptor(
    id: 'data-quality',
    scopes: portfolioScopes,
    optionalCapabilities: {
      OpenKatReportCapability.historicalSnapshots,
      OpenKatReportCapability.sufficientDataFreshness,
    },
    blocks: [
      OpenKatReportBlock(
        id: 'measurement-availability',
        kind: OpenKatReportBlockKind.measurementAvailability,
      ),
    ],
  );

  static const recipes = <OpenKatScenarioDescriptor>[
    management,
    weeklyComparison,
    organizationOverview,
    cveExposure,
    monitoringChanges,
    dataQuality,
    OpenKatScenarioDescriptor(
      id: 'organization-comparison',
      scopes: {OpenKatReportScopeKind.portfolio},
      requiredCapabilities: {OpenKatReportCapability.multipleOrganizations},
      blocks: [
        OpenKatReportBlock(
          id: 'organization-comparison',
          kind: OpenKatReportBlockKind.organizationComparison,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'portfolio-trend',
      scopes: {OpenKatReportScopeKind.portfolio},
      requiredCapabilities: {OpenKatReportCapability.historicalSnapshots},
      optionalCapabilities: {
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      requiresPreviousAsOf: true,
      blocks: [
        OpenKatReportBlock(
          id: 'portfolio-trend',
          kind: OpenKatReportBlockKind.portfolioTrend,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'finding-type-prevalence',
      scopes: {OpenKatReportScopeKind.portfolio},
      optionalCapabilities: {
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      blocks: [
        OpenKatReportBlock(
          id: 'finding-type-prevalence',
          kind: OpenKatReportBlockKind.findingTypePrevalence,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'critical-high-concentration',
      scopes: {OpenKatReportScopeKind.portfolio},
      blocks: [
        OpenKatReportBlock(
          id: 'severity-concentration',
          kind: OpenKatReportBlockKind.severityConcentration,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'cve-landscape',
      scopes: {OpenKatReportScopeKind.portfolio},
      requiredCapabilities: {OpenKatReportCapability.reliableCveReferences},
      blocks: [
        OpenKatReportBlock(
          id: 'cve-landscape',
          kind: OpenKatReportBlockKind.cveLandscape,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'cve-changes',
      scopes: {OpenKatReportScopeKind.portfolio},
      requiredCapabilities: {
        OpenKatReportCapability.reliableCveReferences,
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      requiresPreviousAsOf: true,
      blocks: [
        OpenKatReportBlock(
          id: 'cve-changes',
          kind: OpenKatReportBlockKind.cveChanges,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'finding-lifecycle',
      scopes: portfolioScopes,
      requiredCapabilities: {
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.findingLifecycle,
      },
      optionalCapabilities: {
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      requiresPreviousAsOf: true,
      blocks: [
        OpenKatReportBlock(
          id: 'finding-lifecycle',
          kind: OpenKatReportBlockKind.findingLifecycle,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'finding-age',
      scopes: portfolioScopes,
      requiredCapabilities: {OpenKatReportCapability.reliableOpenedAt},
      blocks: [
        OpenKatReportBlock(
          id: 'finding-age',
          kind: OpenKatReportBlockKind.findingAge,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'system-hotspots',
      scopes: portfolioScopes,
      blocks: [
        OpenKatReportBlock(
          id: 'system-hotspots',
          kind: OpenKatReportBlockKind.systemHotspots,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'system-changes',
      scopes: portfolioScopes,
      requiredCapabilities: {
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.stableAssetIdentity,
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      requiresPreviousAsOf: true,
      blocks: [
        OpenKatReportBlock(
          id: 'system-changes',
          kind: OpenKatReportBlockKind.systemChanges,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'control-coverage',
      scopes: portfolioScopes,
      optionalCapabilities: {OpenKatReportCapability.controlsWithDenominator},
      blocks: [
        OpenKatReportBlock(
          id: 'control-coverage',
          kind: OpenKatReportBlockKind.controlCoverage,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'control-changes',
      scopes: portfolioScopes,
      requiredCapabilities: {
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.controlsWithDenominator,
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      requiresPreviousAsOf: true,
      blocks: [
        OpenKatReportBlock(
          id: 'control-changes',
          kind: OpenKatReportBlockKind.controlChanges,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'recommendations-overview',
      scopes: portfolioScopes,
      blocks: [
        OpenKatReportBlock(
          id: 'recommendations',
          kind: OpenKatReportBlockKind.recommendations,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'asset-inventory',
      scopes: portfolioScopes,
      blocks: [
        OpenKatReportBlock(
          id: 'asset-inventory',
          kind: OpenKatReportBlockKind.assetInventory,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'monitoring-coverage',
      scopes: portfolioScopes,
      requiredCapabilities: {OpenKatReportCapability.reliableMonitoringStatus},
      blocks: [
        OpenKatReportBlock(
          id: 'monitoring-coverage',
          kind: OpenKatReportBlockKind.monitoringCoverage,
        ),
        OpenKatReportBlock(
          id: 'measurement-availability',
          kind: OpenKatReportBlockKind.measurementAvailability,
        ),
      ],
    ),
    OpenKatScenarioDescriptor(
      id: 'measurement-accountability',
      scopes: portfolioScopes,
      blocks: [
        OpenKatReportBlock(
          id: 'measurement-accountability',
          kind: OpenKatReportBlockKind.measurementAccountability,
        ),
      ],
    ),
  ];
}

class OpenKatManagementScenario extends OpenKatDeclarativeScenario {
  const OpenKatManagementScenario() : super(OpenKatScenarioCatalog.management);
}

class OpenKatWeeklyComparisonScenario extends OpenKatDeclarativeScenario {
  const OpenKatWeeklyComparisonScenario()
    : super(OpenKatScenarioCatalog.weeklyComparison);
}

class OpenKatOrganizationScenario extends OpenKatDeclarativeScenario {
  const OpenKatOrganizationScenario()
    : super(OpenKatScenarioCatalog.organizationOverview);
}

class OpenKatCveExposureScenario extends OpenKatDeclarativeScenario {
  const OpenKatCveExposureScenario()
    : super(OpenKatScenarioCatalog.cveExposure);
}

class OpenKatMonitoringChangesScenario extends OpenKatDeclarativeScenario {
  const OpenKatMonitoringChangesScenario()
    : super(OpenKatScenarioCatalog.monitoringChanges);
}

class OpenKatDataQualityScenario extends OpenKatDeclarativeScenario {
  const OpenKatDataQualityScenario()
    : super(OpenKatScenarioCatalog.dataQuality);
}

/// Centraal, injecteerbaar register. Duplicaten zijn een programmeerfout.
class OpenKatReportScenarioRegistry {
  final Map<String, OpenKatReportScenario> _byId;

  OpenKatReportScenarioRegistry({List<OpenKatReportScenario>? scenarios})
    : _byId = _index(
        scenarios ??
            [
              for (final descriptor in OpenKatScenarioCatalog.recipes)
                OpenKatDeclarativeScenario(descriptor),
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
