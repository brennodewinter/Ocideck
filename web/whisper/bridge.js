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
  const state = {
    onLine: null, onAbort: null, initAbort: null, moduleReady: null,
    cancelled: false, generation: 0, contexts: new Map(), active: null,
  };

  // Contextindices zijn alleen binnen hun eigen runtime geldig. Een late
  // callback van een overleden module mag de opvolger niet afbreken.
  function markAborted(generation, why) {
    if (generation !== state.generation) return;
    state.generation++;
    state.contexts.clear();
    state.moduleReady = null;
    window.Module = undefined;
    const init = state.initAbort;
    const run = state.onAbort;
    state.initAbort = state.onLine = state.onAbort = null;
    if (init) init(new Error('wasm-initialisatie afgebroken: ' + why));
    if (run) run(why);
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
    const generation = ++state.generation;
    const initialized = new Promise((resolve, reject) => {
      state.initAbort = reject;
      window.Module = {
        locateFile: p => DIR + p,
        mainScriptUrlOrBlob: SRC,
        print: t => {
          if (generation === state.generation && state.onLine) state.onLine(t);
        },
        printErr: t => {
          if (generation === state.generation && state.onLine) state.onLine(t);
        },
        onRuntimeInitialized: resolve,
        onAbort: why => markAborted(generation, why),
      };
    });
    state.moduleReady = (async () => {
      try {
        await Promise.all([loadScript(SRC), initialized]);
        if (generation !== state.generation) throw new Error('oude wasm-runtime');
        state.initAbort = null;
        return window.Module;
      } catch (e) {
        if (generation === state.generation) markAborted(generation, e);
        throw e;
      }
    })();
    return state.moduleReady;
  }

  async function loadModel(u8) {
    const M = await ensureModule();
    const generation = state.generation;
    if (state.active) throw new Error('wasm-engine is in gebruik');
    try { M.FS_unlink('whisper.bin'); } catch (e) { /* bestond niet */ }
    M.FS_createDataFile('/', 'whisper.bin', u8, true, true);
    const index = M.init('whisper.bin');
    if (generation !== state.generation) throw new Error('modelruntime afgebroken');
    if (index > 0) state.contexts.set(index, generation);
    return index;
  }

  function contextGeneration(index) {
    return state.contexts.get(index) || 0;
  }

  // Eén run beheert print/abort tot zijn eigen promise afgewikkeld is.
  async function transcribe(ctxIndex, pcm, lang, threads, onSegment) {
    const M = await ensureModule();
    if (contextGeneration(ctxIndex) !== state.generation) {
      throw new Error('modelcontext hoort niet bij deze runtime');
    }
    if (state.active) throw new Error('wasm-engine is in gebruik');
    const token = {};
    state.active = token;
    state.cancelled = false;
    try {
      return await new Promise((resolve, reject) => {
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
        try {
          const ret = M.full_default(ctxIndex, pcm, lang, threads, false);
          if (ret !== 0) reject(new Error('full_default weigerde: ' + ret));
        } catch (e) { reject(e); }
      });
    } finally {
      if (state.active === token) {
        state.active = state.onLine = state.onAbort = null;
      }
    }
  }

  function requestCancel() {
    if (!state.active) return;
    state.cancelled = true;
    try {
      if (window.Module) window.Module.requestCancel();
    } catch (e) { /* de runtime kan al zijn afgebroken */ }
  }

  function free(ctxIndex) {
    if (state.active) throw new Error('wasm-engine is in gebruik');
    if (window.Module && contextGeneration(ctxIndex) === state.generation) {
      window.Module.free(ctxIndex);
      state.contexts.delete(ctxIndex);
    }
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
    decodeAudio, contextGeneration,
    get runtimeGeneration() { return state.generation; },
  };
})();
