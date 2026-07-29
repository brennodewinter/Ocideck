import '../deck.dart';
import 'openkat_models.dart';

/// Bereik van een rapportageverzoek.
enum OpenKatReportScopeKind { portfolio, organization }

/// Getypepte rapportagescope; een organisatiescope kan niet zonder code bestaan.
class OpenKatReportScope {
  final OpenKatReportScopeKind kind;
  final String? organizationCode;

  const OpenKatReportScope._(this.kind, this.organizationCode);

  const OpenKatReportScope.portfolio()
    : this._(OpenKatReportScopeKind.portfolio, null);

  factory OpenKatReportScope.organization(String organizationCode) {
    if (organizationCode.trim().isEmpty) {
      throw ArgumentError.value(
        organizationCode,
        'organizationCode',
        'moet een niet-lege organisatiecode zijn',
      );
    }
    return OpenKatReportScope._(
      OpenKatReportScopeKind.organization,
      organizationCode,
    );
  }
}

/// Talen die de headless composer zelf volledig ondersteunt.
enum OpenKatReportLanguage {
  dutch('nl'),
  english('en');

  final String code;
  const OpenKatReportLanguage(this.code);
}

/// Expliciete beleidskeuzes die feitenselectie of presentatie begrenzen.
class OpenKatReportPolicy {
  static const int maximumTableRowLimit = 1000;
  static const int defaultHistoricalFindingWorkLimit = 250000;
  static const int maximumHistoricalFindingWorkLimit = 1000000;

  /// Alleen gezet wanneer de aanroeper zelf een versheidsgrens koos.
  final Duration? maximumSnapshotAge;

  /// Bovengrens voor tabelblokken die geen eigen OciDeck-weergavelimiet hebben.
  final int tableRowLimit;

  /// Maximaal aantal historische findings dat lifecycle mag inspecteren.
  final int historicalFindingWorkLimit;

  const OpenKatReportPolicy({
    this.maximumSnapshotAge,
    this.tableRowLimit = maximumTableRowLimit,
    this.historicalFindingWorkLimit = defaultHistoricalFindingWorkLimit,
  });
}

/// Volledig getypept verzoek aan de rapportagemotor.
class OpenKatReportRequest {
  final String scenarioId;
  final OpenKatReportScope scope;
  final DateTime currentAsOf;
  final DateTime? previousAsOf;
  final String? cveId;
  final OpenKatReportLanguage language;
  final String? title;
  final OpenKatReportPolicy policy;

  const OpenKatReportRequest({
    required this.scenarioId,
    required this.scope,
    required this.currentAsOf,
    this.previousAsOf,
    this.cveId,
    this.language = OpenKatReportLanguage.dutch,
    this.title,
    this.policy = const OpenKatReportPolicy(),
  });
}

/// Bronmogelijkheden waarop scenario's expliciet kunnen steunen.
enum OpenKatReportCapability {
  multipleOrganizations,
  historicalSnapshots,
  reliableCveReferences,
  reliableMonitoringStatus,
  reliableOpenedAt,
  stableAssetIdentity,
  comparableMeasurementCoverage,
  findingLifecycle,
  controlsWithDenominator,
  comparableControlsWithDenominator,
  sufficientDataFreshness,
}

enum OpenKatCapabilityStatus { available, unavailable, notAssessed }

class OpenKatCapabilityAssessment {
  final OpenKatReportCapability capability;
  final OpenKatCapabilityStatus status;
  final Map<String, String> arguments;

  const OpenKatCapabilityAssessment({
    required this.capability,
    required this.status,
    this.arguments = const {},
  });

  bool get isAvailable => status == OpenKatCapabilityStatus.available;
}

enum OpenKatReportDiagnosticSeverity { warning, error }

/// Stabiele codes; vrije presentatietekst hoort niet in het interne contract.
enum OpenKatReportDiagnosticCode {
  unknownScenario,
  unsupportedScope,
  organizationNotFound,
  currentSnapshotMissing,
  previousSnapshotMissing,
  invalidSnapshotChronology,
  invalidCveId,
  missingCapability,
  invalidReportPlan,
  invalidPolicy,
  resourceLimitExceeded,
  snapshotTooOld,
  incompletePortfolio,
  incomparableMeasurementCoverage,
}

class OpenKatReportDiagnostic {
  final OpenKatReportDiagnosticCode code;
  final OpenKatReportDiagnosticSeverity severity;
  final Map<String, String> arguments;

  const OpenKatReportDiagnostic({
    required this.code,
    required this.severity,
    this.arguments = const {},
  });
}

