// Echte-sockettest voor de io-live-transporthelft (#2525): een loopback-
// HttpServer upgrade naar een echte WebSocket — pinning, headers en
// frames lopen over echte bytes, niet over een fake.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/asr_live_transport.dart';
import 'package:ocideck/services/transcription/asr_live_transport_io.dart';
import 'package:ocideck/services/transcription/asr_live_transport_stub.dart'
    as stub;

void main() {
  HttpServer? server;

  tearDown(() async {
    await server?.close(force: true);
    server = null;
  });

  /// Start een loopbackserver die elke upgrade aanvaardt; het verzoek en
  /// de binnenkomende frames staan voor de test klaar.
  Future<({Uri url, List<HttpRequest> seen, List<dynamic> frames})>
  start() async {
    final seen = <HttpRequest>[];
    final frames = <dynamic>[];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(
      server!.forEach((req) async {
        seen.add(req);
        if (WebSocketTransformer.isUpgradeRequest(req)) {
          final ws = await WebSocketTransformer.upgrade(req);
          ws.listen((frame) {
            frames.add(frame);
            // Elk inkomend frame krijgt een protocolantwoord terug —
            // zo is de inkomende richting écht te testen.
            ws.add('{"partial":"echo"}');
          });
        } else {
          req.response.statusCode = 404;
          await req.response.close();
        }
      }),
    );
    return (
      url: Uri.parse('ws://127.0.0.1:${server!.port}'),
      seen: seen,
      frames: frames,
    );
  }

  test(
    'handshake met headers, frames heen en weer over de gepinde socket',
    () async {
      final t = await start();
      final socket = await const IoAsrLiveTransport().connect(
        url: t.url,
        strategy: AiResolveStrategy.loopbackDirect,
        headers: {'authorization': 'Bearer geheim'},
      );

      // De handshake bereikte de server, met de sleutel in de header.
      expect(t.seen.single.headers.value('authorization'), 'Bearer geheim');
      expect(
        t.seen.single.headers.value('upgrade')?.toLowerCase(),
        'websocket',
      );

      // Tekst- en binair frame komen bij de server aan.
      socket.sendText('{"config":{}}');
      socket.sendBytes(Uint8List.fromList([1, 2, 3]));
      await pumpEventQueue();
      expect(t.frames, contains('{"config":{}}'));
      expect(
        t.frames.any(
          (f) => f is List<int> && f.length == 3 && f[0] == 1 && f[2] == 3,
        ),
        isTrue,
      );

      await socket.close();
    },
  );

  test('inkomende frames landen op de berichtenstroom', () async {
    final t = await start();
    final socket = await const IoAsrLiveTransport().connect(
      url: t.url,
      strategy: AiResolveStrategy.loopbackDirect,
    );
    final first = socket.messages.first;
    socket.sendText('{"config":{}}');
    // De server antwoordt op elk frame met een protocolboodschap — die
    // komt als String binnen.
    expect(await first, '{"partial":"echo"}');
    await socket.close();
    // De gate-URL bleef kaal: geen token in de draad-adressering.
    expect(t.seen.single.uri.toString(), isNot(contains('token')));
  });

  test('een dichte poort is een getypte AsrLiveException', () async {
    // Poort 1 is aantoonbaar dicht — connect mag nooit op een vage
    // platformfout uitkomen.
    expect(
      const IoAsrLiveTransport().connect(
        url: Uri.parse('ws://127.0.0.1:1'),
        strategy: AiResolveStrategy.loopbackDirect,
      ),
      throwsA(isA<AsrLiveException>()),
    );
  });

  test('de stub-helft weigert getypt', () {
    expect(
      () => const stub.StubAsrLiveTransport().connect(
        url: Uri.parse('ws://127.0.0.1:1'),
        strategy: AiResolveStrategy.loopbackDirect,
      ),
      throwsA(isA<AsrLiveException>()),
    );
  });
}
