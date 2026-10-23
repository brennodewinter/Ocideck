import 'model_download.dart';
import 'model_store.dart';
import 'whisper_model.dart';

/// Er is geen modelopslag op platforms zonder schijf, dus ook geen
/// downloader. `start` weigert zichtbaar — stil niets doen zou de UI een
/// eeuwig "bezig"-symbool geven.
class StubModelDownloader implements ModelDownloader {
  const StubModelDownloader();

  @override
  ModelDownload start(WhisperModel model, ModelStorePath destination) =>
      _StubModelDownload();
}

class _StubModelDownload implements ModelDownload {
  @override
  Stream<ModelDownloadProgress> get progress => const Stream.empty();

  @override
  Future<ModelStorePath> get done => Future.error(
    const ModelDownloadException(
      ModelDownloadFailure.refused,
      'modeldownloads vragen een bestandssysteem',
    ),
  );

  @override
  void cancel() {}
}

ModelDownloader createModelDownloader() => const StubModelDownloader();
