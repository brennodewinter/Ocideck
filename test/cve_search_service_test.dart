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
}
