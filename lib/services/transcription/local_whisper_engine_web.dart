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

class WebWhisperEngine
    implements LocalWhisperEngine, ManagedTranscriptionEngine {
  WebWhisperEngine({this.model});

  @override
  final WhisperModel? model;

  final _runtime = WebWhisperRuntime();
  bool _running = false;
  bool _cancelRequested = false;
  bool _nativeActive = false;
  WhisperBridge? _activeBridge;

  @override
  EngineKind get kind => EngineKind.local;

  /// Wasm-runtime + pthreads vereisen cross-origin isolatie (COOP/COEP) —
  /// de proefmatrix in docs/design/TRANSCRIPTION.md §4.6 meet dit af.
  bool get _supported => whisperBridge?.isSupported() ?? false;

  @override
  Future<LocalEngineStatus> status() {
    if (whisperBridge == null) {
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
    // Dezelfde whisper.cpp als de CLI — de WASM-bridge neemt dezelfde
    // taalcode, dus dezelfde eerlijke tabel (#2940).
    languages: whisperSupportedLanguages,
    requiresModel: model?.id,
  );

  int get _threads {
    final hc = web.window.navigator.hardwareConcurrency;
    return hc > 0 ? (hc < 4 ? hc : 4) : 4;
  }

  Future<int> _ensureContext(WhisperBridge bridge) async {
    final ctx = _runtime.cachedContext(bridge);
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
    _checkCancelled();
    final int ctxIndex;
    try {
      ctxIndex = await _runtime.load(bridge, bytes.toJS);
    } on Object catch (e) {
      _checkCancelled();
      throw EngineUnavailable('wasm-model laden afgebroken: $e');
    }
    _checkCancelled();
    return ctxIndex;
  }

  void _checkCancelled() {
    if (_cancelRequested) throw const Cancelled('transcriptie afgebroken');
  }

  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) async {
    if (_running) throw const EngineUnavailable('engine is al in gebruik');
    _running = true;
    _cancelRequested = false;
    try {
      return await _runtime.run(() => _transcribe(audio, options));
    } finally {
      _nativeActive = false;
      _activeBridge = null;
      _running = false;
    }
  }

  Future<TranscriptResult> _transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) async {
    _checkCancelled();
    if (!_supported) {
      throw const EngineUnavailable(
        'lokale web-engine vereist cross-origin isolatie',
      );
    }
    if (options.diarize) {
      throw const EngineUnavailable(
        'diarisatie wordt door deze engine niet ondersteund',
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
    final bridge = whisperBridge!;
    _activeBridge = bridge;
    final ctx = await _ensureContext(bridge);
    _checkCancelled();
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
      _checkCancelled();
      logError('WebWhisperEngine: audiodecode', e, s);
      throw const DecodeFailed('audiocontainer niet te decoderen');
    }
    _checkCancelled();
    // Elk segment dat valt is een stukje voortgang: eindtijd van het
    // segment gedeeld door de audioduur (#2515).
    final onProgress = options.onProgress;
    final durationMs = pcm.length / 16000 * 1000;
    final JSObject raw;
    try {
      _nativeActive = true;
      raw = await bridge
          .transcribe(
            ctx.toJS,
            pcm.toJS,
            (options.language ?? 'auto').toJS,
            _threads.toJS,
            onProgress == null || durationMs <= 0
                ? null
                : ((JSNumber t1) {
                    final f = t1.toDartDouble / durationMs;
                    onProgress(f > 1 ? 1.0 : f);
                  }).toJS,
          )
          .toDart;
    } catch (e) {
      _checkCancelled();
      throw EngineUnavailable('wasm-run afgebroken: $e');
    } finally {
      _nativeActive = false;
    }
    _checkCancelled();
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
    if (!_running) return;
    _cancelRequested = true;
    try {
      // Een wachtende taak mag de native run van een andere engine niet stoppen.
      if (_nativeActive) _activeBridge?.requestCancel();
    } on Object catch (e, s) {
      logError('WebWhisperEngine: cancel', e, s);
    }
  }

  @override
  void dispose() => _runtime.dispose();

  @override
  Stream<PartialTranscript>? transcribeLive(
    Stream<AudioChunk> chunks, {
    TranscriptionOptions? options,
  }) => null;
}

