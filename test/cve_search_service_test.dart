import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/cve_search_service.dart';
import 'package:ocideck/services/cve_transport.dart';

/// A transport that returns fixed bytes (or throws) — the CVE service is tested
/// without any network access.
class _FakeTransport implements CveTransport {
  _FakeTransport(this.body, {this.throwIt = false});
  final String body;
  final bool throwIt;
  Uri? lastUri;

  @override
  Future<String> getBody(Uri uri) async {
    lastUri = uri;
    if (throwIt) throw const CveTransportException('boom');
    return body;
  }
}

const _sample =
    '{"results":[{"id":"CVE-2021-44228","description":"Log4Shell",'
    '"published":"2021-12-10T10:15:09.143","cvssScore":10.0,'
    '"cvssSeverity":"CRITICAL"}],"total":1,"query":"2021-44228"}';

CveSearchService _service(_FakeTransport t) => CveSearchService([
  LibrekatCveSource(baseUrl: 'https://cveapi.example', transport: t),
]);

void main() {
  test(
    'parses the mirror response into hits and builds the search URL',
    () async {
      final t = _FakeTransport(_sample);
      final res = await _service(t).search('2021-44228');

      expect(res.isOk, isTrue);
      expect(res.hits, hasLength(1));
      final h = res.hits.first;
      expect(h.id, 'CVE-2021-44228');
      expect(h.cvssScore, 10.0);
      expect(h.cvssSeverity, 'CRITICAL');
      expect(h.description, 'Log4Shell');
      expect(h.url, 'https://nvd.nist.gov/vuln/detail/CVE-2021-44228');
      expect(t.lastUri!.path, '/api/search');
      expect(t.lastUri!.queryParameters['q'], '2021-44228');
      expect(t.lastUri!.queryParameters['limit'], '25');
    },
  );

  test('a query under 3 chars is rejected without a fetch', () async {
    final t = _FakeTransport(_sample);
    final res = await _service(t).search('12');
    expect(res.failure, CveSearchFailure.tooShort);
    expect(t.lastUri, isNull);
  });

  test('every source failing is a network failure', () async {
    final res = await _service(
      _FakeTransport('', throwIt: true),
    ).search('2021');
    expect(res.failure, CveSearchFailure.network);
  });

  test('an empty result set is a successful no-hit outcome', () async {
    final res = await _service(
      _FakeTransport('{"results":[],"total":0,"query":"zzz"}'),
    ).search('zzz');
    expect(res.isOk, isTrue);
    expect(res.hits, isEmpty);
  });

  group('EnisaCveSource', () {
    const enisa =
        '{"items":[{"id":"EUVD-2026-21412","aliases":"CVE-2026-34481",'
        '"description":"Apache Log4j issue","datePublished":"Apr 10, 2026",'
        '"baseScore":6.3,"baseScoreVersion":"4.0"}],"total":1}';

    test(
      'parses items, taking the CVE id from aliases and deriving a band',
      () async {
        final t = _FakeTransport(enisa);
        final hits = await EnisaCveSource(
          baseUrl: 'https://euvd.example',
          transport: t,
        ).search('log4j');
        expect(hits, hasLength(1));
        expect(hits.first.id, 'CVE-2026-34481');
        expect(hits.first.cvssScore, 6.3);
        expect(hits.first.cvssSeverity, 'MEDIUM'); // derived from 6.3
        expect(t.lastUri!.queryParameters['text'], 'log4j'); // keyword search
      },
    );
  });

  group('MitreCveSource', () {
    const mitre =
        '{"cveMetadata":{"cveId":"CVE-2021-44228",'
        '"datePublished":"2021-12-10T10:15:09"},"containers":{"cna":'
        '{"descriptions":[{"lang":"en","value":"Log4Shell RCE"}]},"adp":'
        '[{"metrics":[{"cvssV3_1":{"baseScore":10.0,"baseSeverity":"CRITICAL"}}]}]}}';

    test('only acts on a full CVE id', () async {
      final t = _FakeTransport(mitre);
      final byKeyword = await MitreCveSource(transport: t).search('log4j');
      expect(byKeyword, isEmpty);
      expect(t.lastUri, isNull); // no lookup for a non-id query
    });

    test(
      'looks up an exact id and parses the CVSS from the ADP block',
      () async {
        final t = _FakeTransport(mitre);
        final hits = await MitreCveSource(
          transport: t,
        ).search('cve-2021-44228');
        expect(hits, hasLength(1));
        expect(hits.first.id, 'CVE-2021-44228');
        expect(hits.first.description, 'Log4Shell RCE');
        expect(hits.first.cvssScore, 10.0);
        expect(hits.first.cvssSeverity, 'CRITICAL');
        expect(t.lastUri!.path, '/api/cve/CVE-2021-44228');
      },
    );
  });

  test(
    'cascade falls back to ENISA keyword search when the mirror is empty',
    () async {
      final t = _RoutingTransport({
        'cveapi.example': '{"results":[],"total":0,"query":"log4j"}',
        'euvd.example':
            '{"items":[{"aliases":"CVE-2021-44228","description":"x",'
            '"baseScore":10.0}],"total":1}',
      });
      final service = CveSearchService([
        LibrekatCveSource(baseUrl: 'https://cveapi.example', transport: t),
        EnisaCveSource(baseUrl: 'https://euvd.example', transport: t),
      ]);
      final res = await service.search('log4j');
      expect(res.isOk, isTrue);
      expect(res.hits.single.id, 'CVE-2021-44228');
    },
  );
}

/// Routes each request to a fixed body by a host substring; anything else fails.
class _RoutingTransport implements CveTransport {
  _RoutingTransport(this.byHost);
  final Map<String, String> byHost;

  @override
  Future<String> getBody(Uri uri) async {
    for (final entry in byHost.entries) {
      if (uri.host.contains(entry.key)) return entry.value;
    }
    throw const CveTransportException('no route');
  }
}
