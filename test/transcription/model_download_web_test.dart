@TestOn('browser')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:web/web.dart' as web;
import 'package:ocideck/services/transcription/model_download.dart';
import 'package:ocideck/services/transcription/model_download_web.dart';
import 'package:ocideck/services/transcription/model_store.dart';
import 'package:ocideck/services/transcription/model_store_web.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';

@JS('eval')
external JSAny? evaluate(JSString code);

@JS('globalThis.cancelModelDownload')
external set cancelModelDownload(JSFunction? value);

const key = 'models/ocideck-regression-2953.bin';
const model = WhisperModel(
  id: 'test',
  fileName: 'test.bin',
  sha256: '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
  downloadBytes: 3,
  diskBytes: 3,
  tier: 'test',
);

void install(
  List<List<int>> chunks, {
  String? length,
  String? encoding,
  bool stallFetch = false,
  bool stallRead = false,
  bool reuse = false,
  int delay = 0,
}) {
  evaluate(
    '''
    globalThis.modelReads = 0;
    globalThis.modelCancels = 0;
    globalThis.modelReleases = 0;
    globalThis.modelSignal = null;
    globalThis.fetch = async (_, init) => {
      globalThis.modelSignal = init.signal;
      if ($stallFetch) return new Promise((_, reject) => init.signal.addEventListener('abort',
        () => reject(new DOMException('aborted', 'AbortError'))));
      const chunks = ${jsonEncode(chunks)};
      const shared = new Uint8Array(1);
      const reader = {
        read: async () => {
          modelReads++;
          if ($stallRead) return new Promise((_, reject) => init.signal.addEventListener('abort',
            () => reject(new DOMException('aborted', 'AbortError'))));
          if ($delay) await new Promise(resolve => setTimeout(resolve, $delay));
          const next = chunks.shift();
          if (!next) return {done: true};
          if ($reuse) { shared[0] = next[0]; return {done: false, value: shared}; }
          return {done: false, value: new Uint8Array(next)};
        },
        cancel: async () => { modelCancels++; },
        releaseLock: () => { modelReleases++; }
      };
      return {ok: true, status: 200, type: 'basic',
        headers: {get: name => name === 'content-length' ? ${jsonEncode(length)} :
          name === 'content-encoding' ? ${jsonEncode(encoding)} : null},
        body: {getReader: () => reader}};
    };
  '''
        .toJS,
  );
}

int count(String expression) =>
    (evaluate(expression.toJS) as JSNumber).toDartInt;

ModelDownload start({
  Duration total = const Duration(seconds: 10),
  Duration idle = const Duration(seconds: 2),
}) => WebModelDownloader(
  totalTimeout: total,
  idleTimeout: idle,
).start(model, const ModelStorePath(key, false));

Future<void> refused(ModelDownload download) async {
  await expectLater(
    download.done,
    throwsA(
      isA<ModelDownloadException>().having(
        (e) => e.failure,
        'reden',
        ModelDownloadFailure.networkFailed,
      ),
    ),
  );
  expect(await readModelRecord(key), isNull);
  expect((await listModelKeys()).where((k) => k.startsWith(key)), isEmpty);
  expect(evaluate('modelSignal.aborted'.toJS).dartify(), isTrue);
}

