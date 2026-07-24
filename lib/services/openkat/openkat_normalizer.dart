import '../../models/openkat/openkat_models.dart';
import 'openkat_directory_scanner.dart';
import 'openkat_json_adapter.dart';

/// Normalises the source JSON of a snapshot into the shared internal model.
///
/// Keeps provenance (source file, hash, report date, report type) and does not
/// add any technical conclusions beyond what OpenKAT reports.
class OpenKatNormalizer {
  const OpenKatNormalizer();

  OpenKatSnapshot normalize(
    OpenKatSnapshotGroup group, {
    required List<OpenKatSnapshot> olderSnapshots,
  }) {
    final adapter = group.candidate.adapter;
    final json = group.candidate.json;

    final systems = _normalizeSystems(adapter.systemObjects(json));
    final findings = _normalizeFindings(
      adapter.findingObjects(json),
      systems: systems,
      adapter: adapter,
      sourceFile: group.candidate.path,
    );
    final controls = adapter.controlScores(json);

    return OpenKatSnapshot(
      reportDate: group.reportDate,
      sourceFile: group.candidate.path,
      sourceHash: group.candidate.hash,
      schema: group.candidate.schema,
      systems: systems,
      findings: _deduplicateFindings(findings),
      controls: controls,
    );
  }

  List<OpenKatSystem> _normalizeSystems(List<Map<String, dynamic>> objects) {
    final byAnchor = <String, OpenKatSystem>{};

    for (final object in objects) {
      final ooi = _stringField(object, ['ooi', 'id', 'value', 'name']) ?? '';
      final anchor = _systemAnchor(ooi, object);
      final existing = byAnchor[anchor];
      if (existing != null) {
        byAnchor[anchor] = existing.copyWith(
          oois: {...existing.oois, ooi}.toList(),
        );
      } else {
        byAnchor[anchor] = OpenKatSystem(
          id: anchor,
          hostname: _stringField(object, ['hostname', 'name']),
          ip: _stringField(object, [
            'ip',
            'address',
            'ip_address',
            'ipv4',
            'ipv6',
          ]),
          oois: [ooi],
        );
      }
    }

    return byAnchor.values.toList();
  }

  String _systemAnchor(String ooi, Map<String, dynamic> object) {
    final lower = ooi.toLowerCase();
    if (lower.startsWith('ipaddressv4|') || lower.startsWith('ipaddressv6|')) {
      return ooi.split('|').skip(1).join('|');
    }
    if (lower.startsWith('ipport|')) {
      final parts = ooi.split('|');
      return parts.length >= 2 ? parts[1] : ooi;
    }
    if (lower.startsWith('hostname|')) {
      return ooi.split('|').skip(1).join('|');
    }
    if (lower.startsWith('url|') || lower.startsWith('httpresource|')) {
      final raw = ooi.split('|').skip(1).join('|');
      // Uri.tryParse gooit niet — bij onzin komt er null en valt dit terug op
      // de ruwe waarde. De try/bare-catch die hier stond ving dus niets.
      final uri = Uri.tryParse(raw);
      final host = uri?.host;
      return (host == null || host.isEmpty) ? raw : host;
    }
    return _stringField(object, ['hostname', 'ip', 'address', 'name']) ?? ooi;
  }

  List<OpenKatFinding> _normalizeFindings(
    List<Map<String, dynamic>> objects, {
    required List<OpenKatSystem> systems,
    required OpenKatJsonAdapter adapter,
    required String sourceFile,
  }) {
    final out = <OpenKatFinding>[];
    for (final object in objects) {
      final findingType = _mapField(object, [
        'finding_type',
        'finding_type_id',
      ]);
      final typeId =
          _stringField(findingType, ['id', 'key', 'code']) ??
          _stringField(object, ['finding_type', 'finding_type_id', 'type']) ??
          'unknown';
      final typeName =
          _stringField(findingType, ['name', 'title']) ??
          _stringField(object, ['finding_type_name', 'title']);
      final severity =
          _stringField(object, [
            'severity',
            'risk_level',
            'level',
          ])?.toLowerCase() ??
          'medium';
      final primaryKey = _stringField(object, ['primary_key', 'id', 'finding']);
      final ooi =
          _stringField(object, [
            'ooi',
            'object',
            'system',
            'asset',
            'hostname',
            'ip',
          ]) ??
          '';
      final systemId = _resolveSystem(ooi, systems);
      final openedAt = _openedAt(object, sourceFile);
      final recommendation = _stringField(object, [
        'recommendation',
        'recommendations',
        'solution',
        'mitigation',
      ]);
      final impact = _stringField(object, ['impact', 'description', 'summary']);

      out.add(
        OpenKatFinding(
          id:
              primaryKey ??
              '$typeId|${systemId ?? ooi}|${_stringField(object, ['description']) ?? ''}',
          findingTypeId: typeId,
          findingTypeName: typeName,
          severity: severity,
          systemId: systemId ?? ooi,
          openedAt: openedAt,
          recommendation: recommendation,
          impact: impact,
          sourceReports: [sourceFile],
        ),
      );
    }
    return out;
  }

  String? _resolveSystem(String ooi, List<OpenKatSystem> systems) {
    final anchor = _systemAnchor(ooi, {});
    for (final s in systems) {
      if (s.id == anchor || s.oois.contains(ooi)) return s.id;
    }
    return anchor;
  }

  DateTime? _openedAt(Map<String, dynamic> object, String sourceFile) {
    final raw =
        object['first_seen'] ?? object['opened_at'] ?? object['created_at'];
    if (raw is String) return DateTime.tryParse(raw);
    return null;
  }

  List<OpenKatFinding> _deduplicateFindings(List<OpenKatFinding> findings) {
    final byId = <String, OpenKatFinding>{};
    for (final finding in findings) {
      final existing = byId[finding.id];
      if (existing == null) {
        byId[finding.id] = finding;
      } else {
        byId[finding.id] = existing.copyWith(
          sourceReports: {
            ...existing.sourceReports,
            ...finding.sourceReports,
          }.toList(),
        );
      }
    }
    return byId.values.toList();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String? _stringField(dynamic value, List<String> keys) {
    if (value is! Map) return value is String ? value : null;
    final map = value as Map<String, dynamic>;
    for (final key in keys) {
      final v = map[key];
      if (v is String) return v;
      if (v is num) return v.toString();
    }
    return null;
  }

  Map<String, dynamic> _mapField(dynamic value, List<String> keys) {
    if (value is! Map) return const {};
    final map = value as Map<String, dynamic>;
    for (final key in keys) {
      final v = map[key];
      if (v is Map<String, dynamic>) return v;
      if (v is Map) return v.cast<String, dynamic>();
    }
    return const {};
  }
}
