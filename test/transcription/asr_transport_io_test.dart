// Echte-sockettest voor de io-transporthelft (#2524): een loopback-
// HttpServer ontvangt het verzoek — pinning, redirectweigering,
// bytecap en abort lopen over een echte socket, niet over een fake.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/asr_transport_io.dart';

void main() {
  HttpServer? server;

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  /// Start een loopbackserver die [answer] elk verzoek laat beantwoorden;
  /// het ontvangen verzoek staat daarna in [seen].
  Future<({Uri base, List<HttpRequest> seen})> start(
    FutureOr<void> Function(HttpRequest req) answer,
  ) async {
    final seen = <HttpRequest>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server!.forEach((req) async {
        seen.add(req);
        await answer(req);
        await req.response.close();
      }),
    );
    return (base: Uri.parse('http://127.0.0.1:${server!.port}'), seen: seen);
  }

  test(
    'POST bereikt de server met headers en body, antwoord komt terug',
    () async {
      String? received;
      final t = await start((req) async {
        received = await utf8.decoder.bind(req).join();
        req.response.statusCode = 200;
        req.response.write('{"text":"goeiemorgen"}');
      });
      final h = const IoAsrTransport().send(
        method: 'POST',
        url: t.base.replace(path: '/inference'),
        strategy: AiResolveStrategy.loopbackDirect,
        headers: {'authorization': 'Bearer geheim', 'x-t': '1'},
        body: utf8.encode('--boundary-audio'),
      );
      final res = await h.done;
      expect(res.statusCode, 200);
      expect(res.body, contains('goeiemorgen'));
      final req = t.seen.single;
      expect(req.method, 'POST');
      expect(req.uri.path, '/inference');
      expect(req.headers.value('authorization'), 'Bearer geheim');
      expect(req.contentLength, utf8.encode('--boundary-audio').length);
      expect(received, '--boundary-audio');
    },
  );

  test('localhost als naam resolveert en pinnt naar loopback', () async {
    final t = await start((req) {
      req.response.write('{"text":"ok"}');
    });
    final h = const IoAsrTransport().send(
      method: 'GET',
      url: t.base.replace(host: 'localhost'),
      strategy: AiResolveStrategy.loopbackDirect,
      body: null,
    );
    expect((await h.done).statusCode, 200);
  });

  test(
    'een omleiding wordt niet gevolgd — de 3xx komt als antwoord terug',
    () async {
      var hits = 0;
      final t = await start((req) {
        hits++;
        req.response.statusCode = 302;
        req.response.headers.set('location', 'http://169.254.169.254/meta');
      });
      final h = const IoAsrTransport().send(
        method: 'GET',
        url: t.base,
        strategy: AiResolveStrategy.loopbackDirect,
        body: null,
      );
      expect((await h.done).statusCode, 302);
      expect(hits, 1); // geen tweede request richting de omleiding
    },
  );

  test('een te groot antwoord breekt af met een getypeerde fout', () async {
    final t = await start((req) {
      req.response.write('x' * 64);
    });
    final h = const IoAsrTransport(maxResponseBytes: 8).send(
      method: 'GET',
      url: t.base,
      strategy: AiResolveStrategy.loopbackDirect,
      body: null,
    );
    await expectLater(h.done, throwsA(isA<AsrRequestException>()));
  });

  test('cancel() breekt een lopend verzoek af als afgebroken', () async {
    final t = await start((req) async {
      // Antwoord bewust nooit — de test annuleert.
      await Completer<void>().future;
    });
    final h = const IoAsrTransport().send(
      method: 'POST',
      url: t.base,
      strategy: AiResolveStrategy.loopbackDirect,
      body: utf8.encode('audio'),
    );
    // Laat de request aankomen, breek dan af.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    h.cancel();
    await expectLater(
      h.done,
      throwsA(
        isA<AsrRequestException>().having(
          (e) => e.message,
          'message',
          'afgebroken',
        ),
      ),
    );
  });

  test('cancel() vóór openUrl laat done niet hangen', () async {
    final t = await start((req) {
      req.response.write('{}');
    });
    final h = const IoAsrTransport().send(
      method: 'POST',
      url: t.base,
      strategy: AiResolveStrategy.loopbackDirect,
      body: utf8.encode('x'),
    )..cancel();
    await expectLater(h.done, throwsA(isA<AsrRequestException>()));
  });

  for (final phase in ['headers', 'lege body', 'partiële body', 'druppels']) {
    test('totale deadline geldt tijdens $phase', () async {
      final release = Completer<void>();
      Timer? drip;
      var arrived = false;
      final t = await start((req) async {
        arrived = true;
        if (phase != 'headers') {
          req.response.bufferOutput = false;
          req.response.headers.chunkedTransferEncoding = true;
          if (phase != 'lege body') req.response.write('a');
          await req.response.flush();
          if (phase == 'druppels') {
            drip = Timer.periodic(const Duration(milliseconds: 20), (_) {
              req.response.write('a');
            });
          }
        }
        await release.future;
      });
      final h = const IoAsrTransport().send(
        method: 'GET',
        url: t.base,
        strategy: AiResolveStrategy.loopbackDirect,
        timeout: const Duration(milliseconds: 500),
      );
      try {
        await expectLater(
          h.done.timeout(const Duration(seconds: 5)),
          throwsA(
            isA<AsrRequestException>().having(
              (e) => e.message,
              'reden',
              'verbinding verliep',
            ),
          ),
        );
        expect(arrived, isTrue);
        // Herhaalde en late annulering mogen de terminale reden niet wijzigen.
        h.cancel();
        h.cancel();
      } finally {
        drip?.cancel();
        release.complete();
      }
    });
  }

  for (final cancel in [true, false]) {
    test('${cancel ? 'cancel' : 'deadline'} voltooit vóór trage DNS', () async {
      final resolved = Completer<InternetAddress>();
      final t = await start((req) => req.response.write('te laat'));
      final h = IoAsrTransport(resolve: (_, _) => resolved.future).send(
        method: 'GET',
        url: t.base,
        strategy: AiResolveStrategy.loopbackDirect,
        timeout: const Duration(milliseconds: 100),
      );
      final check = expectLater(
        h.done.timeout(const Duration(seconds: 5)),
        throwsA(
          isA<AsrRequestException>().having(
            (e) => e.message,
            'reden',
            cancel ? 'afgebroken' : 'verbinding verliep',
          ),
        ),
      );
      if (cancel) h.cancel();
      await check;
      resolved.complete(InternetAddress.loopbackIPv4);
      await Future<void>.delayed(Duration.zero);
      expect(t.seen, isEmpty, reason: 'late DNS mag geen verbinding starten');
    });
  }

  test('cancel tijdens partiële body sluit de publieke future', () async {
    final sent = Completer<void>();
    final release = Completer<void>();
    final t = await start((req) async {
      req.response.write('a');
      await req.response.flush();
      sent.complete();
      await release.future;
    });
    final h = const IoAsrTransport().send(
      method: 'GET',
      url: t.base,
      strategy: AiResolveStrategy.loopbackDirect,
    );
    final check = expectLater(
      h.done,
      throwsA(
        isA<AsrRequestException>().having(
          (e) => e.message,
          'reden',
          'afgebroken',
        ),
      ),
    );
    await sent.future;
    h.cancel();
    await check;
    release.complete();
  });

  test('publicGuarded weigert een loopback-adres al in de resolve', () async {
    final h = const IoAsrTransport().send(
      method: 'GET',
      url: Uri.parse('http://127.0.0.1:9/'),
      strategy: AiResolveStrategy.publicGuarded,
      body: null,
    );
    await expectLater(h.done, throwsA(isA<AsrRequestException>()));
  });
}
