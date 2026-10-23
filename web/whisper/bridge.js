// OciDeck — bridge tussen Dart en de whisper.cpp-WASM module (#2513).
//
// Dit bestand is bewust dun en audit-vriendelijk: het is de enige JS die
// OciDeck zelf schrijft naast de gegenereerde emscripten-lijm (libmain.js).
// Het doet vier dingen:
//   * detecteren of de browser/deploy de route kan dragen (SharedArrayBuffer
//     onder cross-origin isolatie — de wasm is met pthreads gebouwd);
//   * libmain.js lui laden (pas als de gebruiker de engine gebruikt);
//   * model-bytes in de virtuele FS plaatsen en een context openen;
//   * audio decoderen/resamplen naar 16 kHz mono en de definitieve pass
//     draaien — met echte cancel via Module.requestCancel (abort_callback).
//
// Geen netwerk hier: model- en audiobytes komen binnen als typed arrays.
'use strict';
(function () {
  // bridge.js is parser-geladen (script-tag in index.html): currentScript is
  // hier geldig en geeft de map `whisper/` op elke deploy-locatie. libmain.js
  // wordt dynamisch geladen — daar is currentScript leeg, en zonder
  // `mainScriptUrlOrBlob` weten de pthread-werkers niet waar libmain.js staat
  // (Emscripten pikt de vorm op als Module-veld, zie libmain.js).
  const SELF = document.currentScript && document.currentScript.src;
  const DIR = SELF ? SELF.slice(0, SELF.lastIndexOf('/') + 1) : 'whisper/';
  const SRC = DIR + 'libmain.js';

  // Segmenttekst komt via Module.print als
  // "[hh:mm:ss.mmm --> hh:mm:ss.mmm]  tekst"; "total time" markeert het
  // einde van een run (ook na abort — whisper_print_timings draait altijd).
  const SEGMENT = /\[(\d+):(\d+):(\d+\.\d+) --> (\d+):(\d+):(\d+\.\d+)\]\s*(.*)/;

  // De print-routes moeten bij moduleconstructie al bestaan; de lopende
  // transcribe wisselt `onLine` uit. `state` deelt de run-status.
  const state = { onLine: null, onAbort: null, moduleReady: null, cancelled: false };

  // Een abort (OOM, te groot model, SAB-misser) doodt de hele runtime:
  // de volgende ensureModule mag een dode module nooit teruggeven.
  function markAborted(why) {
    state.moduleReady = null;
    window.Module = undefined;
    const cb = state.onAbort;
    state.onLine = null;
    state.onAbort = null;
    if (cb) cb(why);
  }

  function isSupported() {
    return typeof WebAssembly !== 'undefined'
        && typeof SharedArrayBuffer !== 'undefined'
        && globalThis.crossOriginIsolated === true;
  }

  function loadScript(src) {
    return new Promise((resolve, reject) => {
      const el = document.createElement('script');
      el.src = src;
      el.onload = resolve;
      el.onerror = () => reject(new Error('script ' + src + ' niet gevonden'));
      document.head.appendChild(el);
    });
  }

  async function ensureModule() {
    if (state.moduleReady) return state.moduleReady;
    // Pre-declareer Module: libmain.js pakt deze vorm op en leest
    // print/printErr/locateFile bij constructie.
    window.Module = {
      locateFile: p => DIR + p,
      mainScriptUrlOrBlob: SRC,
      print: t => { if (state.onLine) state.onLine(t); },
      printErr: t => { if (state.onLine) state.onLine(t); },
      onAbort: why => markAborted(why),
    };
    state.moduleReady = (async () => {
      await loadScript(SRC);
      const M = window.Module;
      await new Promise(r => {
        if (M.runtimeInitialized) return r();
        const prev = M.onRuntimeInitialized;
        M.onRuntimeInitialized = () => { if (prev) prev(); r(); };
      });
      return M;
    })();
    return state.moduleReady;
  }

  // Model bytes -> virtuele FS -> context-index (>0), of 0 bij falen.
  async function loadModel(u8) {
    const M = await ensureModule();
    try { M.FS_unlink('whisper.bin'); } catch (e) { /* bestond niet */ }
    M.FS_createDataFile('/', 'whisper.bin', u8, true, true);
    return M.init('whisper.bin');
  }

  // Definitieve pass over 16 kHz mono f32. Levert {segments, cancelled} —
  // een afgebroken run is een expliciete uitkomst, geen stille afkap.
  // `onSegment` (optioneel, #2515) krijgt elk segment zodra het valt —
  // de Dart-kant rekent dat om naar een voortgangsfractie.
  async function transcribe(ctxIndex, pcm, lang, threads, onSegment) {
    const M = await ensureModule();
    state.cancelled = false;
    const result = new Promise((resolve, reject) => {
      const segments = [];
      state.onAbort = why =>
        reject(new Error('wasm-runtime afgebroken: ' + why));
      state.onLine = t => {
        const m = SEGMENT.exec(t);
        if (m) {
          const t0 = (+m[1] * 3600 + +m[2] * 60 + +m[3]) * 1000;
          const t1 = (+m[4] * 3600 + +m[5] * 60 + +m[6]) * 1000;
          const seg = { t0: Math.round(t0), t1: Math.round(t1), text: m[7] };
          segments.push(seg);
          if (onSegment) onSegment(seg.t1);
        }
        if (t.indexOf('total time') !== -1) {
          state.onLine = null;
          resolve({ segments, cancelled: state.cancelled });
        }
      };
    });
    const ret = M.full_default(ctxIndex, pcm, lang, threads, false);
    if (ret !== 0) {
      state.onLine = null;
      throw new Error('full_default weigerde: ' + ret);
    }
    return result;
  }

  function requestCancel() {
    state.cancelled = true;
    try {
      if (window.Module) window.Module.requestCancel();
    } catch (e) { /* module nog niet geladen — er liep dan ook niets */ }
  }

  function free(ctxIndex) {
    if (window.Module && ctxIndex) window.Module.free(ctxIndex);
  }

  // Container -> 16 kHz mono Float32Array via Web Audio (dezelfde weg als
  // de upstream-demo, en daarmee de breedste containerdekking).
  async function decodeAudio(bytes) {
    const AC = window.AudioContext || window.webkitAudioContext;
    const OC = window.OfflineAudioContext || window.webkitOfflineAudioContext;
    const ac = new AC();
    try {
      // decodeAudioData wil een kale ArrayBuffer (Chrome weigert views) —
      // de Dart-kant stuurt een Uint8Array-view, dus slice exact het bereik.
      const buf = bytes.buffer.slice(
        bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
      const decoded = await ac.decodeAudioData(buf);
      const n = Math.max(1, Math.ceil(decoded.duration * 16000));
      const oc = new OC(1, n, 16000);
      const src = oc.createBufferSource();
      src.buffer = decoded;
      src.connect(oc.destination);
      src.start(0);
      const rendered = await oc.startRendering();
      return rendered.getChannelData(0);
    } finally {
      ac.close();
    }
  }

  window.ocideckWhisper = {
    isSupported, ensureModule, loadModel, transcribe, requestCancel, free,
    decodeAudio,
  };
})();
