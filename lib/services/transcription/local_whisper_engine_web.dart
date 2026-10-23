// De lokale engine op web: whisper.cpp als WASM in de pagina zelf
// (docs/design/TRANSCRIPTION.md §4.2/§5.3, #2513).
//
// Dezelfde bron, zelfde modellen, zelfde contract als de desktop-helper —
// alleen draait hij in de tab in plaats van in een subproces. De grens met
// de native wereld is `web/whisper/bridge.js`: een kleine audit-laag die
// libmain.js lui laadt, modelbytes in de virtuele FS zet, segmenttekst uit
// de print-stroom vist en Cancel doorgeeft aan `abort_callback`.
//
// Harde voorwaarden die hier worden afgedwongen, niet verondersteld:
//  * cross-origin isolatie + SharedArrayBuffer — de wasm is met pthreads
//    gebouwd; zonder COOP/COEP-headers van de host abort de module hard
//    (`LocalEngineSupport.noIsolation` meldt dat vóór enige download);
//  * het model komt uit de IndexedDB-store mét de catalogus-hash; een
//    model dat de hash niet haalt wordt de engine nooit gevoed;
//  * audio komt binnen als bytes (`mem:`-store of gekozen bestand) — de
//    engine netwerkt nooit; modeldownload is een aparte, zichtbare route.
import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../web_asset_store.dart';
import '../../utils/log.dart';
import 'capture_source.dart' show AudioChunk;
import 'local_whisper_engine.dart';
import 'model_store.dart' show createModelStore;
import 'model_store_web.dart' show readModelRecord, sha256Web;
import 'transcription_engine.dart';
import 'transcription_errors.dart';
import 'whisper_model.dart';

@JS('ocideckWhisper')
external _JsWhisperBridge? get _bridge;

extension type _JsWhisperBridge(JSObject _) implements JSObject {
  external bool isSupported();
  external JSPromise<JSNumber> loadModel(JSUint8Array bytes);
  external JSPromise<JSObject> transcribe(
    JSNumber ctxIndex,
    JSFloat32Array pcm,
    JSString lang,
    JSNumber threads,
  );
  external JSPromise<JSFloat32Array> decodeAudio(JSUint8Array bytes);
  external void requestCancel();
  external void free(JSNumber ctxIndex);
}

class WebWhisperEngine implements LocalWhisperEngine {
  WebWhisperEngine({this.model});

  @override
  final WhisperModel? model;

  int? _context;

  @override
  EngineKind get kind => EngineKind.local;

  /// Wasm-runtime + pthreads vereisen cross-origin isolatie (COOP/COEP) —
  /// de proefmatrix in docs/design/TRANSCRIPTION.md §4.6 meet dit af.
  bool get _supported => _bridge?.isSupported() ?? false;

  @override
  Future<LocalEngineStatus> status() {
    if (_bridge == null) {
      return Future.value(
        const LocalEngineStatus(
          LocalEngineSupport.missingHelper,
          'whisper/bridge.js ontbreekt in deze bundle',
        ),
      );
    }
    if (!_supported) {
      return Future.value(
        const LocalEngineStatus(
          LocalEngineSupport.noIsolation,
          'geen cross-origin isolatie of SharedArrayBuffer',
        ),
      );
    }
    return Future.value(const LocalEngineStatus(LocalEngineSupport.ready, ''));
  }

  @override
  Future<EngineCapabilities> capabilities() async => EngineCapabilities(
    timestamps: true,
    languages: const {'auto'},
    requiresModel: model?.id,
  );

  int get _threads {
    final hc = web.window.navigator.hardwareConcurrency;
    return hc > 0 ? (hc < 4 ? hc : 4) : 4;
  }

  Future<int> _ensureContext() async {
    final ctx = _context;
    if (ctx != null) return ctx;
    final m = model;
    if (m == null) {
      throw const EngineUnavailable('geen model gekozen');
    }
    // De recordsleutel komt uit de store — containment (alleen `models/`,
    // nooit `..`) wordt daar afgedwongen, niet hier opnieuw uitgevonden.
    final key = (await createModelStore().modelPath(m)).path;
    final bytes = await readModelRecord(key);
    if (bytes == null) {
      throw const EngineUnavailable('model is niet geïnstalleerd');
    }
    // Dezelfde discipline als desktop: hash eerst, pas dan voeren.
    final hex = await sha256Web(bytes);
    if (hex != m.sha256) {
      throw const EngineUnavailable('model-hash klopt niet met de catalogus');
    }
    final idx = (await _bridge!.loadModel(bytes.toJS).toDart).toDartInt;
    if (idx <= 0) {
      throw const EngineUnavailable('model kon niet in de wasm-engine laden');
    }
    _context = idx;
    return idx;
  }

  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) async {
    if (!_supported) {
      throw const EngineUnavailable(
        'lokale web-engine vereist cross-origin isolatie',
      );
    }
    final Uint8List? bytes = WebAssetStore.isMemPath(audio.path)
        ? WebAssetStore.bytesFor(audio.path)
        : null;
    if (bytes == null) {
      throw SourceUnavailable(
        'audiobron niet in de tab aanwezig: ${audio.path}',
      );
    }
    final ctx = await _ensureContext();
    final bridge = _bridge!;
    final Float32List pcm;
    try {
      // Een expliciete view: `mem:`-bytes kunnen op een grotere buffer liggen
      // en `bytes.buffer` zou die meesturen — verkeerde audio, geen fout.
      final view = bytes.buffer.asUint8List(
        bytes.offsetInBytes,
        bytes.lengthInBytes,
      );
      pcm = (await bridge.decodeAudio(view.toJS).toDart).toDart;
    } on Object catch (e, s) {
      logError('WebWhisperEngine: audiodecode', e, s);
      throw const DecodeFailed('audiocontainer niet te decoderen');
    }
    final JSObject raw;
    try {
      raw = await bridge
          .transcribe(
            ctx.toJS,
            pcm.toJS,
            (options.language ?? 'auto').toJS,
            _threads.toJS,
          )
          .toDart;
    } catch (e) {
      throw EngineUnavailable('wasm-run afgebroken: $e');
    }
    final map = raw.dartify() as Map<Object?, Object?>;
    if (map['cancelled'] == true) {
      throw const Cancelled('transcriptie afgebroken');
    }
    final segments = <TranscriptSegment>[];
    for (final item in (map['segments'] as List<Object?>? ?? const [])) {
      final s = item as Map<Object?, Object?>;
      segments.add(
        TranscriptSegment(
          text: '${s['text'] ?? ''}',
          start: Duration(milliseconds: (s['t0'] as num?)?.toInt() ?? 0),
        ),
      );
    }
    return TranscriptResult(segments: segments);
  }

  @override
  void cancel() {
    try {
      _bridge?.requestCancel();
    } on Object catch (e, s) {
      // Een kapotte runtime hoeft niet ook nog een cancel-fout te geven.
      logError('WebWhisperEngine: cancel', e, s);
    }
  }

  /// Wasm-modellen ontladen — roept de bridge `free` voor deze context.
  void dispose() {
    final ctx = _context;
    if (ctx != null) {
      _context = null;
      try {
        _bridge?.free(ctx.toJS);
      } on Object catch (e, s) {
        logError('WebWhisperEngine: context vrijgeven', e, s);
      }
    }
  }

  @override
  Stream<PartialTranscript>? transcribeLive(Stream<AudioChunk> chunks) => null;
}

LocalWhisperEngine createLocalWhisperEngine({WhisperModel? model}) =>
    WebWhisperEngine(model: model);
