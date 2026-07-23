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
  }) =>
      OpenKatOrganization(
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

  const OpenKatSnapshot({
    required this.reportDate,
    required this.sourceFile,
    required this.sourceHash,
    this.schema,
    this.systems = const [],
    this.findings = const [],
    this.controls = const {},
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
  }) =>
      OpenKatSnapshot(
        reportDate: reportDate ?? this.reportDate,
        sourceFile: sourceFile ?? this.sourceFile,
        sourceHash: sourceHash ?? this.sourceHash,
        schema: clearSchema ? null : (schema ?? this.schema),
        systems: systems ?? this.systems,
        findings: findings ?? this.findings,
        controls: controls ?? this.controls,
      );
}

class OpenKatSystem {
  /// Normalised system anchor, e.g. an IP address or hostname.
  final String id;
  final String? hostname;
  final String? ip;

  /// The original OOIs that resolve to this anchor.
  final List<String> oois;

  const OpenKatSystem({
    required this.id,
    this.hostname,
    this.ip,
    this.oois = const [],
  });

  OpenKatSystem copyWith({
    String? id,
    String? hostname,
    bool clearHostname = false,
    String? ip,
    bool clearIp = false,
    List<String>? oois,
  }) =>
      OpenKatSystem(
        id: id ?? this.id,
        hostname: clearHostname ? null : (hostname ?? this.hostname),
        ip: clearIp ? null : (ip ?? this.ip),
        oois: oois ?? this.oois,
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
  }) =>
      OpenKatFinding(
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
      );
}

class OpenKatControlScore {
  final String name;
  final int? compliant;
  final int? total;

  const OpenKatControlScore({
    required this.name,
    this.compliant,
    this.total,
  });

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