LocalWhisperEngine createLocalWhisperEngine({WhisperModel? model}) =>
    WebWhisperEngine(model: model);

@JS('ocideckWhisper')
external WhisperBridge? get whisperBridge;

extension type WhisperBridge(JSObject _) implements JSObject {
  external bool isSupported();
  external JSNumber get runtimeGeneration;
  external JSNumber contextGeneration(JSNumber index);
  external JSPromise<JSNumber> loadModel(JSUint8Array bytes);
  external JSPromise<JSObject> transcribe(
    JSNumber index,
    JSFloat32Array pcm,
    JSString lang,
    JSNumber threads,
    JSFunction? onSegment,
  );
  external JSPromise<JSFloat32Array> decodeAudio(JSUint8Array bytes);
  external void requestCancel();
  external void free(JSNumber index);
}

/// Provider-dispose trekt het aanbod in, maar een reeds begonnen taak mag
/// zijn context tot in zijn finally houden. De volgende taak wacht daarop.
class WebWhisperRuntime {
  static Future<void> _tail = Future.value();
  bool _busy = false;
  bool _retired = false;
  int? _context;
  int? _generation;
  WhisperBridge? _loadedBridge;

  Future<T> run<T>(Future<T> Function() body) async {
    if (_retired || _busy) {
      throw const EngineUnavailable('engine is vervangen of al in gebruik');
    }
    _busy = true;
    final previous = _tail;
    final turn = Completer<void>();
    _tail = turn.future;
    try {
      await previous;
      return await body();
    } finally {
      // Vrijgeven binnen deze beurt: ook bij veel snelle modelwissels mag
      // de oude context geen extra plek in de native contexttabel innemen.
      if (_retired) _free();
      _busy = false;
      turn.complete();
    }
  }

  int? cachedContext(WhisperBridge bridge) {
    final ctx = _context;
    if (ctx == null) return null;
    if (bridge != _loadedBridge ||
        bridge.runtimeGeneration.toDartInt != _generation ||
        bridge.contextGeneration(ctx.toJS).toDartInt != _generation) {
      _context = null;
      _loadedBridge = null;
      return null;
    }
    return ctx;
  }

  Future<int> load(WhisperBridge bridge, JSUint8Array bytes) async {
    final ctx = (await bridge.loadModel(bytes).toDart).toDartInt;
    final generation = bridge.contextGeneration(ctx.toJS).toDartInt;
    if (ctx <= 0 || generation != bridge.runtimeGeneration.toDartInt) {
      throw const EngineUnavailable('model kon niet in de wasm-engine laden');
    }
    _context = ctx;
    _generation = generation;
    _loadedBridge = bridge;
    return ctx;
  }

  void dispose() {
    if (_retired) return;
    _retired = true;
    if (_busy) return;
    final previous = _tail;
    final turn = Completer<void>();
    _tail = turn.future;
    unawaited(() async {
      try {
        await previous;
        _free();
      } finally {
        turn.complete();
      }
    }());
  }

  void _free() {
    final bridge = _loadedBridge;
    try {
      // Een abort vernietigt de hele runtime. Dezelfde numerieke index in
      // de volgende runtime is andermans model en mag nooit worden vrijgegeven.
      final ctx = bridge == null ? null : cachedContext(bridge);
      if (ctx != null && bridge == whisperBridge) bridge!.free(ctx.toJS);
    } on Object catch (e, s) {
      logError('WebWhisperRuntime: context vrijgeven', e, s);
    } finally {
      _context = null;
      _loadedBridge = null;
    }
  }
}
