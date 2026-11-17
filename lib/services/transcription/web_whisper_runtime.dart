// Eén eigenaar per modelcontext, één actieve gebruiker van de globale WASM.
import 'dart:async';
import 'dart:js_interop';

import '../../utils/log.dart';
import 'transcription_errors.dart';

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
