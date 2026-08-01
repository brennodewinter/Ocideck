import 'dart:convert';

enum AssetRightsRisk { clear, review, high }

enum AssetRightsDispositionStatus { accepted, resolved, rejected, deferred }

class AssetRightsProvenance {
  final String? sourceUrl;
  final String? creator;
  final String? license;
  final String? licenseEvidence;
  final DateTime? licenseExpiresAt;

  const AssetRightsProvenance({
    this.sourceUrl,
    this.creator,
    this.license,
    this.licenseEvidence,
    this.licenseExpiresAt,
  });

  bool get hasRightsEvidence =>
      (license?.trim().isNotEmpty ?? false) &&
      (licenseEvidence?.trim().isNotEmpty ?? false);

  Map<String, Object?> toJson() => {
    if (sourceUrl != null) 'source_url': sourceUrl,
    if (creator != null) 'creator': creator,
    if (license != null) 'license': license,
    if (licenseEvidence != null) 'license_evidence': licenseEvidence,
    if (licenseExpiresAt != null)
      'license_expires_at': licenseExpiresAt!.toUtc().toIso8601String(),
  };

  factory AssetRightsProvenance.fromJson(Object? value) {
    final map = value is Map ? value : const <Object?, Object?>{};
    DateTime? date(String key) => DateTime.tryParse('${map[key] ?? ''}');
    String? text(String key) {
      final value = map[key];
      return value is String && value.trim().isNotEmpty ? value.trim() : null;
    }

    return AssetRightsProvenance(
      sourceUrl: text('source_url'),
      creator: text('creator'),
      license: text('license'),
      licenseEvidence: text('license_evidence'),
      licenseExpiresAt: date('license_expires_at'),
    );
  }
}

class AssetRightsSignal {
  final String ruleId;
  final AssetRightsRisk risk;
  final String message;
  final String fingerprint;
  final Map<String, String> evidence;

  const AssetRightsSignal({
    required this.ruleId,
    required this.risk,
    required this.message,
    required this.fingerprint,
    this.evidence = const {},
  });

  String get key => '$ruleId $fingerprint';

  Map<String, Object?> toJson() => {
    'rule': ruleId,
    'risk': risk.name,
    'message': message,
    'fingerprint': fingerprint,
    if (evidence.isNotEmpty) 'evidence': evidence,
  };

  factory AssetRightsSignal.fromJson(Object? value) {
    final map = value is Map ? value : const <Object?, Object?>{};
    final evidence = map['evidence'];
    return AssetRightsSignal(
      ruleId: '${map['rule'] ?? 'unknown'}',
      risk: AssetRightsRisk.values.firstWhere(
        (v) => v.name == map['risk'],
        orElse: () => AssetRightsRisk.review,
      ),
      message: '${map['message'] ?? ''}',
      fingerprint: '${map['fingerprint'] ?? ''}',
      evidence: evidence is Map
          ? {for (final e in evidence.entries) '${e.key}': '${e.value}'}
          : const {},
    );
  }
}

class AssetRightsDisposition {
  final String signalKey;
  final AssetRightsDispositionStatus status;
  final String reason;
  final String? note;
  final String? decidedBy;
  final DateTime decidedAt;
  final bool revoked;

  const AssetRightsDisposition({
    required this.signalKey,
    required this.status,
    required this.reason,
    required this.decidedAt,
    this.note,
    this.decidedBy,
    this.revoked = false,
  });

  bool get suppressesWarning =>
      !revoked &&
      (status == AssetRightsDispositionStatus.accepted ||
          status == AssetRightsDispositionStatus.resolved);

  Map<String, Object?> toJson() => {
    'signal': signalKey,
    'status': status.name,
    'reason': reason,
    if (note != null) 'note': note,
    if (decidedBy != null) 'decided_by': decidedBy,
    'decided_at': decidedAt.toUtc().toIso8601String(),
    if (revoked) 'revoked': true,
  };

  factory AssetRightsDisposition.fromJson(Object? value) {
    final map = value is Map ? value : const <Object?, Object?>{};
    return AssetRightsDisposition(
      signalKey: '${map['signal'] ?? ''}',
      status: AssetRightsDispositionStatus.values.firstWhere(
        (v) => v.name == map['status'],
        orElse: () => AssetRightsDispositionStatus.deferred,
      ),
      reason: '${map['reason'] ?? ''}',
      note: map['note'] is String ? map['note'] as String : null,
      decidedBy: map['decided_by'] is String
          ? map['decided_by'] as String
          : null,
      decidedAt:
          DateTime.tryParse('${map['decided_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      revoked: map['revoked'] == true,
    );
  }
}

class AssetRightsAssessment {
  static const formatVersion = 1;