enum OpenKatMeasurementRole { current, previous, historical }

/// Werkelijk gebruikt meetmoment, inclusief ouderdom op de gevraagde peildatum.
class OpenKatMeasurementUsage {
  final String organizationCode;
  final OpenKatMeasurementRole role;
  final DateTime requestedAsOf;
  final DateTime? measuredAt;
  final Duration? age;
  final bool missing;

  const OpenKatMeasurementUsage({
    required this.organizationCode,
    required this.role,
    required this.requestedAsOf,
    required this.measuredAt,
    required this.age,
    required this.missing,
  });
}

/// Herleidbaarheid van rapportfeit naar de werkelijk gekozen bron.
class OpenKatSourceTrace {
  final String organizationCode;
  final OpenKatMeasurementRole role;
  final DateTime reportDate;
  final String sourceFile;
  final String sourceHash;
  final String? schema;

  const OpenKatSourceTrace({
    required this.organizationCode,
    required this.role,
    required this.reportDate,
    required this.sourceFile,
    required this.sourceHash,
    this.schema,
  });
}

/// De twee werkelijk geselecteerde momentopnames voor één organisatie.
class OpenKatReportSelection {
  final OpenKatOrganization organization;
  final DateTime currentAsOf;
  final DateTime? previousAsOf;
  final OpenKatSnapshot? current;
  final OpenKatSnapshot? previous;

  const OpenKatReportSelection({
    required this.organization,
    required this.currentAsOf,
    required this.previousAsOf,
    required this.current,
    required this.previous,
  });

  Duration? get currentAge =>
      current == null ? null : currentAsOf.difference(current!.reportDate);

  Duration? get previousAge => previous == null || previousAsOf == null
      ? null
      : previousAsOf!.difference(previous!.reportDate);

  bool get currentMissing => current == null;
  bool get previousMissing => previousAsOf != null && previous == null;
}

enum OpenKatFindingObservation { newlyObserved, noLongerObserved, reobserved }

/// Feitelijke verandering van één bevinding tussen twee gekozen metingen.
class OpenKatFindingLifecycleItem {
  final String organizationCode;
  final OpenKatFinding finding;
  final OpenKatFindingObservation observation;

  /// Waar wanneer de twee exports aantoonbaar dezelfde meetdekking hebben.
  final bool comparableCoverage;

  const OpenKatFindingLifecycleItem({
    required this.organizationCode,
    required this.finding,
    required this.observation,
    required this.comparableCoverage,
  });
}

class OpenKatControlChange {
  final String organizationCode;
  final String controlId;
  final int previousCompliant;
  final int previousTotal;
  final int currentCompliant;
  final int currentTotal;
  final double previousRatio;
  final double currentRatio;

  const OpenKatControlChange({
    required this.organizationCode,
    required this.controlId,
    required this.previousCompliant,
    required this.previousTotal,
    required this.currentCompliant,
    required this.currentTotal,
    required this.previousRatio,
    required this.currentRatio,
  });

  double get delta => currentRatio - previousRatio;
}

class OpenKatOrganizationRanking {
  final String code;
  final String name;
  final DateTime measuredAt;
  final int critical;
  final int high;
  final int affectedSystems;
  final int totalFindings;

  const OpenKatOrganizationRanking({
    required this.code,
    required this.name,
    required this.measuredAt,
    required this.critical,
    required this.high,
    required this.affectedSystems,
    required this.totalFindings,
  });
}

class OpenKatPortfolioHistoryPoint {
  final DateTime date;
  final Map<String, int> severityCounts;
  final int contributingOrganizations;
  final int carriedForwardOrganizations;

  const OpenKatPortfolioHistoryPoint({
    required this.date,
    required this.severityCounts,
    required this.contributingOrganizations,
    required this.carriedForwardOrganizations,
  });
}

class OpenKatSystemHotspot {
  final String organizationCode;
  final String systemId;
  final String? hostname;
  final String? ip;
  final Map<String, int> severityCounts;
  final bool unknownSystem;

  const OpenKatSystemHotspot({
    required this.organizationCode,
    required this.systemId,
    required this.hostname,
    required this.ip,
    required this.severityCounts,
    required this.unknownSystem,
  });

  int get total => severityCounts.values.fold(0, (sum, count) => sum + count);
}

enum OpenKatSystemChangeKind { moreObserved, fewerObserved, mixed }

class OpenKatSystemChangeItem {
  final String organizationCode;
  final String systemId;
  final OpenKatSystemChangeKind kind;
  final Map<String, int> severityDeltas;

