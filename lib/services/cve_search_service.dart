import 'dart:convert';

import '../models/cve_hit.dart';
import '../utils/log.dart';
import 'cve_transport.dart';
import 'cve_transport_factory.dart';

final _reCve = RegExp(r'CVE-\d{4}-\d+', caseSensitive: false);
final _reCveExact = RegExp(r'^CVE-\d{4}-\d+$', caseSensitive: false);

/// Strip one trailing slash from a base URL.
String _stripSlash(String s) =>
    s.endsWith('/') ? s.substring(0, s.length - 1) : s;

/// Map a CVSS base score to its qualitative band (upper-case, matching how the
/// CVE sources spell it) — used when a source gives a score but no band.
String cvssBand(double score) {
  if (score <= 0) return 'NONE';
  if (score < 4) return 'LOW';
  if (score < 7) return 'MEDIUM';
  if (score < 9) return 'HIGH';
  return 'CRITICAL';
}

/// Why a CVE search yielded no hits (the picker renders this).
enum CveSearchFailure {
  /// The query is shorter than the source accepts (3 chars).
  tooShort,

  /// Every source failed to reach the network / returned an error.
  network,
}

/// The outcome of a [CveSearchService.search]: hits, or a typed failure.
class CveSearchResult {
  const CveSearchResult.ok(this.hits) : failure = null;
  const CveSearchResult.failed(this.failure) : hits = const [];

  final List<CveHit> hits;
  final CveSearchFailure? failure;

  bool get isOk => failure == null;
}

/// One CVE data source in the cascade (librekat mirror → ENISA → MITRE).
abstract class CveSource {
  Future<List<CveHit>> search(String query);
}

/// Primary source: a librekat NVD mirror. `GET <base>/api/search?q=&limit=`
/// searches **by CVE-id pattern** (e.g. `2021-44228`, `CVE-2024`) and returns
/// `{results: [{id, description, cvssScore, cvssSeverity, published}], …}`.
class LibrekatCveSource implements CveSource {
  LibrekatCveSource({required this.baseUrl, required this.transport});

  final String baseUrl;
  final CveTransport transport;

  @override
  Future<List<CveHit>> search(String query) async {
    final uri = Uri.parse(
      '${_stripSlash(baseUrl)}/api/search',
    ).replace(queryParameters: {'q': query, 'limit': '25'});
    final body = await transport.getBody(uri);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final results = (json['results'] as List?) ?? const [];
    return [
      for (final r in results.whereType<Map<String, dynamic>>())
        CveHit(
          id: (r['id'] as String?)?.trim() ?? '',
          description: (r['description'] as String?)?.trim() ?? '',
          cvssScore: (r['cvssScore'] as num?)?.toDouble(),
          cvssSeverity: (r['cvssSeverity'] as String?)?.trim() ?? '',
          published: (r['published'] as String?)?.trim() ?? '',
        ),
    ].where((h) => h.id.isNotEmpty).toList();
  }
}

/// Fallback source: the ENISA **EU Vulnerability Database** (EUVD). Its
/// `GET <base>/api/search?text=<q>` does **keyword** search (broader than the
/// id-pattern mirror), returning `{items: [{aliases, description, baseScore,
/// baseScoreVector, datePublished, …}]}`; the CVE id comes from `aliases`.
class EnisaCveSource implements CveSource {
  EnisaCveSource({this.baseUrl = defaultBaseUrl, required this.transport});

  static const defaultBaseUrl = 'https://euvdservices.enisa.europa.eu';

  final String baseUrl;
  final CveTransport transport;

  @override
  Future<List<CveHit>> search(String query) async {
    final uri = Uri.parse(
      '${_stripSlash(baseUrl)}/api/search',
    ).replace(queryParameters: {'text': query, 'size': '25'});
    final body = await transport.getBody(uri);
    final json = jsonDecode(body) as Map<String, dynamic>;
    final items = (json['items'] as List?) ?? const [];
    final hits = <CveHit>[];
    for (final item in items.whereType<Map<String, dynamic>>()) {
      final cve = _reCve.firstMatch('${item['aliases'] ?? ''}')?.group(0);
      if (cve == null) continue;
      final score = (item['baseScore'] as num?)?.toDouble();
      hits.add(
        CveHit(
          id: cve.toUpperCase(),
          description: (item['description'] as String?)?.trim() ?? '',
          cvssScore: score,
          cvssSeverity: score == null ? '' : cvssBand(score),
          published: (item['datePublished'] as String?)?.trim() ?? '',
        ),
      );
    }
    return hits;
  }
}

