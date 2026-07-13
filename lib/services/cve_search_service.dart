import 'dart:convert';

import '../models/cve_hit.dart';
import '../utils/log.dart';
import 'cve_transport.dart';
import 'cve_transport_factory.dart';

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
    final base = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final uri = Uri.parse(
      '$base/api/search',
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

/// Runs the [sources] in order until one yields results — the cascade seam
/// (only the librekat mirror is wired today; ENISA/MITRE plug in as extra
/// sources later). A `network` failure means every source errored.
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

/// The default service for [baseUrl] using the platform transport (SSRF-pinned
/// on desktop; the web build gates the feature off before reaching here).
CveSearchService defaultCveSearchService(String baseUrl) => CveSearchService([
  LibrekatCveSource(baseUrl: baseUrl, transport: createCveTransport()),
]);
