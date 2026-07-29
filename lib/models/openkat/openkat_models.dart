/// Feiten die de bronvorm zelf aantoonbaar kan dragen.
///
/// Dit staat los van wat in één specifieke meting gevuld is. Een lege
/// CVE-lijst kan immers betekenen dat er geen blootstelling is, maar alleen
/// wanneer de exportvorm CVE-verwijzingen überhaupt betrouwbaar levert.
enum OpenKatSourceFeature {
  stableAssetIdentity,
  stableFindingIdentity,
  reliableCveReferences,
  reliableMonitoringStatus,
  reliableOpenedAt,
  comparableMeasurementCoverage,
}

/// Expliciete monitoringstatus uit de bron.
///
/// Afwezig blijft `null`: voorkomen in een export is geen bewijs dat een asset
/// actief gemonitord wordt.
enum OpenKatMonitoringStatus { monitored, notMonitored }

/// Internal, forensically-traceable representation of one or more OpenKAT
/// reports. Every value is derived from the JSON source; the parser adds no
/// technical conclusions of its own.
class OpenKatOrganization {
  final String code;
  final String name;
  final List<OpenKatSnapshot> snapshots;

  const OpenKatOrganization({
    required this.code,
    required this.name,
    required this.snapshots,
  });

  OpenKatSnapshot? get current => snapshots.isNotEmpty ? snapshots.last : null;
  OpenKatSnapshot? get previous =>
      snapshots.length >= 2 ? snapshots[snapshots.length - 2] : null;

  OpenKatOrganization copyWith({
    String? code,
    String? name,
    List<OpenKatSnapshot>? snapshots,
  }) => OpenKatOrganization(
    code: code ?? this.code,
    name: name ?? this.name,
    snapshots: snapshots ?? this.snapshots,
  );
}

class OpenKatSnapshot {
  final DateTime reportDate;
  final String sourceFile;
  final String sourceHash;
  final String? schema;

  final List<OpenKatSystem> systems;
  final List<OpenKatFinding> findings;
  final Map<String, OpenKatControlScore> controls;

  /// Of de scanner en normalizer deze meting inhoudelijk konden gebruiken.
  ///
  /// Een onbruikbare meting blijft desgewenst herleidbaar, maar mag nooit door
  /// een peildatumselectie worden gekozen.
  final bool usable;

  /// Mogelijkheden die de adapter voor deze bronvorm expliciet garandeert.
  final Set<OpenKatSourceFeature> sourceFeatures;

  /// Stabiele bronidentiteit van de gemeten populatie, wanneer aanwezig.
  ///
  /// Alleen gelijke, niet-lege waarden bewijzen vergelijkbare meetdekking.
  final String? measurementScopeId;

  const OpenKatSnapshot({
    required this.reportDate,
    required this.sourceFile,
    required this.sourceHash,
    this.schema,
    this.systems = const [],
    this.findings = const [],
    this.controls = const {},
    this.usable = true,
    this.sourceFeatures = const {},
    this.measurementScopeId,
  });

  OpenKatSnapshot copyWith({
    DateTime? reportDate,
    String? sourceFile,
    String? sourceHash,
    String? schema,
    bool clearSchema = false,
    List<OpenKatSystem>? systems,
    List<OpenKatFinding>? findings,
    Map<String, OpenKatControlScore>? controls,
    bool? usable,
    Set<OpenKatSourceFeature>? sourceFeatures,
    String? measurementScopeId,
    bool clearMeasurementScopeId = false,
  }) => OpenKatSnapshot(
    reportDate: reportDate ?? this.reportDate,
    sourceFile: sourceFile ?? this.sourceFile,
    sourceHash: sourceHash ?? this.sourceHash,
    schema: clearSchema ? null : (schema ?? this.schema),
    systems: systems ?? this.systems,
    findings: findings ?? this.findings,
    controls: controls ?? this.controls,
    usable: usable ?? this.usable,
    sourceFeatures: sourceFeatures ?? this.sourceFeatures,
    measurementScopeId: clearMeasurementScopeId
        ? null
        : (measurementScopeId ?? this.measurementScopeId),
  );
}

class OpenKatSystem {
  /// Normalised system anchor, e.g. an IP address or hostname.
  final String id;
  final String? hostname;
  final String? ip;

  /// The original OOIs that resolve to this anchor.
  final List<String> oois;

  /// Waar wanneer [id] rechtstreeks uit een stabiele bronidentiteit volgt.
  final bool stableIdentity;

  /// Alleen gevuld wanneer de bron monitoringstatus expliciet levert.
  final OpenKatMonitoringStatus? monitoringStatus;

  const OpenKatSystem({
    required this.id,
    this.hostname,
    this.ip,
    this.oois = const [],
    this.stableIdentity = false,
    this.monitoringStatus,
  });

