// Het modelbeheer (#2512): downloads serialiseren, annuleren verandert de
// spiegel, en delete/refresh spiegelen wat op schijf staat — nooit andersom.
import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/model_download.dart';
import 'package:ocideck/services/transcription/model_download_io.dart';
import 'package:ocideck/services/transcription/model_store.dart';
import 'package:ocideck/services/transcription/model_store_io.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';
import 'package:ocideck/state/transcription_model_provider.dart';

void main() {
  late Directory temp;
  late IoModelStore store;

  final bytes = List<int>.generate(64, (i) => i);
  final model = WhisperModel(
    id: 'test',
    fileName: 'ggml-test.bin',
    sha256: sha256.convert(bytes).toString(),
    downloadBytes: bytes.length,
    diskBytes: bytes.length,
    tier: 'light',
  );

  ProviderContainer container(ModelDownloader downloader) => ProviderContainer(
    overrides: [
      transcriptionModelStoreProvider.overrideWithValue(store),
      transcriptionModelDownloaderProvider.overrideWithValue(downloader),
      whisperModelCatalogProvider.overrideWithValue([model]),
    ],
  );

  ModelDownloader downloaderServing(List<int> body) =>
      createTestModelDownloader(
        (url) async => ModelFetchResult(
          statusCode: 200,
          contentLength: body.length,
          body: Stream.value(body),
        ),
      );

  setUp(() {
    temp = Directory.systemTemp.createTempSync('modelmgr_test_');
    store = IoModelStore(root: temp);
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  test('de spiegel toont absent → downloading → present', () async {
    final c = container(downloaderServing(bytes));
    addTearDown(c.dispose);
    // De eerste status wordt async ververst; geef die een tick.
    await c.read(transcriptionModelManagerProvider.notifier).refresh();

    await c.read(transcriptionModelManagerProvider.notifier).download(model);
    final status = c.read(transcriptionModelManagerProvider)[model.id]!;
    expect(status.install, ModelInstallState.present);
    expect(status.downloading, isFalse);
  });

  test('een mislukte download laat failure en absent achter', () async {
    final c = container(
      createTestModelDownloader(
        (url) async => ModelFetchResult(
          statusCode: 200,
          contentLength: model.downloadBytes,
          body: Stream.value(List.filled(model.downloadBytes, 0)),
        ),
      ),
    );
    addTearDown(c.dispose);
    await c.read(transcriptionModelManagerProvider.notifier).download(model);
    final status = c.read(transcriptionModelManagerProvider)[model.id]!;
    expect(status.install, ModelInstallState.absent);
    expect(status.failure, ModelDownloadFailure.invalidHash);
    expect(File('${temp.path}/ggml-test.bin').existsSync(), isFalse);
  });

  test('delete haalt het model van schijf én uit de spiegel', () async {
    File('${temp.path}/ggml-test.bin').writeAsBytesSync(bytes);
    final c = container(downloaderServing(bytes));
    addTearDown(c.dispose);
    await c.read(transcriptionModelManagerProvider.notifier).refresh();
    expect(
      c.read(transcriptionModelManagerProvider)[model.id]?.install,
      ModelInstallState.present,
    );
    await c.read(transcriptionModelManagerProvider.notifier).delete(model);
    expect(
      c.read(transcriptionModelManagerProvider)[model.id]?.install,
      ModelInstallState.absent,
    );
  });

  test('cancel op een niet-actief model is rustig', () async {
    final c = container(downloaderServing(bytes));
    addTearDown(c.dispose);
    c.read(transcriptionModelManagerProvider.notifier).cancel(model);
  });

  test('een tweede download tijdens een lopende is een no-op', () async {
    final gate = Completer<void>();
    var fetches = 0;
    final fetchStarted = Completer<void>();
    final c = container(
      createTestModelDownloader((url) async {
        fetches++;
        fetchStarted.complete();
        return ModelFetchResult(
          statusCode: 200,
          contentLength: model.downloadBytes,
          body: Stream.fromFuture(gate.future.then((_) => bytes)),
        );
      }),
    );
    addTearDown(c.dispose);
    final mgr = c.read(transcriptionModelManagerProvider.notifier);
    final first = mgr.download(model);
    // Wacht tot de fetch echt draait: dan is _active gevuld en is de
    // downloading-vlag de poort die de tweede aanroep tegenhoudt.
    await fetchStarted.future;
    await mgr.download(model);
    mgr.cancel(model);
    gate.complete();
    await first;
    expect(fetches, 1);
    expect(
      c.read(transcriptionModelManagerProvider)[model.id]?.failure,
      ModelDownloadFailure.cancelled,
    );
  });
}
