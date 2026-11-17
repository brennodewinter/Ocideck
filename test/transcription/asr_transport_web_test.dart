@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/asr_transport_web.dart';

@JS('eval')
external JSAny? evaluate(JSString code);
@JS('globalThis')
external JSObject get global;

void installResponse(
  List<List<int>> chunks, {
  bool emptyBody = false,
  bool stall = false,
  bool fail = false,
  bool reuseBuffer = false,
}) {
  evaluate(
    '''
    globalThis.asrReads = 0;
    globalThis.asrCancels = 0;
    globalThis.asrReleases = 0;
    globalThis.asrSignal = null;
    globalThis.fetch = async (_, init) => {
      globalThis.asrSignal = init.signal;
      const chunks = ${jsonEncode(chunks)};
      const shared = new Uint8Array(1);
      const reader = {
        read: async () => {
          globalThis.asrReads++;
          if ($fail) throw new Error('controlled stream failure');
          if ($stall) return await new Promise((_, reject) => {
            init.signal.addEventListener('abort', () =>
              reject(new DOMException('aborted', 'AbortError')));
          });
          const next = chunks.shift();
          if (!next) return {done: true};
          if ($reuseBuffer) {
            shared[0] = next[0];
            return {done: false, value: shared};
          }
          return {done: false, value: new Uint8Array(next)};
        },
        cancel: async () => { globalThis.asrCancels++; },
        releaseLock: () => { globalThis.asrReleases++; }
      };
      return {status: 200, url: 'https://asr.invalid', headers: new Headers({'content-type': 'application/json'}),
        body: $emptyBody ? null : {getReader: () => reader},
        arrayBuffer: () => { throw new Error('unbounded read is forbidden'); }};
    };
  '''
        .toJS,
  );
}

int count(String name) => (global.getProperty(name.toJS) as JSNumber).toDartInt;
bool get aborted =>
    (evaluate('globalThis.asrSignal.aborted'.toJS) as JSBoolean).toDart;

AsrSendHandle send([int maximum = 8]) =>
    WebAsrTransport(maxResponseBytes: maximum).send(
      method: 'GET',
      url: Uri.parse('https://asr.invalid'),
      strategy: AiResolveStrategy.publicGuarded,
    );

void main() {
  setUp(() => evaluate('globalThis.savedAsrFetch = globalThis.fetch'.toJS));
  tearDown(() => evaluate('globalThis.fetch = globalThis.savedAsrFetch'.toJS));

  test('overschrijding stopt vóór bewaren en vóór een derde read', () async {
    installResponse([
      List.filled(6, 97),
      List.filled(6, 98),
      [99],
    ]);
    await expectLater(
      send().done,
      throwsA(
        isA<AsrRequestException>().having(
          (e) => e.message,
          'message',
          'respons groter dan het maximum',
        ),
      ),
    );
    expect(count('asrReads'), 2);
    expect(count('asrCancels'), 1);
    expect(count('asrReleases'), 1);
    expect(aborted, isTrue);
  });

  test('exact de grens en UTF-8 verdeeld over chunks blijven geldig', () async {
    installResponse([
      [104, 195],
      [169],
    ]);
    final response = await send(3).done;
    expect(response.body, 'hé');
    expect(response.statusCode, 200);
    expect(count('asrCancels'), 0);
    expect(count('asrReleases'), 1);
    expect(aborted, isFalse);
  });

  test('ontvangen chunks blijven niet als losse aliassen bewaard', () async {
    installResponse([
      [97],
      [98],
    ], reuseBuffer: true);
    expect((await send(2).done).body, 'ab');
  });

  test(
    'lege en ontbrekende responsebody blijven geldige lege antwoorden',
    () async {
      for (final empty in [false, true]) {
        installResponse([], emptyBody: empty);
        expect((await send().done).body, '');
      }
    },
  );

  test('annulering onderbreekt een wachtende streamread', () async {
    installResponse([], stall: true);
    final request = send();
    final failed = expectLater(
      request.done,
      throwsA(
        isA<AsrRequestException>().having(
          (e) => e.message,
          'message',
          'afgebroken',
        ),
      ),
    );
    await pumpEventQueue();
    request.cancel();
    await failed;
    expect(aborted, isTrue);
    expect(count('asrReleases'), 1);
  });

  test('een streamfout blijft een netwerkfout ondanks cleanup-abort', () async {
    installResponse([], fail: true);
    await expectLater(
      send().done,
      throwsA(
        isA<AsrRequestException>().having(
          (e) => e.message,
          'message',
          'netwerk',
        ),
      ),
    );
    expect(aborted, isTrue);
    expect(count('asrReleases'), 1);
  });
}