  const OpenKatSystemChangeItem({
    required this.organizationCode,
    required this.systemId,
    required this.kind,
    required this.severityDeltas,
  });
}

class OpenKatCveLandscapeItem {
  final String cveId;
  final int organizationCount;
  final int systemCount;
  final int observationCount;
  final Map<String, int> severityCounts;

  const OpenKatCveLandscapeItem({
    required this.cveId,
    required this.organizationCount,
    required this.systemCount,
    required this.observationCount,
    required this.severityCounts,
  });
}

enum OpenKatCveObservation { newlyObserved, reobserved, noLongerObserved }

class OpenKatCveChangeItem {
  final String cveId;
  final OpenKatCveObservation observation;
  final Set<String> organizationCodes;
  final Set<String> systemIds;

  const OpenKatCveChangeItem({
    required this.cveId,
    required this.observation,
    required this.organizationCodes,
    required this.systemIds,
  });
}

class OpenKatRecommendationItem {
  final String findingTypeId;
  final String findingTypeName;
  final String recommendation;
  final int organizationCount;
  final int systemCount;
  final String highestSeverity;

  const OpenKatRecommendationItem({
    required this.findingTypeId,
    required this.findingTypeName,
    required this.recommendation,
    required this.organizationCount,
    required this.systemCount,
    required this.highestSeverity,
  });
}

class OpenKatCveExposure {
  final String organizationCode;
  final OpenKatFinding finding;

  const OpenKatCveExposure({
    required this.organizationCode,
    required this.finding,
  });
}

enum OpenKatMonitoringMutationKind { added, removed }

class OpenKatMonitoringMutation {
  final String organizationCode;
  final OpenKatSystem system;
  final OpenKatMonitoringMutationKind kind;

  const OpenKatMonitoringMutation({
    required this.organizationCode,
    required this.system,
    required this.kind,
  });
}

/// Kleine, herbruikbare bouwstenen waaruit scenario's een plan samenstellen.
enum OpenKatReportBlockKind {
  managementOverview,
  portfolioSummary,
  organizationComparison,
  severityConcentration,
  portfolioTrend,
  findingTypePrevalence,
  measurementAvailability,
  measurementAccountability,
  findingLifecycle,
  findingAge,
  systemHotspots,
  systemChanges,
  cveExposure,
  cveLandscape,
  cveChanges,
  controlCoverage,
  controlChanges,
  recommendations,
  assetInventory,
  monitoringCoverage,
  monitoringChanges,
  organizationOverview,
}

/// Voorwaarden die uit de betekenis van een blok volgen, onafhankelijk van
/// wat een (eventueel geïnjecteerd) scenario erover declareert.
class OpenKatReportBlockPreconditions {
  final Set<OpenKatReportCapability> capabilities;
  final Set<OpenKatReportScopeKind> scopes;
  final bool requiresPreviousAsOf;
  final bool requiresCveId;
  final bool omitWhenUnavailable;
  final int constructionBudget;
  final int viewLimit;

  const OpenKatReportBlockPreconditions({
    this.capabilities = const {},
    this.scopes = const {
      OpenKatReportScopeKind.portfolio,
      OpenKatReportScopeKind.organization,
    },
    this.requiresPreviousAsOf = false,
    this.requiresCveId = false,
    this.omitWhenUnavailable = false,
    this.constructionBudget = OpenKatReportPolicy.maximumTableRowLimit,
    this.viewLimit = 7,
  });
}

