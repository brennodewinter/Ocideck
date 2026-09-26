@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/update_check_fetch_io.dart';

/// Zie cve_transport_io_test.dart: een HttpClient die `connectionFactory`
/// (de SSRF-pinning) negeert en het verzoek naar een lokale [HttpServer]
/// stuurt. De NetGuard-controle in [pinnedUpdateCheckFetch] draait gewoon op
/// het opgegeven publieke adres; alleen de socket zelf wordt omgeleid.
class _LocalRedirectClient implements HttpClient {
  final HttpClient _real;
  final int _port;

  _LocalRedirectClient(this._real, this._port);

  @override
  set connectionFactory(_) {}

  @override
  set connectionTimeout(Duration? v) => _real.connectionTimeout = v;

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) => _real.openUrl(
    method,
    url.replace(host: '127.0.0.1', port: _port, scheme: 'http'),
  );

  @override
  void close({bool force = false}) => _real.close(force: force);

  @override
  dynamic noSuchMethod(Invocation i) => _real.noSuchMethod(i);
}

void main() {
  // 8.8.8.8 is een publiek IP dat NetGuard doorlaat zonder DNS-opzoeking;
  // de werkelijke verbinding gaat in de HttpOverrides-tests hieronder naar
  // de lokale server.
  final uri = Uri.parse('https://8.8.8.8/api/v1/releases/latest');

  test(
    'alles behalve https wordt geweigerd vóór er een socket opengaat',
    () async {
      expect(
        await pinnedUpdateCheckFetch(Uri.parse('http://8.8.8.8/x')),
        isNull,
      );
    },
  );

  test(
    'een host die nergens op uitkomt is geen fout, alleen geen uitslag',
    () async {
      // `.invalid` bestaat bij afspraak niet (RFC 2606): de opzoeking faalt en
      // de check meldt stil "geen verdict".
      expect(
        await pinnedUpdateCheckFetch(Uri.parse('https://nergens.invalid/x')),
        isNull,
      );
    },
  );

  group('HTTP-pad', () {
    late HttpServer server;
    late HttpClient realClient;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      realClient = HttpClient();
    });

    tearDown(() {
      realClient.close(force: true);
      server.close(force: true);
    });

    Future<String?> fetch() => HttpOverrides.runZoned(
      () => pinnedUpdateCheckFetch(uri),
      createHttpClient: (_) => _LocalRedirectClient(realClient, server.port),
    );

    test('200 OK levert de body als tekst', () async {
      server.listen((req) {
        req.response.statusCode = 200;
        req.response.write('{"tag_name":"v9.9.9"}');
        req.response.close();
      });

      expect(await fetch(), '{"tag_name":"v9.9.9"}');
    });

    test('non-200 is geen uitslag', () async {
      server.listen((req) {
        req.response.statusCode = 404;
        req.response.close();
      });

      expect(await fetch(), isNull);
    });

    test('een redirect wordt niet gevolgd', () async {
      server.listen((req) {
        req.response.statusCode = 302;
        req.response.headers.set('location', 'https://evil.invalid/');
        req.response.close();
      });

      // followRedirects staat uit: een 3xx is geen succes en mag de
      // hostcontrole niet omzeilen — geen uitslag, geen omweg.
      expect(await fetch(), isNull);
    });

    test('een body boven de kap wordt afgebroken', () async {
      server.listen((req) {
        req.response.statusCode = 200;
        final chunk = List<int>.filled(64 * 1024, 0x41);
        req.response.add(chunk);
        req.response.add(chunk);
        req.response.close();
      });

      expect(await fetch(), isNull);
    });
  });
}