  OpenKatSystem copyWith({
    String? id,
    String? hostname,
    bool clearHostname = false,
    String? ip,
    bool clearIp = false,
    List<String>? oois,
    bool? stableIdentity,
    OpenKatMonitoringStatus? monitoringStatus,
    bool clearMonitoringStatus = false,
  }) => OpenKatSystem(
    id: id ?? this.id,
    hostname: clearHostname ? null : (hostname ?? this.hostname),
    ip: clearIp ? null : (ip ?? this.ip),
    oois: oois ?? this.oois,
    stableIdentity: stableIdentity ?? this.stableIdentity,
    monitoringStatus: clearMonitoringStatus
        ? null
        : (monitoringStatus ?? this.monitoringStatus),
  );
}

class OpenKatFinding {
  final String id;
  final String findingTypeId;
  final String? findingTypeName;
  final String severity;
  final String? systemId;
  final DateTime? openedAt;
  final String? recommendation;
  final String? impact;

  /// Which source report(s) this occurrence was seen in.
  final List<String> sourceReports;

  /// Waar wanneer [id] een expliciete bevindingidentiteit uit de bron is.
  final bool stableIdentity;

  /// Alleen expliciet gekoppelde, canoniek geschreven CVE-ID's.
  final List<String> cveIds;

  const OpenKatFinding({
    required this.id,
    required this.findingTypeId,
    this.findingTypeName,
    this.severity = 'medium',
    this.systemId,
    this.openedAt,
    this.recommendation,
    this.impact,
    this.sourceReports = const [],
    this.stableIdentity = false,
    this.cveIds = const [],
  });

  OpenKatFinding copyWith({
    String? id,
    String? findingTypeId,
    String? findingTypeName,
    bool clearFindingTypeName = false,
    String? severity,
    String? systemId,
    bool clearSystemId = false,
    DateTime? openedAt,
    bool clearOpenedAt = false,
    String? recommendation,
    bool clearRecommendation = false,
    String? impact,
    bool clearImpact = false,
    List<String>? sourceReports,
    bool? stableIdentity,
    List<String>? cveIds,
  }) => OpenKatFinding(
    id: id ?? this.id,
    findingTypeId: findingTypeId ?? this.findingTypeId,
    findingTypeName: clearFindingTypeName
        ? null
        : (findingTypeName ?? this.findingTypeName),
    severity: severity ?? this.severity,
    systemId: clearSystemId ? null : (systemId ?? this.systemId),
    openedAt: clearOpenedAt ? null : (openedAt ?? this.openedAt),
    recommendation: clearRecommendation
        ? null
        : (recommendation ?? this.recommendation),
    impact: clearImpact ? null : (impact ?? this.impact),
    sourceReports: sourceReports ?? this.sourceReports,
    stableIdentity: stableIdentity ?? this.stableIdentity,
    cveIds: cveIds ?? this.cveIds,
  );
}

class OpenKatControlScore {
  final String name;
  final int? compliant;
  final int? total;

  const OpenKatControlScore({required this.name, this.compliant, this.total});

  double? get ratio {
    final t = total;
    final c = compliant;
    if (t == null || t == 0 || c == null) return null;
    return c / t;
  }
}

class OpenKatManifestEntry {
  final String path;
  final String hash;
  final String? organizationCode;
  final String? organizationName;
  final DateTime? reportDate;
  final String? schema;
  final String status;
  final String? error;

  const OpenKatManifestEntry({
    required this.path,
    required this.hash,
    this.organizationCode,
    this.organizationName,
    this.reportDate,
    this.schema,
    required this.status,
    this.error,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'hash': hash,
    if (organizationCode != null) 'organizationCode': organizationCode,
    if (organizationName != null) 'organizationName': organizationName,
    if (reportDate != null) 'reportDate': reportDate!.toIso8601String(),
    if (schema != null) 'schema': schema,
    'status': status,
    if (error != null) 'error': error,
  };
}

class OpenKatManifest {
  final String parserVersion;
  final DateTime importedAt;
  final String directory;
  final List<OpenKatManifestEntry> entries;

  const OpenKatManifest({
    required this.parserVersion,
    required this.importedAt,
    required this.directory,
    required this.entries,
  });

  List<OpenKatManifestEntry> get recognized =>
      entries.where((e) => e.status == 'ok').toList();
  List<OpenKatManifestEntry> get duplicates =>
      entries.where((e) => e.status == 'duplicate').toList();
  List<OpenKatManifestEntry> get conflicts =>
      entries.where((e) => e.status == 'conflict').toList();
  List<OpenKatManifestEntry> get unrecognized =>
      entries.where((e) => e.status == 'unrecognized').toList();
  List<OpenKatManifestEntry> get errors =>
      entries.where((e) => e.status.startsWith('error')).toList();

  Map<String, dynamic> toJson() => {
    'parserVersion': parserVersion,
    'importedAt': importedAt.toIso8601String(),
    'directory': directory,
    'entries': entries.map((e) => e.toJson()).toList(),
  };
}