/// Intrinsieke blokcontracten. Een geïnjecteerd scenario kan deze voorwaarden
/// niet verzwakken, omdat de motor uitsluitend dit register raadpleegt.
abstract final class OpenKatReportBlockRegistry {
  static const Map<OpenKatReportBlockKind, OpenKatReportBlockPreconditions>
  definitions = {
    OpenKatReportBlockKind.managementOverview:
        OpenKatReportBlockPreconditions(),
    OpenKatReportBlockKind.portfolioSummary: OpenKatReportBlockPreconditions(),
    OpenKatReportBlockKind.organizationComparison:
        OpenKatReportBlockPreconditions(
          capabilities: {OpenKatReportCapability.multipleOrganizations},
          omitWhenUnavailable: true,
        ),
    OpenKatReportBlockKind.severityConcentration:
        OpenKatReportBlockPreconditions(),
    OpenKatReportBlockKind.portfolioTrend: OpenKatReportBlockPreconditions(
      capabilities: {OpenKatReportCapability.historicalSnapshots},
      omitWhenUnavailable: true,
    ),
    OpenKatReportBlockKind.findingTypePrevalence:
        OpenKatReportBlockPreconditions(),
    OpenKatReportBlockKind.measurementAvailability:
        OpenKatReportBlockPreconditions(viewLimit: 8),
    OpenKatReportBlockKind.measurementAccountability:
        OpenKatReportBlockPreconditions(viewLimit: 8),
    OpenKatReportBlockKind.findingLifecycle: OpenKatReportBlockPreconditions(
      capabilities: {
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.findingLifecycle,
      },
      requiresPreviousAsOf: true,
      omitWhenUnavailable: true,
    ),
    OpenKatReportBlockKind.findingAge: OpenKatReportBlockPreconditions(
      capabilities: {OpenKatReportCapability.reliableOpenedAt},
      omitWhenUnavailable: true,
      viewLimit: 8,
    ),
    OpenKatReportBlockKind.systemHotspots: OpenKatReportBlockPreconditions(
      viewLimit: 8,
    ),
    OpenKatReportBlockKind.systemChanges: OpenKatReportBlockPreconditions(
      capabilities: {
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.stableAssetIdentity,
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      requiresPreviousAsOf: true,
    ),
    OpenKatReportBlockKind.cveExposure: OpenKatReportBlockPreconditions(
      capabilities: {OpenKatReportCapability.reliableCveReferences},
      requiresCveId: true,
    ),
    OpenKatReportBlockKind.cveLandscape: OpenKatReportBlockPreconditions(
      capabilities: {OpenKatReportCapability.reliableCveReferences},
    ),
    OpenKatReportBlockKind.cveChanges: OpenKatReportBlockPreconditions(
      capabilities: {
        OpenKatReportCapability.reliableCveReferences,
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      requiresPreviousAsOf: true,
    ),
    OpenKatReportBlockKind.controlCoverage: OpenKatReportBlockPreconditions(
      viewLimit: 8,
    ),
    OpenKatReportBlockKind.controlChanges: OpenKatReportBlockPreconditions(
      capabilities: {
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.comparableControlsWithDenominator,
        OpenKatReportCapability.comparableMeasurementCoverage,
      },
      requiresPreviousAsOf: true,
      viewLimit: 8,
    ),
    OpenKatReportBlockKind.recommendations: OpenKatReportBlockPreconditions(),
    OpenKatReportBlockKind.assetInventory: OpenKatReportBlockPreconditions(
      viewLimit: 8,
    ),
    OpenKatReportBlockKind.monitoringCoverage: OpenKatReportBlockPreconditions(
      capabilities: {OpenKatReportCapability.reliableMonitoringStatus},
      viewLimit: 8,
    ),
    OpenKatReportBlockKind.monitoringChanges: OpenKatReportBlockPreconditions(
      capabilities: {
        OpenKatReportCapability.historicalSnapshots,
        OpenKatReportCapability.reliableMonitoringStatus,
        OpenKatReportCapability.stableAssetIdentity,
      },
      requiresPreviousAsOf: true,
    ),
    OpenKatReportBlockKind.organizationOverview:
        OpenKatReportBlockPreconditions(
          scopes: {OpenKatReportScopeKind.organization},
        ),
  };

  static OpenKatReportBlockPreconditions definition(
    OpenKatReportBlockKind kind,
  ) => definitions[kind]!;
}

class OpenKatReportBlock {
  final String id;
  final OpenKatReportBlockKind kind;

  const OpenKatReportBlock({required this.id, required this.kind});

  OpenKatReportBlockPreconditions get preconditions =>
      OpenKatReportBlockRegistry.definition(kind);
}

class OpenKatReportPlan {
  final String scenarioId;
  final List<OpenKatReportBlock> blocks;

  const OpenKatReportPlan({required this.scenarioId, required this.blocks});
}

/// Volledige, machineleesbare uitkomst van één generatiepoging.
class OpenKatReportResult {
  final Deck? deck;
  final OpenKatReportPlan? plan;
  final String scenarioId;
  final OpenKatReportScope scope;
  final List<OpenKatMeasurementUsage> measurements;
  final List<OpenKatReportDiagnostic> diagnostics;
  final Set<OpenKatReportCapability> missingCapabilities;
  final List<OpenKatSourceTrace> sourceTraces;

  const OpenKatReportResult({
    required this.deck,
    required this.plan,
    required this.scenarioId,
    required this.scope,
    required this.measurements,
    required this.diagnostics,
    required this.missingCapabilities,
    required this.sourceTraces,
  });

  bool get generated => deck != null;
  bool get hasErrors => diagnostics.any(
    (diagnostic) =>
        diagnostic.severity == OpenKatReportDiagnosticSeverity.error,
  );
}
