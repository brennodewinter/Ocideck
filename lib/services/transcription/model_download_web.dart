// De modeldownload op web (docs/design/TRANSCRIPTION.md §4.4, #2513).
//
// Dezelfde regels als op desktop, met browsermechaniek in plaats van
// NetGuard-sockets:
//  * de gebruiker start hem expliciet; niets hier begint vanzelf;
//  * `fetch` in CORS-modus laat de browser elke redirect-hop zelf toetsen —
//    ons equivalent van hop-voor-hop NetGuard. Een hop zonder toestemming
//    (geen ACAO) strandt zichtbaar als netwerkfout, nooit als datalek;
//  * voortgang via de streamreader; annuleren via AbortController;
//  * bytes landen als `<sleutel>.part` in IndexedDB en pas na een geslaagde
//    SHA-256 (WebCrypto) onder de echte sleutel — dezelfde betekenis als
//    `.part` op schijf;
//  * quota- en opslagfouten zijn `ioFailed` — zichtbaar, niet stil.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../../utils/log.dart';
import 'model_download.dart';
import 'model_store.dart';
import 'model_store_web.dart'
    show
        deleteModelRecord,
        partialSuffix,
        sha256Web,
        storageFreeBytes,
        writeModelRecord;
import 'whisper_model.dart';

class _WebModelDownload implements ModelDownload {
  _WebModelDownload(this.model, this.destination) : _key = destination.path {
    _progressCtrl = StreamController<ModelDownloadProgress>();
    _run();
  }

  final WhisperModel model;
  final ModelStorePath destination;
  final String _key;
  final _abort = web.AbortController();
  late final StreamController<ModelDownloadProgress> _progressCtrl;
  final _done = Completer<ModelStorePath>();
  bool _cancelled = false;

  @override
  Stream<ModelDownloadProgress> get progress => _progressCtrl.stream;

  @override
  Future<ModelStorePath> get done => _done.future;

  @override
  void cancel() {
    _cancelled = true;
    _abort.abort();
  }

  void _emit(ModelDownloadPhase phase, int received, int total) {
    if (!_progressCtrl.isClosed) {
      _progressCtrl.add(ModelDownloadProgress(phase, received, total));
    }
  }

  /// `.part` weg — best effort. Mag nooit werpen: de foutpaden hieronder
  /// hangen eraan, en een mislukte cleanup mag `_done` niet doen hangen.
  Future<void> _dropPartial() async {
    try {
      await deleteModelRecord('$_key$partialSuffix');
    } on Object catch (e, s) {
      // IndexedDB weigerde — de sweep bij provider-start ruimt hem alsnog.
      logError('WebModelDownload: .part opruimen', e, s);
    }
  }

  void _fail(ModelDownloadFailure failure, String detail) {
    if (!_done.isCompleted) {
      _done.completeError(ModelDownloadException(failure, detail));
    }
    _progressCtrl.close();
  }

  void _finish() {
    if (!_done.isCompleted) _done.complete(destination);
    _progressCtrl.close();
  }

  Future<void> _run() async {
    try {
      _emit(ModelDownloadPhase.connecting, 0, model.downloadBytes);
      final response = await web.window
          .fetch(
            model.url.toString().toJS,
            web.RequestInit(signal: _abort.signal),
          )
          .toDart;
      if (_cancelled) throw _cancelledError();
      if (!response.ok) {
        throw ModelDownloadException(
          ModelDownloadFailure.networkFailed,
          'HTTP ${response.status}',
        );
      }
      // CORS-modus weigert ondoorzichtige antwoorden zelf; een verdediging
      // extra kost hier niets.
      if (response.type != 'cors' && response.type != 'basic') {
        throw const ModelDownloadException(
          ModelDownloadFailure.refused,
          'antwoord is niet CORS-leesbaar',
        );
      }
      final body = response.body;
      if (body == null) {
        throw const ModelDownloadException(
          ModelDownloadFailure.networkFailed,
          'geen responsebody',
        );
      }
      final declared = response.headers.get('content-length');
      final total = int.tryParse(declared ?? '') ?? model.downloadBytes;

      final reader = body.getReader() as web.ReadableStreamDefaultReader;
      final chunks = <Uint8List>[];
      var received = 0;
      while (true) {
        if (_cancelled) throw _cancelledError();
        final step = await reader.read().toDart;
        if (step.done) break;
        final value = step.value;
        if (value != null) {
          final chunk = (value as JSUint8Array).toDart;
          chunks.add(chunk);
          received += chunk.length;
          _emit(ModelDownloadPhase.downloading, received, total);
        }
      }
      if (received != model.downloadBytes) {
        throw ModelDownloadException(
          ModelDownloadFailure.networkFailed,
          '$received van ${model.downloadBytes} bytes ontvangen',
        );
      }

      final merged = Uint8List(received);
      var at = 0;
      for (final chunk in chunks) {
        merged.setRange(at, at + chunk.length, chunk);
        at += chunk.length;
      }

      _emit(ModelDownloadPhase.verifying, received, total);
      final freeBefore = await storageFreeBytes();
      if (freeBefore != null && freeBefore < received * 2) {
        throw const ModelDownloadException(
          ModelDownloadFailure.ioFailed,
          'onvoldoende browseropslagquota voor model + download',
        );
      }

      // Eerst .part parkeren, dan hashtoets, dan pas de echte sleutel —
      // zelfde betekenis als het deelsbestand op schijf.
      await writeModelRecord('$_key$partialSuffix', merged);
      final hex = await sha256Web(merged);
      if (hex == null) {
        await _dropPartial();
        throw const ModelDownloadException(
          ModelDownloadFailure.refused,
          'geen secure context voor de controlesom',
        );
      }
      if (hex != model.sha256) {
        await _dropPartial();
        throw const ModelDownloadException(
          ModelDownloadFailure.invalidHash,
          'sha256 wijkt af van de catalogus',
        );
      }
      await writeModelRecord(_key, merged);
      await _dropPartial();
      _finish();
    } on ModelDownloadException catch (e) {
      await _dropPartial();
      _fail(e.failure, e.detail);
    } catch (e) {
      await _dropPartial();
      if (_cancelled) {
        _fail(ModelDownloadFailure.cancelled, 'afgebroken door de gebruiker');
      } else {
        _fail(ModelDownloadFailure.networkFailed, '$e');
      }
    }
  }

  ModelDownloadException _cancelledError() => const ModelDownloadException(
    ModelDownloadFailure.cancelled,
    'afgebroken door de gebruiker',
  );
}

class WebModelDownloader implements ModelDownloader {
  const WebModelDownloader();

  @override
  ModelDownload start(WhisperModel model, ModelStorePath destination) =>
      _WebModelDownload(model, destination);
}

ModelDownloader createModelDownloader() => const WebModelDownloader();
