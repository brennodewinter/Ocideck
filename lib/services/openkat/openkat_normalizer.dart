import '../../models/openkat/openkat_models.dart';
import 'openkat_directory_scanner.dart';
import 'openkat_json_adapter.dart';

/// Het systeem waar de OpenKAT-sleutel [ooi] bij hoort: een hostname als de
/// sleutel er een draagt, anders een IP-adres.
///
/// Een primary key van OpenKAT is een `|`-gescheiden reeks die begint bij het
/// objecttype en het *netwerk* waarin het object is gevonden
/// (`Hostname|internet|underdark.nl`), en die voor samengestelde types de
/// sleutels van zijn onderdelen achter elkaar plakt — een `Website` draagt zijn
/// `IPService` én zijn `Hostname`, een `HTTPHeader` daarbovenop nog een pad en
/// een headernaam.
///
/// Dus wordt hier niet op positie geteld maar op vórm gezocht: het laatste
/// segment dat als host leest is waar het object hoort. Dat vouwt elk pad en
/// elke header van één website samen tot dat ene systeem, en het is bestand
/// tegen een samenstelling die dit bestand nog niet kent — precies wat een
/// grammatica die per type een segmentnummer onthoudt niet is.
///
/// Een hostname wint van een IP-adres, want een website waarvan beide bekend
/// zijn is de hostname. Levert de vorm niets op, dan tellen eerst de velden van
/// [object] en pas daarna het laatste segment (`Network|internet` → `internet`);
/// een sleutel zonder segmenten komt onveranderd terug. Nooit een gok die een
/// bestaand systeem zou kunnen kapen.
String openKatSystemAnchor(
  String ooi, [
  Map<String, dynamic> object = const {},
]) {
  final segments = ooi.split('|');
  String? host;
  String? address;
  for (final segment in segments) {
    final value = segment.trim();
    if (value.isEmpty) continue;
    final fromUri = value.contains('://') ? Uri.tryParse(value)?.host : null;
    final candidate = (fromUri != null && fromUri.isNotEmpty) ? fromUri : value;
    if (_looksLikeHostname(candidate)) {
      host = candidate.toLowerCase();
    } else if (_looksLikeIpv4(candidate) || _looksLikeIpv6(candidate)) {
      address = candidate.toLowerCase();
    }
  }
  final anchor = host ?? address;
  if (anchor != null) return anchor;

  for (final key in const ['hostname', 'ip', 'address', 'name']) {
    final value = object[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return segments.length > 1 ? segments.last.trim() : ooi;
}

/// Een naam met minstens één punt, waarvan het laatste deel uit letters bestaat
/// — genoeg om `underdark.nl` van `185.73.32.3`, `Strict-Transport-Security`,
/// `tcp`, `443` en `/.well-known/security.txt` te scheiden.
///
/// Een hostname zonder punt (`intranet`) valt hier bewust buiten: hij is niet te
/// onderscheiden van de losse woorden waar deze sleutels vol mee staan, en die
/// verwarring maakt van een headernaam een systeem.
bool _looksLikeHostname(String value) => RegExp(
  r'^[a-z0-9]([a-z0-9-]*[a-z0-9])?(\.[a-z0-9]([a-z0-9-]*[a-z0-9])?)*\.[a-z]{2,}$',
  caseSensitive: false,
).hasMatch(value);

bool _looksLikeIpv4(String value) =>
    RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(value);

bool _looksLikeIpv6(String value) =>
    value.contains(':') &&
    RegExp(r'^[0-9a-f:]+$', caseSensitive: false).hasMatch(value);

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
      sourceFeatures: adapter.sourceFeatures,
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
          stableIdentity: ooi.isNotEmpty,
        );
      }
    }

    return byAnchor.values.toList();
  }

  String _systemAnchor(String ooi, Map<String, dynamic> object) =>
      openKatSystemAnchor(ooi, object);

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
      final cveIds = _explicitCveIds(object);

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
          stableIdentity: primaryKey != null && primaryKey.isNotEmpty,
          cveIds: cveIds,
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
          cveIds: {...existing.cveIds, ...finding.cveIds}.toList()..sort(),
        );
      }
    }
    return byId.values.toList();
  }

  List<String> _explicitCveIds(Map<String, dynamic> object) {
    final raw = object['cve_ids'] ?? object['cves'];
    if (raw is! List) return const [];
    final ids = <String>{};
    for (final value in raw) {
      if (value is! String) continue;
      final canonical = value.trim().toUpperCase();
      if (RegExp(r'^CVE-[0-9]{4}-[0-9]{4,}$').hasMatch(canonical)) {
        ids.add(canonical);
      }
    }
    final sorted = ids.toList()..sort();
    return sorted;
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
