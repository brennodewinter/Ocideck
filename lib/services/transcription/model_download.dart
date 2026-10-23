// Het binnenhalen van een catalogusmodel — de enige nieuwe netwerkuitgang
// die #2512 toevoegt (docs/design/TRANSCRIPTION.md §4.4).
//
// De regels die hier gelden:
//  * downloads starten alleen op een expliciete gebruikerskeuze — niets in
//    deze laag vraagt zelf om toestemming of begint vanzelf;
//  * alle egress loopt door `NetGuard`: elke hop wordt opnieuw opgelost en
//    de socket vastgezet, want `resolve/…` op huggingface.co redirect naar
//    de CDN en een ongecontroleerde 3xx is een SSRF-deur;
//  * de bestemming komt uit de modelopslag met zijn containment-poort;
//  * er wordt naar `<naam>.part` geschreven en pas na een geslaagde
//    SHA-256-controle hernoemd — een `.part` is bewijs van "niet af", nooit
//    van "geïnstalleerd";
//  * annuleren of falen ruimt het deelbestand op.
//
// De facade deelt de statussen en het resultaat; `_io` draagt het
// transport en `_stub` het weglaten ervan op platforms zonder schijf.
import 'model_download_stub.dart'
    if (dart.library.io) 'model_download_io.dart'
    as impl;

import 'model_store.dart';
import 'whisper_model.dart';

/// Waar een lopende download staat — de UI vertaalt dit, de kern niet.
enum ModelDownloadPhase { connecting, downloading, verifying }

/// Voortgang: [received] bytes binnen van de aangekondigde [total]
/// (`Content-Length`, of 0 als de server hem niet stuurde).
class ModelDownloadProgress {
  const ModelDownloadProgress(this.phase, this.received, this.total);

  final ModelDownloadPhase phase;
  final int received;
  final int total;
}

/// Waarom een download strandde. `cancelled` is de eigen keuze van de
/// gebruiker; `invalidHash` betekent dat het netwerk iets anders leverde
/// dan de catalogus belooft — dat is een beveiligingsmelding, geen hik.
enum ModelDownloadFailure {
  cancelled,
  networkFailed,
  refused,
  invalidHash,
  ioFailed,
}

class ModelDownloadException implements Exception {
  const ModelDownloadException(this.failure, [this.detail = '']);

  final ModelDownloadFailure failure;
  final String detail;

  @override
  String toString() => 'ModelDownloadException($failure, $detail)';
}

/// Een lopende (of net afgesloten) download. [cancel] is idempotent.
abstract class ModelDownload {
  /// Voortgang tot het einde van de byteslus, daarna `verifying`.
  Stream<ModelDownloadProgress> get progress;

  /// Voltooit met het pad van het geïnstalleerde model, of met een
  /// [ModelDownloadException].
  Future<ModelStorePath> get done;

  /// Breekt de transfer af en ruimt het deelbestand op.
  void cancel();
}

/// Haalt catalogusmodellen binnen. Eén tegelijk per aanroep is bewust —
/// de provider serialiseert, zodat twee knoppen nooit om dezelfde `.part`
/// vechten.
abstract class ModelDownloader {
  /// Start een download naar de plek die [TranscriptionModelStore.modelPath]
  /// opleverde. De store blijft eigenaar van het eindpad; de downloader mag
  /// er alleen via `.part` naartoe.
  ModelDownload start(WhisperModel model, ModelStorePath destination);
}

ModelDownloader createModelDownloader() => impl.createModelDownloader();
