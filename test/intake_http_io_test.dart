@TestOn('vm')
library;

// De echte HTTP-laag van het inzendverkeer (`intake_http_io.dart`): wat er vóór een socket
// wordt geweigerd, en — via een lokale server waarheen de socket wordt omgeleid — wat er
// onderweg gebeurt. Zie cve_transport_io_test.dart voor de opzet: de NetGuard-controle draait
// gewoon op het opgegeven publieke adres (8.8.8.8 lost zonder opzoeking op), alleen de socket zelf
// gaat naar de lokale server.

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form/intake/intake_http.dart';
import 'package:ocideck/services/form/intake/intake_http_factory.dart';
import 'package:ocideck/services/form/intake/intake_http_io.dart'
    hide createIntakeHttp;

class _LocalRedirectClient implements HttpClient {
  _LocalRedirectClient(this._real, this._port);

  final HttpClient _real;
  final int _port;
  String? userAgentSet = 'niet gezet';

  @override
  set connectionFactory(_) {}

  @override
  set connectionTimeout(Duration? v) => _real.connectionTimeout = v;

  @override
  set userAgent(String? v) {
    userAgentSet = v;
    _real.userAgent = v;
  }

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

Future<IntakeHttpFailure> failureOf(Future<Object?> call) async {
  try {
    await call;
  } on IntakeHttpException catch (e) {
    return e.failure;
  }
  fail('er kwam geen IntakeHttpException');
}

void main() {
  const transport = PinnedIntakeHttp();

  test('de fabriek levert de gepinde laag op dit platform', () {
    expect(createIntakeHttp(), isA<PinnedIntakeHttp>());
  });

  group('geweigerd vóór er een socket opengaat', () {
    Future<IntakeHttpFailure> refusal(String url, {int max = 1024}) =>
        failureOf(
          transport.send(
            method: 'GET',
            url: Uri.parse(url),
            maxResponseBytes: max,
            timeout: const Duration(seconds: 5),
          ),
        );

    test('alles behalve https', () async {
      for (final url in const [
        'http://8.8.8.8/v1/info',
        'ftp://8.8.8.8/x',
        'file:///etc/passwd',
        'wss://8.8.8.8/x',
      ]) {
        expect(
          await refusal(url),
          IntakeHttpFailure.requestRefused,
          reason: url,
        );
      }
    });

    test('een poort die een uitnodiging niet mag noemen', () async {
      for (final port in [22, 25, 3306, 9999, 65535]) {
        expect(
          await refusal('https://8.8.8.8:$port/v1/info'),
          IntakeHttpFailure.requestRefused,
          reason: '$port',
        );
      }
    });

    test('de poorten die wel mogen komen voorbij die controle', () async {
      // Ze stranden pas op de host, niet op de poort.
      for (final url in const [
        'https://127.0.0.1/x',
        'https://127.0.0.1:443/x',
        'https://127.0.0.1:8443/x',
        'https://127.0.0.1:8080/x',
      ]) {
        expect(await refusal(url), IntakeHttpFailure.hostRefused, reason: url);
      }
    });

    test('een begrenzing die nergens op slaat', () async {
      expect(
        await refusal('https://8.8.8.8/x', max: 0),
        IntakeHttpFailure.requestRefused,
      );
      expect(
        await refusal('https://8.8.8.8/x', max: -1),
        IntakeHttpFailure.requestRefused,
      );
      expect(
        await refusal(
          'https://8.8.8.8/x',
          max: PinnedIntakeHttp.absoluteMaxResponseBytes + 1,
        ),
        IntakeHttpFailure.requestRefused,
      );
    });

    test(
      'het plafond is 130 MiB: ruimte voor een verzegeld pakket van 120 MiB',
      () {
        expect(PinnedIntakeHttp.absoluteMaxResponseBytes, 130 * 1024 * 1024);
      },
    );

    test('loopback, privé en link-local worden geweigerd', () async {
      for (final url in const [
        'https://localhost/x',
        'https://sub.localhost/x',
        'https://127.0.0.1/x',
        'https://[::1]/x',
        'https://10.1.2.3/x',
        'https://192.168.1.1/x',
        'https://172.16.0.1/x',
        'https://169.254.169.254/latest/meta-data/',
        'https://[::ffff:169.254.169.254]/x',
      ]) {
        expect(await refusal(url), IntakeHttpFailure.hostRefused, reason: url);
      }
    });

    test('een naam die nergens op uitkomt', () async {
      expect(
        await refusal('https://nergens.invalid/x'),
        IntakeHttpFailure.hostRefused,
      );
    });
  });

  group('onderweg', () {
    late HttpServer server;
    late HttpClient realClient;
    late _LocalRedirectClient wrapper;
    final uri = Uri.parse('https://8.8.8.8/v1/info');

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      realClient = HttpClient();
      wrapper = _LocalRedirectClient(realClient, server.port);
    });

    tearDown(() {
      realClient.close(force: true);
      server.close(force: true);
    });

    Future<IntakeHttpResponse> send({
      String method = 'GET',
      Map<String, String> headers = const {},
      List<int>? body,
      int max = 1024,
      Duration timeout = const Duration(seconds: 5),
      Uri? url,
    }) => HttpOverrides.runZoned(
      () => transport.send(
        method: method,
        url: url ?? uri,
        headers: headers,
        body: body,
        maxResponseBytes: max,
        timeout: timeout,
      ),
      createHttpClient: (_) => wrapper,
    );

    test('geeft status, kleine koppen en de bytes terug', () async {
      server.listen((req) {
        req.response
          ..statusCode = 201
          ..headers.set('X-Eigen-Kop', 'waarde')
          ..add([1, 2, 3])
          ..close();
      });
      final r = await send();
      expect(r.statusCode, 201);
      expect(r.body, Uint8List.fromList([1, 2, 3]));
      expect(r.headers['x-eigen-kop'], 'waarde');
    });

    test('stuurt de koppen mee en geen User-Agent', () async {
      final seen = Completer<HttpRequest>();
      server.listen((req) {
        seen.complete(req);
        req.response.close();
      });
      await send(
        headers: const {'accept': 'application/json', 'intake-form': 'abc'},
      );
      final req = await seen.future;
      expect(req.headers.value('accept'), 'application/json');
      expect(req.headers.value('intake-form'), 'abc');
      expect(req.headers.value('user-agent'), isNull);
      expect(wrapper.userAgentSet, isNull);
    });

    test('stuurt een body met zijn lengte, niet in stukken', () async {
      final body = Uint8List.fromList(List.generate(5000, (i) => i % 251));
      final seen =
          Completer<
            ({int? length, String? encoding, List<int> bytes, String method})
          >();
      server.listen((req) async {
        final bytes = <int>[];
        await for (final chunk in req) {
          bytes.addAll(chunk);
        }
        seen.complete((
          length: req.contentLength,
          encoding: req.headers.value('transfer-encoding'),
          bytes: bytes,
          method: req.method,
        ));
        await req.response.close();
      });
      await send(method: 'PUT', body: body);
      final got = await seen.future;
      expect(got.method, 'PUT');
      expect(got.length, 5000);
      expect(got.encoding, isNull);
      expect(got.bytes, body);
    });

    test('een verzoek zonder body stuurt geen Content-Length', () async {
      final seen = Completer<int>();
      server.listen((req) {
        seen.complete(req.contentLength);
        req.response.close();
      });
      await send();
      expect(await seen.future, -1);
    });

    test('volgt een redirect niet: de 3xx komt gewoon terug', () async {
      var hits = 0;
      server.listen((req) {
        hits++;
        req.response
          ..statusCode = 302
          ..headers.set('location', 'https://10.0.0.1/geheim')
          ..close();
      });
      final r = await send();
      expect(r.statusCode, 302);
      expect(r.headers['location'], 'https://10.0.0.1/geheim');
      expect(hits, 1);
    });

    test('een antwoord boven de begrenzing: te groot', () async {
      server.listen((req) {
        req.response
          ..add(List.filled(2000, 7))
          ..close();
      });
      expect(
        await failureOf(send(max: 1000)),
        IntakeHttpFailure.responseTooLarge,
      );
    });

    test('een antwoord precies op de begrenzing mag', () async {
      server.listen((req) {
        req.response
          ..add(List.filled(1000, 7))
          ..close();
      });
      expect((await send(max: 1000)).body, hasLength(1000));
    });

    test('een begrenzing van één byte mag', () async {
      server.listen((req) {
        req.response
          ..add([9])
          ..close();
      });
      expect((await send(max: 1)).body, [9]);
    });

    test('een begrenzing van het plafond zelf mag', () async {
      server.listen((req) {
        req.response
          ..add([9])
          ..close();
      });
      expect(
        (await send(max: PinnedIntakeHttp.absoluteMaxResponseBytes)).body,
        [9],
      );
    });

    test(
      'een server die niet antwoordt: te traag, en de verbinding gaat dicht',
      () async {
        // De server neemt de verbinding over en kijkt wanneer de client hem sluit.
        final closed = Completer<void>();
        server.listen((req) async {
          final socket = await req.response.detachSocket(writeHeaders: false);
          socket.listen(
            (_) {},
            onDone: () => closed.complete(),
            onError: (_) => closed.complete(),
          );
        });
        expect(
          await failureOf(send(timeout: const Duration(milliseconds: 200))),
          IntakeHttpFailure.timeout,
        );
        // De client sluit zijn kant geforceerd; zonder dat bleef de verbinding open.
        await closed.future.timeout(const Duration(seconds: 5));
      },
    );

    test('een server die niet antwoordt: te traag', () async {
      server.listen((req) {});
      expect(
        await failureOf(send(timeout: const Duration(milliseconds: 200))),
        IntakeHttpFailure.timeout,
      );
    });

    test('een server die de verbinding afbreekt: netwerkfout', () async {
      server.listen((req) async {
        final socket = await req.response.detachSocket(writeHeaders: false);
        socket.destroy();
      });
      expect(await failureOf(send()), IntakeHttpFailure.network);
    });

    test('een server die er niet is: netwerkfout', () async {
      await server.close(force: true);
      expect(await failureOf(send()), IntakeHttpFailure.network);
    });
  });
}