/// Last-resort source: MITRE's CVE Services API. It only does **exact-id**
/// lookup (`GET <base>/api/cve/<id>`, CVE JSON 5.0), so it acts only when the
/// query is a full CVE id; otherwise it returns nothing.
class MitreCveSource implements CveSource {
  MitreCveSource({this.baseUrl = defaultBaseUrl, required this.transport});

  static const defaultBaseUrl = 'https://cveawg.mitre.org';

  final String baseUrl;
  final CveTransport transport;

  @override
  Future<List<CveHit>> search(String query) async {
    if (!_reCveExact.hasMatch(query.trim())) return const [];
    final id = query.trim().toUpperCase();
    final body = await transport.getBody(
      Uri.parse('${_stripSlash(baseUrl)}/api/cve/$id'),
    );
    final json = jsonDecode(body) as Map<String, dynamic>;
    final meta = json['cveMetadata'] as Map<String, dynamic>? ?? const {};
    final containers = json['containers'] as Map<String, dynamic>? ?? const {};
    final cvss = _mitreCvss(containers);
    return [
      CveHit(
        id: (meta['cveId'] as String?)?.trim() ?? id,
        description: _mitreDescription(containers),
        cvssScore: cvss?.$1,
        cvssSeverity: cvss?.$2 ?? '',
        published: (meta['datePublished'] as String?)?.trim() ?? '',
      ),
    ];
  }

  static String _mitreDescription(Map<String, dynamic> containers) {
    final cna = containers['cna'] as Map<String, dynamic>?;
    final descs = (cna?['descriptions'] as List?) ?? const [];
    String? fallback;
    for (final d in descs.whereType<Map<String, dynamic>>()) {
      final value = (d['value'] as String?)?.trim();
      if (value == null || value.isEmpty) continue;
      if (d['lang'] == 'en') return value;
      fallback ??= value;
    }
    return fallback ?? '';
  }

  /// The first CVSS (v4 → v3.1 → v3.0) base score + band across the CNA and any
  /// ADP metric blocks — MITRE stores metrics in either container.
  static (double, String)? _mitreCvss(Map<String, dynamic> containers) {
    final lists = <List<dynamic>>[];
    final cna = containers['cna'] as Map<String, dynamic>?;
    if (cna?['metrics'] is List) lists.add(cna!['metrics'] as List<dynamic>);
    final adp = containers['adp'];
    if (adp is List) {
      for (final a in adp.whereType<Map<String, dynamic>>()) {
        if (a['metrics'] is List) lists.add(a['metrics'] as List<dynamic>);
      }
    }
    for (final key in const ['cvssV4_0', 'cvssV3_1', 'cvssV3_0']) {
      for (final list in lists) {
        for (final m in list.whereType<Map<String, dynamic>>()) {
          final data = m[key] as Map<String, dynamic>?;
          final score = (data?['baseScore'] as num?)?.toDouble();
          if (score != null) {
            final sev = (data?['baseSeverity'] as String?)?.trim();
            return (score, sev == null || sev.isEmpty ? cvssBand(score) : sev);
          }
        }
      }
    }
    return null;
  }
}

/// Runs the [sources] in order until one yields results — the cascade
/// (librekat mirror → ENISA EUVD → MITRE). A `network` failure means every
/// source errored.
class CveSearchService {
  CveSearchService(this.sources);

  final List<CveSource> sources;

  Future<CveSearchResult> search(String query) async {
    final q = query.trim();
    if (q.length < 3) {
      return const CveSearchResult.failed(CveSearchFailure.tooShort);
    }
    var anySucceeded = false;
    for (final source in sources) {
      try {
        final hits = await source.search(q);
        anySucceeded = true;
        if (hits.isNotEmpty) return CveSearchResult.ok(hits);
      } catch (e) {
        // Try the next source in the cascade.
        logError('CveSource.search', e);
      }
    }
    return anySucceeded
        ? const CveSearchResult.ok([])
        : const CveSearchResult.failed(CveSearchFailure.network);
  }
}

/// The default cascade for [baseUrl] using the platform transport (SSRF-pinned
/// on desktop; the web build gates the feature off before reaching here):
/// the configured librekat mirror first, then ENISA EUVD (keyword search), then
/// MITRE (exact-id lookup) as a last resort.
CveSearchService defaultCveSearchService(String baseUrl) {
  final transport = createCveTransport();
  return CveSearchService([
    LibrekatCveSource(baseUrl: baseUrl, transport: transport),
    EnisaCveSource(transport: transport),
    MitreCveSource(transport: transport),
  ]);
}
