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
    this.tableRowLimit = 25,
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
  stableAssetIdentity,
  comparableMeasurementCoverage,
  findingLifecycle,
  controlsWithDenominator,
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

enum OpenKatMeasurementRole { current, previous }

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
  final double previousRatio;
  final double currentRatio;

  const OpenKatControlChange({
    required this.organizationCode,
    required this.controlId,
    required this.previousRatio,
    required this.currentRatio,
  });

  double get delta => currentRatio - previousRatio;
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
  measurementAvailability,
  findingLifecycle,
  cveExposure,
  monitoringChanges,
}

/// Voorwaarden die uit de betekenis van een blok volgen, onafhankelijk van
/// wat een (eventueel geïnjecteerd) scenario erover declareert.
class OpenKatReportBlockPreconditions {
  final Set<OpenKatReportCapability> capabilities;
  final bool requiresPreviousAsOf;
  final bool requiresCveId;
  final bool omitWhenUnavailable;

  const OpenKatReportBlockPreconditions({
    this.capabilities = const {},
    this.requiresPreviousAsOf = false,
    this.requiresCveId = false,
    this.omitWhenUnavailable = false,
  });
}

extension OpenKatReportBlockContract on OpenKatReportBlockKind {
  OpenKatReportBlockPreconditions get preconditions => switch (this) {
    OpenKatReportBlockKind.managementOverview ||
    OpenKatReportBlockKind.measurementAvailability =>
      const OpenKatReportBlockPreconditions(),
    OpenKatReportBlockKind.findingLifecycle =>
      const OpenKatReportBlockPreconditions(
        capabilities: {
          OpenKatReportCapability.historicalSnapshots,
          OpenKatReportCapability.findingLifecycle,
        },
        requiresPreviousAsOf: true,
        omitWhenUnavailable: true,
      ),
    OpenKatReportBlockKind.cveExposure => const OpenKatReportBlockPreconditions(
      capabilities: {OpenKatReportCapability.reliableCveReferences},
      requiresCveId: true,
    ),
    OpenKatReportBlockKind.monitoringChanges =>
      const OpenKatReportBlockPreconditions(
        capabilities: {
          OpenKatReportCapability.historicalSnapshots,
          OpenKatReportCapability.reliableMonitoringStatus,
          OpenKatReportCapability.stableAssetIdentity,
        },
        requiresPreviousAsOf: true,
      ),
  };
}

class OpenKatReportBlock {
  final String id;
  final OpenKatReportBlockKind kind;

  const OpenKatReportBlock({required this.id, required this.kind});

  OpenKatReportBlockPreconditions get preconditions => kind.preconditions;
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
