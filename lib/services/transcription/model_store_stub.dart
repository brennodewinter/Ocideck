import 'transcription_errors.dart';
import 'model_store.dart';
import 'whisper_model.dart';

/// De modelopslag op platforms zonder schijf (web). Er valt daar niets te
/// bewaren of te toetsen — elke toestand is `absent` en elke schrijfactie
/// is `UnsupportedSource`, zodat de UI nooit een download aanbiedt die
/// nergens kan landen.
class StubModelStore implements TranscriptionModelStore {
  const StubModelStore();

  static const _unsupported = UnsupportedSource(
    'modelbeheer vraagt een bestandssysteem',
  );

  @override
  Future<ModelStorePath> directory() => throw _unsupported;

  @override
  Future<ModelStorePath> modelPath(WhisperModel model) => throw _unsupported;

  @override
  Future<ModelInstallState> stateOf(WhisperModel model) =>
      Future.value(ModelInstallState.absent);

  @override
  Future<bool> verify(WhisperModel model) => Future.value(false);

  @override
  Future<void> delete(WhisperModel model) => throw _unsupported;

  @override
  Future<void> sweepPartials() async {}
}

TranscriptionModelStore createModelStore() => const StubModelStore();
