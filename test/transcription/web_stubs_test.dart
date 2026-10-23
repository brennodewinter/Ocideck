// De web-helften van de model- en engine-façades (#2512): op een platform
// zonder schijf en zonder subproces moeten ze eerlijk weigeren — absent,
// UnsupportedSource — in plaats van iets voor te wenden.
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/local_whisper_engine.dart';
import 'package:ocideck/services/transcription/local_whisper_engine_stub.dart'
    as engine_stub;
import 'package:ocideck/services/transcription/model_download.dart';
import 'package:ocideck/services/transcription/model_download_stub.dart'
    as download_stub;
import 'package:ocideck/services/transcription/model_store_stub.dart'
    as store_stub;
import 'package:ocideck/services/transcription/model_store.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';

void main() {
  const model = WhisperModel(
    id: 'test',
    fileName: 'ggml-test.bin',
    sha256: 'x',
    downloadBytes: 1,
    diskBytes: 1,
    tier: 'light',
  );

  group('modelstore-stub (web)', () {
    const store = store_stub.StubModelStore();

    test('elke toestand is afwezig; schrijfroutes weigeren zichtbaar', () {
      expect(store.stateOf(model), completion(ModelInstallState.absent));
      expect(store.verify(model), completion(isFalse));
      // De niet-async routes gooien synchron, niet als rejected Future.
      expect(store.directory, throwsA(isA<UnsupportedSource>()));
      expect(() => store.modelPath(model), throwsA(isA<UnsupportedSource>()));
      expect(() => store.delete(model), throwsA(isA<UnsupportedSource>()));
      expect(store.sweepPartials(), completes);
      expect(store_stub.createModelStore(), isA<store_stub.StubModelStore>());
    });
  });

  group('modeldownload-stub (web)', () {
    test('start eindigt met refused, nooit met een stille hang', () {
      final dl = download_stub.StubModelDownloader().start(
        model,
        const ModelStorePath('/tmp/x', true),
      );
      dl.cancel(); // moet veilig zijn
      expect(
        dl.done,
        throwsA(
          isA<ModelDownloadException>().having(
            (e) => e.failure,
            'failure',
            ModelDownloadFailure.refused,
          ),
        ),
      );
      expect(dl.progress, emitsDone);
    });
  });

  group('lokale-engine-stub (web)', () {
    test('status is eerlijk afwezig en transcribe weigert getypt', () async {
      final e = engine_stub.StubLocalWhisperEngine(model: model);
      expect(e.kind, EngineKind.local);
      final status = await e.status();
      expect(status.support, LocalEngineSupport.unsupportedArchitecture);
      expect(
        e.transcribe(
          const AudioRef('/tmp/a.wav'),
          const TranscriptionOptions(),
        ),
        throwsA(isA<UnsupportedSource>()),
      );
      expect(e.transcribeLive(const Stream.empty()), isNull);
      expect(
        engine_stub.createLocalWhisperEngine(model: model),
        isA<engine_stub.StubLocalWhisperEngine>(),
      );
    });
  });
}