void main() {
  setUp(() async {
    evaluate(
      '''
      globalThis.savedModelFetch = globalThis.fetch;
      globalThis.savedEstimate = navigator.storage.estimate;
      globalThis.savedModelPut = IDBObjectStore.prototype.put;
      globalThis.savedModelDelete = IDBObjectStore.prototype.delete;
      globalThis.savedModelDigest = crypto.subtle.digest;
      navigator.storage.estimate = async () => ({quota: 1000000000, usage: 0});
    '''
          .toJS,
    );
    await deleteModelRecord(key);
  });
  tearDown(() async {
    evaluate(
      '''
      globalThis.fetch = savedModelFetch;
      navigator.storage.estimate = savedEstimate;
      IDBObjectStore.prototype.put = savedModelPut;
      IDBObjectStore.prototype.delete = savedModelDelete;
      crypto.subtle.digest = savedModelDigest;
    '''
          .toJS,
    );
    for (final item in await listModelKeys()) {
      if (item.startsWith(key)) await deleteModelRecord(item);
    }
  });

  test(
    'eerste te grote chunk stopt vóór opslaan en vóór een derde read',
    () async {
      install([
        [1, 2, 3],
        [4, 5, 6],
        [7, 8, 9],
      ]);
      final download = start();
      final progress = download.progress.toList();
      await refused(download);
      expect(count('modelReads'), 2);
      expect(count('modelCancels'), 1);
      expect(count('modelReleases'), 1);
      expect((await progress).every((p) => p.received <= 3), isTrue);
    },
  );

  test('afwijkende vergelijkbare Content-Length weigert vóór lezen', () async {
    install([
      [1, 2, 3],
    ], length: '9');
    await refused(start());
    expect(count('modelReads'), 0);
  });

  for (final encoded in [false, true]) {
    test(
      'geldige download ${encoded ? 'met transportcompressie' : 'zonder lengte'}',
      () async {
        install(
          [
            [1],
            [2],
            [3],
          ],
          length: encoded ? '9' : null,
          encoding: encoded ? 'gzip' : null,
          reuse: true,
        );
        final download = start();
        expect((await download.done).path, key);
        expect(await readModelRecord(key), [1, 2, 3]);
        expect(count('modelReleases'), 1);
        expect(count('modelCancels'), 0);
        expect((await listModelKeys()).where((k) => k.startsWith(key)), [key]);
      },
    );
  }

  test('te korte EOF installeert niets', () async {
    install([
      [1],
    ]);
    await refused(start());
  });

  test('hangende fetch eindigt door idle-deadline', () async {
    install([], stallFetch: true);
    await refused(start(idle: const Duration(milliseconds: 30)));
  });

  test('hangende reader wordt afgebroken en vrijgegeven', () async {
    install([], stallRead: true);
    await refused(start(idle: const Duration(milliseconds: 30)));
    expect(count('modelCancels'), 1);
    expect(count('modelReleases'), 1);
  });

  test('druppelende data reset de totale deadline niet', () async {
    install([
      [1],
      [2],
      [3],
    ], delay: 20);
    await refused(start(total: const Duration(milliseconds: 35)));
    expect(count('modelReads'), lessThan(4));
  });
  Future<void> cancelled(ModelDownload download) async {
    await expectLater(
      download.done,
      throwsA(
        isA<ModelDownloadException>().having(
          (e) => e.failure,
          'reden',
          ModelDownloadFailure.cancelled,
        ),
      ),
    );
    expect(await readModelRecord(key), [9, 8, 7]);
    expect((await listModelKeys()).where((k) => k.startsWith(key)), [key]);
  }

  Future<void> until(bool Function() condition) async {
    for (var i = 0; i < 200 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(condition(), isTrue);
  }

  test('annuleren bij verifying behoudt de vorige installatie', () async {
    await writeModelRecord(key, Uint8List.fromList([9, 8, 7]));
    install([
      [1, 2, 3],
    ]);
    final download = start();
    final sub = download.progress.listen((p) {
      if (p.phase == ModelDownloadPhase.verifying) download.cancel();
    });
    await cancelled(download);
    await sub.cancel();
  });

  test('annuleren tijdens ontvangen bewaart het vorige model', () async {
    await writeModelRecord(key, Uint8List.fromList([9, 8, 7]));
    install([
      [1],
      [2],
      [3],
    ]);
    final download = start();
    final sub = download.progress.listen((p) {
      if (p.phase == ModelDownloadPhase.downloading) download.cancel();
    });
    await cancelled(download);
    await sub.cancel();
    expect((await start().done).path, key);
    expect(await readModelRecord(key), [1, 2, 3]);
  });

  for (final quotaCall in [1, 2]) {
    test(
      'annuleren tijdens quota-opvraag $quotaCall installeert niets',
      () async {
        await writeModelRecord(key, Uint8List.fromList([9, 8, 7]));
        install([
          [1, 2, 3],
        ]);
        evaluate(
          '''
        globalThis.modelQuotaCalls = 0;
        globalThis.releaseModelQuota = null;
        navigator.storage.estimate = async () => {
          if (++modelQuotaCalls === $quotaCall) return new Promise(resolve => {
            releaseModelQuota = () => resolve({quota: 1000000000, usage: 0});
          });
          return {quota: 1000000000, usage: 0};
        };
      '''
              .toJS,
        );
        final download = start();
        await until(
          () =>
              evaluate(
                'typeof releaseModelQuota === "function"'.toJS,
              ).dartify() ==
              true,
        );
        download.cancel();
        evaluate('releaseModelQuota()'.toJS);
        await cancelled(download);
        if (quotaCall == 1) expect(count('modelReads'), 0);
      },
    );
  }

  for (final part in [true, false]) {
    test(
      'cancel tijdens ${part ? 'part-write' : 'finale transactie'} behoudt oud record',
      () async {
        await writeModelRecord(key, Uint8List.fromList([9, 8, 7]));
        install([
          [1, 2, 3],
        ]);
        evaluate(
          '''
        IDBObjectStore.prototype.put = function(...args) {
          const result = savedModelPut.apply(this, args);
          const key = String(args[1]);
          if (${part ? "key.startsWith('$key.') && key.endsWith('.part')" : "key === '$key'"}) {
            cancelModelDownload();
          }
          return result;
        };
      '''
              .toJS,
        );
        final download = start();
        cancelModelDownload = download.cancel.toJS;
        await cancelled(download);
      },
    );
  }

  test(
    'cancel tijdens WebCrypto-verificatie voorkomt definitieve write',
    () async {
      await writeModelRecord(key, Uint8List.fromList([9, 8, 7]));
      install([
        [1, 2, 3],
      ]);
      evaluate(
        '''
      crypto.subtle.digest = function(...args) {
        return savedModelDigest.apply(this, args).then(result => {
          cancelModelDownload(); return result;
        });
      };
    '''
            .toJS,
      );
      final download = start();
      cancelModelDownload = download.cancel.toJS;
      await cancelled(download);
    },
  );

  test('installatie controleert opnieuw na database-openen', () async {
    await writeModelRecord(key, Uint8List.fromList([9, 8, 7]));
    final opened = Completer<web.IDBDatabase>();
    final cancellation = ModelInstallCancellation();
    final future = installModelRecord(
      key,
      Uint8List.fromList([1, 2, 3]),
      cancellation,
      openDatabase: () => opened.future,
    );
    cancellation.cancel();
    opened.complete(await openModelDb());
    expect(await future, isFalse);
    expect(await readModelRecord(key), [9, 8, 7]);
  });

  test('cancel na transaction-complete verandert succes niet', () async {
    install([
      [1, 2, 3],
    ]);
    evaluate(
      '''
      IDBObjectStore.prototype.delete = function(...args) {
        if (String(args[0]).startsWith('$key.')) cancelModelDownload();
        return savedModelDelete.apply(this, args);
      };
    '''
          .toJS,
    );
    final download = start();
    cancelModelDownload = download.cancel.toJS;
    expect((await download.done).path, key);
    download.cancel();
    expect(await readModelRecord(key), [1, 2, 3]);
  });

  test(
    'oude cleanup raakt een nieuwere download naar dezelfde sleutel niet',
    () async {
      await writeModelRecord(key, Uint8List.fromList([9, 8, 7]));
      install([
        [1, 2, 3],
      ]);
      evaluate(
        '''
      globalThis.modelDigestCalls = 0;
      globalThis.releaseFirstModelHash = null;
      crypto.subtle.digest = function(...args) {
        const real = savedModelDigest.apply(this, args);
        if (++modelDigestCalls === 1) return real.then(result => new Promise(resolve => {
          releaseFirstModelHash = () => resolve(result);
        }));
        return real;
      };
    '''
            .toJS,
      );
      final first = start();
      final failure = expectLater(
        first.done,
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'reden',
            ModelDownloadFailure.cancelled,
          ),
        ),
      );
      await until(
        () =>
            evaluate(
              'typeof releaseFirstModelHash === "function"'.toJS,
            ).dartify() ==
            true,
      );
      expect((await start().done).path, key);
      first.cancel();
      evaluate('releaseFirstModelHash()'.toJS);
      await failure;
      expect(await readModelRecord(key), [1, 2, 3]);
      expect((await listModelKeys()).where((k) => k.startsWith(key)), [key]);
    },
  );
}
