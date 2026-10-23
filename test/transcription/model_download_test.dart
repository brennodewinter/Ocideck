// De bewaakte modeldownload (#2512): de transportpunt is geïnjecteerd,
// zodat redirect-beleid, omvangsgrens, annulering en de hash-eindtoets
// getoetst worden zonder het netwerk — NetGuard weigert loopback terecht.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/model_download.dart';
import 'package:ocideck/services/transcription/model_download_io.dart';
import 'package:ocideck/services/transcription/model_store.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';

void main() {
  late Directory temp;
  late ModelStorePath dest;

  final bytes = List<int>.generate(1024, (i) => i % 251);
  final model = WhisperModel(
    id: 'test',
    fileName: 'ggml-test.bin',
    sha256: sha256.convert(bytes).toString(),
    downloadBytes: bytes.length,
    diskBytes: bytes.length,
    tier: 'light',
  );

  /// Bouwt een fetch die [responses] achter elkaar serveert (één per hop)
  /// en de bezochte url's vastlegt.
  ({ModelFetch fetch, List<Uri> visited}) fetchWith(
    List<ModelFetchResult> responses,
  ) {
    final visited = <Uri>[];
    var i = 0;
    return (
      visited: visited,
      fetch: (url) async {
        visited.add(url);
        return responses[i++ % responses.length];
      },
    );
  }

  ModelFetchResult serve(List<int> body, {int status = 200, int? length}) =>
      ModelFetchResult(
        statusCode: status,
        contentLength: length ?? body.length,
        body: Stream.value(body),
      );

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('modeldl_test_');
    dest = ModelStorePath('${temp.path}/ggml-test.bin', true);
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  group('redirectbeleid', () {
    test('volgt een https-redirect naar een andere host', () async {
      final (fetch: fetch, visited: visited) = fetchWith([
        const ModelFetchResult(
          statusCode: 302,
          location: 'https://cdn.example.org/x.bin',
        ),
        serve(bytes),
      ]);
      final dl = createTestModelDownloader(fetch);
      await dl.start(model, dest).done;
      expect(visited.map((u) => u.host).toList(), [
        'huggingface.co',
        'cdn.example.org',
      ]);
      expect(await File(dest.path).readAsBytes(), bytes);
    });

    test('een http-redirect wordt geweigerd, nooit gevolgd', () async {
      final (fetch: fetch, visited: _) = fetchWith([
        const ModelFetchResult(
          statusCode: 302,
          location: 'http://intern.local/x.bin',
        ),
      ]);
      final dl = createTestModelDownloader(fetch);
      await expectLater(
        dl.start(model, dest).done,
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'failure',
            ModelDownloadFailure.refused,
          ),
        ),
      );
    });

    test('te veel hops is een weigering', () async {
      final (fetch: fetch, visited: _) = fetchWith([
        const ModelFetchResult(statusCode: 302, location: '/next'),
      ]);
      final dl = createTestModelDownloader(fetch);
      await expectLater(
        dl.start(model, dest).done,
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'failure',
            ModelDownloadFailure.refused,
          ),
        ),
      );
    });
  });

  group('omvang en hash', () {
    test(
      'een groeiende stream wordt bij de catalogusgrens afgebroken',
      () async {
        final (fetch: fetch, visited: _) = fetchWith([
          ModelFetchResult(
            statusCode: 200,
            contentLength: model.downloadBytes,
            // Kondigt de juiste omvang aan maar stuurt meer — precies het
            // geval waarvoor de grens bestaat.
            body: Stream.value(List.filled(model.downloadBytes + 1, 0)),
          ),
        ]);
        final dl = createTestModelDownloader(fetch);
        await expectLater(
          dl.start(model, dest).done,
          throwsA(
            isA<ModelDownloadException>().having(
              (e) => e.failure,
              'failure',
              ModelDownloadFailure.refused,
            ),
          ),
        );
        expect(await File('${dest.path}.part').exists(), isFalse);
      },
    );

    test('afwijkende hash: bestand weg, nooit geïnstalleerd', () async {
      final (fetch: fetch, visited: _) = fetchWith([
        serve(List.filled(model.downloadBytes, 0)),
      ]);
      final dl = createTestModelDownloader(fetch);
      await expectLater(
        dl.start(model, dest).done,
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'failure',
            ModelDownloadFailure.invalidHash,
          ),
        ),
      );
      expect(await File(dest.path).exists(), isFalse);
      expect(await File('${dest.path}.part').exists(), isFalse);
    });

    test('een Content-Length die niet klopt weigert vroeg', () async {
      final (fetch: fetch, visited: _) = fetchWith([
        ModelFetchResult(
          statusCode: 200,
          contentLength: model.downloadBytes + 1,
          body: Stream.value(bytes),
        ),
      ]);
      final dl = createTestModelDownloader(fetch);
      await expectLater(
        dl.start(model, dest).done,
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'failure',
            ModelDownloadFailure.refused,
          ),
        ),
      );
    });
  });

  group('voortgang en annulering', () {
    test('voortgang loopt mee met de bytes', () async {
      final (fetch: fetch, visited: _) = fetchWith([serve(bytes)]);
      final dl = createTestModelDownloader(fetch);
      final handle = dl.start(model, dest);
      final events = await handle.progress.toList();
      await handle.done;
      expect(
        events.any(
          (e) =>
              e.phase == ModelDownloadPhase.downloading &&
              e.received == model.downloadBytes,
        ),
        isTrue,
      );
      expect(events.last.phase, ModelDownloadPhase.verifying);
    });

    test('cancel breekt de transfer af en ruimt op', () async {
      final gate = Completer<void>();
      final (fetch: fetch, visited: _) = fetchWith([
        ModelFetchResult(
          statusCode: 200,
          contentLength: model.downloadBytes,
          // Een stream die pas levert als de test hem loslaat — annuleren
          // terwijl de eerste brok nog onderweg is.
          body: Stream.fromFuture(gate.future.then((_) => bytes)),
        ),
      ]);
      final dl = createTestModelDownloader(fetch);
      final handle = dl.start(model, dest);
      // Geef de runner een tick om de fetch te starten.
      await Future<void>.delayed(Duration.zero);
      handle.cancel();
      gate.complete();
      await expectLater(
        handle.done,
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'failure',
            ModelDownloadFailure.cancelled,
          ),
        ),
      );
      expect(await File('${dest.path}.part').exists(), isFalse);
    });

    test(
      'een tweede identieke download overschrijft het deelbestand',
      () async {
        // Simuleert een afgebroken eerdere poging: er ligt een .part.
        await File('${dest.path}.part').writeAsBytes([9, 9, 9]);
        final (fetch: fetch, visited: _) = fetchWith([serve(bytes)]);
        final dl = createTestModelDownloader(fetch);
        await dl.start(model, dest).done;
        expect(await File(dest.path).readAsBytes(), bytes);
        expect(await File('${dest.path}.part').exists(), isFalse);
      },
    );
  });
}
