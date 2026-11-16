@TestOn('browser')
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/asr_live_limits.dart';
import 'package:ocideck/services/transcription/asr_live_transport.dart';
import 'package:ocideck/services/transcription/asr_live_transport_web.dart';

@JS('eval')
external JSAny? evaluate(JSString code);
@JS('globalThis')
external JSObject get global;

void deliver(String expression) =>
    evaluate('globalThis.asrSocket.onmessage({data: $expression})'.toJS);

Future<AsrLiveSocket> connect({int queuedBytes = 32}) =>
    WebAsrLiveTransport(
      limits: LiveResponseLimits(messageBytes: 8, queuedBytes: queuedBytes),
    ).connect(
      url: Uri.parse('wss://asr.invalid'),
      strategy: AiResolveStrategy.publicGuarded,
    );

void main() {
  setUp(() {
    evaluate(
      '''
      globalThis.savedAsrWebSocket = globalThis.WebSocket;
      globalThis.asrCloses = 0;
      globalThis.WebSocket = class {
        static OPEN = 1;
        constructor() {
          globalThis.asrSocket = this;
          this.readyState = 0;
          setTimeout(() => { this.readyState = 1; this.onopen({}); }, 0);
        }
        send(_) {}
        close() {
          this.readyState = 3;
          globalThis.asrCloses++;
          this.onclose({code: 1000});
        }
      };
    '''
          .toJS,
    );
  });
  tearDown(
    () => evaluate('globalThis.WebSocket = globalThis.savedAsrWebSocket'.toJS),
  );

  for (final expression in [
    "'123456789'",
    'new Uint8Array(9).buffer',
    "'ééééé'",
  ]) {
    test('browsertransport begrenst $expression en sluit eenmaal', () async {
      final socket = await connect();
      final failed = expectLater(
        socket.messages,
        emitsError(isA<LiveResponseLimitExceeded>()),
      );
      deliver(expression);
      await failed;
      expect((global.getProperty('asrCloses'.toJS) as JSNumber).toDartInt, 1);
      await socket.close();
    });
  }

  test('gewone tekst en exact de binaire grens blijven behouden', () async {
    final socket = await connect();
    final frames = <Object>[];
    final done = Completer<void>();
    socket.messages.listen(frames.add, onDone: done.complete);
    deliver("'éé'");
    deliver('new Uint8Array([1,2,3,4,5,6,7,8]).buffer');
    await socket.close();
    await done.future;
    expect(frames[0], 'éé');
    expect(frames[1], [1, 2, 3, 4, 5, 6, 7, 8]);
  });

  test(
    'pauzeren verschuift onbegrensde groei niet naar de browserqueue',
    () async {
      final socket = await connect(queuedBytes: 4);
      final frames = <Object>[];
      final errors = <Object>[];
      final done = Completer<void>();
      final sub = socket.messages.listen(
        frames.add,
        onError: errors.add,
        onDone: done.complete,
      )..pause();
      deliver("'abcd'");
      deliver("'e'");
      sub.resume();
      await done.future;
      expect(frames, ['abcd']);
      expect(errors.single, isA<LiveResponseLimitExceeded>());
      await socket.close();
    },
  );
}
