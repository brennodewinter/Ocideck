'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const vm = require('node:vm');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname, '../../web/whisper/bridge.js'), 'utf8');

function fixture() {
  const f = { modules: [], frees: [], nextInit: null, deferRun: false, failScript: false };
  const sandbox = { WebAssembly, SharedArrayBuffer, crossOriginIsolated: true };
  sandbox.window = sandbox;
  sandbox.document = {
    currentScript: { src: 'https://example.test/whisper/bridge.js' },
    createElement: () => ({}),
    head: { appendChild: el => queueMicrotask(() => {
      if (f.failScript) { f.failScript = false; el.onerror(); return; }
      const M = sandbox.Module;
      f.modules.push(M);
      M.FS_unlink = () => {};
      M.FS_createDataFile = () => {};
      M.init = () => 1;
      M.free = i => f.frees.push([M, i]);
      M.requestCancel = () => { f.cancelled = true; };
      M.full_default = () => {
        f.finish = () => {
          M.print('[00:00:00.000 --> 00:00:00.100] tekst');
          M.printErr('total time = 1 ms');
        };
        if (!f.deferRun) f.finish();
        return f.returnCode || 0;
      };
      if (f.nextInit) { const fn = f.nextInit; f.nextInit = null; fn(M); }
      else M.onRuntimeInitialized();
      el.onload();
    }) }
  };
  vm.runInNewContext(source, sandbox);
  f.bridge = sandbox.ocideckWhisper;
  return f;
}
const pcm = new Float32Array(1600);
const turn = () => new Promise(r => setImmediate(r));

test('abort during init rejects and a new explicit attempt can recover', async () => {
  const f = fixture();
  f.nextInit = M => M.onAbort('OOM');
  await assert.rejects(f.bridge.loadModel(new Uint8Array([1])), /afgebroken/);
  const index = await f.bridge.loadModel(new Uint8Array([1]));
  assert.equal(index, 1);
  assert.equal(f.modules.length, 2);
  assert.equal(f.bridge.contextGeneration(index), f.bridge.runtimeGeneration);
});

test('script failure does not poison all future attempts', async () => {
  const f = fixture(); f.failScript = true;
  await assert.rejects(f.bridge.loadModel(new Uint8Array([1])), /niet gevonden/);
  assert.equal(await f.bridge.loadModel(new Uint8Array([1])), 1);
});

test('abort in run clears context epochs and ignores late old-runtime callbacks', async () => {
  const f = fixture(); f.deferRun = true;
  const index = await f.bridge.loadModel(new Uint8Array([1]));
  const oldGeneration = f.bridge.contextGeneration(index);
  const pending = f.bridge.transcribe(index, pcm, 'auto', 1, null);
  await turn();
  const rejected = assert.rejects(pending, /afgebroken/);
  f.modules[0].onAbort('native failure');
  await rejected;
  assert.equal(f.bridge.contextGeneration(index), 0);
  assert.notEqual(f.bridge.runtimeGeneration, oldGeneration);
  await f.bridge.loadModel(new Uint8Array([1]));
  const newGeneration = f.bridge.runtimeGeneration;
  const next = f.bridge.transcribe(1, pcm, 'auto', 1, null);
  await turn();
  f.modules[0].onAbort('late abort');
  f.modules[0].print('total time = stale');
  assert.equal(f.bridge.runtimeGeneration, newGeneration);
  f.finish();
  assert.equal((await next).segments[0].text, 'tekst');
});

test('active model cannot be freed or replaced and concurrent runs are rejected', async () => {
  const f = fixture(); f.deferRun = true;
  const index = await f.bridge.loadModel(new Uint8Array([1]));
  const pending = f.bridge.transcribe(index, pcm, 'nl', 1, null);
  await turn();
  assert.throws(() => f.bridge.free(index), /in gebruik/);
  await assert.rejects(f.bridge.loadModel(new Uint8Array([1])), /in gebruik/);
  await assert.rejects(f.bridge.transcribe(index, pcm, 'nl', 1, null), /in gebruik/);
  f.bridge.requestCancel(); f.finish();
  assert.equal((await pending).cancelled, true);
  f.bridge.free(index);
  assert.equal(f.frees.length, 1);
  assert.equal(f.bridge.contextGeneration(index), 0);
});

test('failed native start clears callbacks so the next run can proceed', async () => {
  const f = fixture(); f.deferRun = true; f.returnCode = 7;
  const index = await f.bridge.loadModel(new Uint8Array([1]));
  await assert.rejects(f.bridge.transcribe(index, pcm, 'nl', 1, null), /weigerde: 7/);
  f.returnCode = 0; f.deferRun = false;
  assert.equal((await f.bridge.transcribe(index, pcm, 'nl', 1, null)).segments.length, 1);
});

test('free is idempotent and missing context never enters native run', async () => {
  const f = fixture();
  const index = await f.bridge.loadModel(new Uint8Array([1]));
  f.bridge.free(index); f.bridge.free(index);
  assert.equal(f.frees.length, 1);
  await assert.rejects(f.bridge.transcribe(index, pcm, 'auto', 1, null), /context/);
});
