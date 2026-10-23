import 'capture_source.dart' show AudioChunk;
import 'local_whisper_engine.dart';
import 'transcription_engine.dart';
import 'transcription_errors.dart';
import 'whisper_model.dart';

/// De lokale engine op platforms zonder subproces (web). De route bestaat
/// er niet — `status()` zegt dat eerlijk en `transcribe` weigert in plaats
/// van iets voor te wenden. De echte webengine is #2513.
class StubLocalWhisperEngine implements LocalWhisperEngine {
  StubLocalWhisperEngine({this.model});

  @override
  final WhisperModel? model;

  @override
  EngineKind get kind => EngineKind.local;

  @override
  Future<LocalEngineStatus> status() => Future.value(
    const LocalEngineStatus(
      LocalEngineSupport.unsupportedArchitecture,
      'geen lokale spraakengine op dit platform',
    ),
  );

  @override
  Future<EngineCapabilities> capabilities() =>
      Future.value(EngineCapabilities(requiresModel: model?.id));

  @override
  void cancel() {}

  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) => Future.error(
    const UnsupportedSource('geen lokale spraakengine op dit platform'),
  );

  @override
  Stream<PartialTranscript>? transcribeLive(Stream<AudioChunk> chunks) => null;
}

LocalWhisperEngine createLocalWhisperEngine({WhisperModel? model}) =>
    StubLocalWhisperEngine(model: model);