  final String sha256;
  final String mimeType;
  final int byteLength;
  final int? width;
  final int? height;
  final String scannerVersion;
  final DateTime scannedAt;
  final AssetRightsProvenance provenance;
  final List<AssetRightsSignal> signals;
  final List<AssetRightsDisposition> dispositions;

  const AssetRightsAssessment({
    required this.sha256,
    required this.mimeType,
    required this.byteLength,
    required this.scannerVersion,
    required this.scannedAt,
    this.width,
    this.height,
    this.provenance = const AssetRightsProvenance(),
    this.signals = const [],
    this.dispositions = const [],
  });

  List<AssetRightsSignal> get openSignals => [
    for (final signal in signals)
      if (!_latestDisposition(signal.key).suppressesWarning) signal,
  ];

  AssetRightsDisposition _latestDisposition(String key) {
    final matching = dispositions.where((d) => d.signalKey == key).toList()
      ..sort((a, b) => b.decidedAt.compareTo(a.decidedAt));
    return matching.isEmpty
        ? AssetRightsDisposition(
            signalKey: key,
            status: AssetRightsDispositionStatus.deferred,
            reason: '',
            decidedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            revoked: true,
          )
        : matching.first;
  }

  AssetRightsRisk get risk => openSignals.fold(
    AssetRightsRisk.clear,
    (current, signal) =>
        signal.risk.index > current.index ? signal.risk : current,
  );

  AssetRightsAssessment copyWith({
    AssetRightsProvenance? provenance,
    List<AssetRightsSignal>? signals,
    List<AssetRightsDisposition>? dispositions,
    String? scannerVersion,
    DateTime? scannedAt,
  }) => AssetRightsAssessment(
    sha256: sha256,
    mimeType: mimeType,
    byteLength: byteLength,
    width: width,
    height: height,
    scannerVersion: scannerVersion ?? this.scannerVersion,
    scannedAt: scannedAt ?? this.scannedAt,
    provenance: provenance ?? this.provenance,
    signals: signals ?? this.signals,
    dispositions: dispositions ?? this.dispositions,
  );

  Map<String, Object?> toJson() => {
    'version': formatVersion,
    'asset': {
      'sha256': sha256,
      'mime_type': mimeType,
      'bytes': byteLength,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
    },
    'provenance': provenance.toJson(),
    'assessment': {
      'scanner_version': scannerVersion,
      'scanned_at': scannedAt.toUtc().toIso8601String(),
      'signals': signals.map((s) => s.toJson()).toList(),
    },
    if (dispositions.isNotEmpty)
      'dispositions': dispositions.map((d) => d.toJson()).toList(),
  };

  String encode({bool pretty = true}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toJson());

  factory AssetRightsAssessment.fromJson(Object? value) {
    final root = value is Map ? value : const <Object?, Object?>{};
    if (root['version'] != formatVersion) {
      throw const FormatException('Onbekende assetrechten-sidecarversie');
    }
    final asset = root['asset'] is Map
        ? root['asset'] as Map
        : const <Object?, Object?>{};
    final scan = root['assessment'] is Map
        ? root['assessment'] as Map
        : const <Object?, Object?>{};
    return AssetRightsAssessment(
      sha256: '${asset['sha256'] ?? ''}',
      mimeType: '${asset['mime_type'] ?? ''}',
      byteLength: asset['bytes'] is int ? asset['bytes'] as int : 0,
      width: asset['width'] is int ? asset['width'] as int : null,
      height: asset['height'] is int ? asset['height'] as int : null,
      scannerVersion: '${scan['scanner_version'] ?? ''}',
      scannedAt:
          DateTime.tryParse('${scan['scanned_at'] ?? ''}') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      provenance: AssetRightsProvenance.fromJson(root['provenance']),
      signals: scan['signals'] is List
          ? [
              for (final item in scan['signals'] as List)
                AssetRightsSignal.fromJson(item),
            ]
          : const [],
      dispositions: root['dispositions'] is List
          ? [
              for (final item in root['dispositions'] as List)
                AssetRightsDisposition.fromJson(item),
            ]
          : const [],
    );
  }

  factory AssetRightsAssessment.decode(String source) =>
      AssetRightsAssessment.fromJson(jsonDecode(source));
}
