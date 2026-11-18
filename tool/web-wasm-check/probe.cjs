// Runs the actual release bundle under its shipped CSP, isolation and MIME rules.
// Usage: node probe.cjs [bundle] [browser,...] [auto|fallback|single-thread|baseline] [runs]
// npm ci; npx playwright install chromium firefox webkit
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const zlib = require('node:zlib');
const {performance} = require('node:perf_hooks');
const playwright = require('playwright');
const root = path.resolve(process.argv[2] || 'build/web');
const engines = (process.argv[3] || 'chromium,firefox,webkit').split(',');
const mode = process.argv[4] || 'auto';
const runs = Number(process.argv[5] || 3);
if (!['auto', 'fallback', 'single-thread', 'baseline'].includes(mode) || !Number.isInteger(runs) || !(runs > 0)) {
  throw new Error('Expected auto|fallback|single-thread|baseline and a positive integer run count');
}
const config = fs.readFileSync(path.join(root, '.htaccess'), 'utf8');
const types = {'.html':'text/html', '.js':'text/javascript', '.mjs':'text/javascript',
  '.wasm':'application/wasm', '.json':'application/json', '.ttf':'font/ttf',
  '.otf':'font/otf', '.png':'image/png', '.svg':'image/svg+xml', '.css':'text/css'};
const cache = new Map();
const server = http.createServer((req, res) => {
  try {
    // A subdirectory deployment catches absolute asset/bootstrap paths as well.
    const url = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    if (!url.startsWith('/ocideck/')) { res.writeHead(404).end(); return; }
    const relative = url.slice('/ocideck/'.length) || 'index.html';
    const file = path.resolve(root, relative);
    if (!file.startsWith(root + path.sep) || !fs.statSync(file).isFile()) {
      res.writeHead(404).end(); return;
    }
    if (!cache.has(file)) {
      let bytes = fs.readFileSync(file);
      if (mode === 'fallback' && relative === 'flutter_bootstrap.js') {
        const original = bytes.toString();
        const altered = original.replace(/wasmAllowList:\s*\{[^}]*\}/,
          'wasmAllowList: {blink: false, webkit: false, gecko: false}');
        if (original === altered) throw new Error('No wasmAllowList to override');
        bytes = Buffer.from(altered);
      }
      cache.set(file, zlib.gzipSync(bytes));
    }
    const headers = {'Content-Type':types[path.extname(file)] || 'application/octet-stream',
      'Content-Encoding':'gzip', 'Cache-Control':'no-cache'};
    for (const [, name, value] of config.matchAll(/Header always set ([\w-]+) "([^"]*)"/g)) {
      if (name === 'Cache-Control') continue;
      if (mode === 'single-thread' && name.startsWith('Cross-Origin-')) continue;
      headers[name] = value;
    }
    res.writeHead(200, headers).end(cache.get(file));
  } catch (error) { res.writeHead(404).end(String(error)); }
});
(async () => {
  const results = [];
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    for (const engine of engines) {
      const browser = await playwright[engine].launch({headless:true});
      try {
        for (let run = 0; run < runs; run++) {
          const context = await browser.newContext({viewport:{width:1440,height:900}});
          await context.addInitScript(() => {
            window.addEventListener('flutter-first-frame', () => performance.mark('probe:first-frame'));
          });
          const page = await context.newPage();
          const errors = [], badResponses = [], requests = [], workers = [];
          page.on('worker', worker => workers.push(worker.url()));
          page.on('pageerror', error => errors.push(String(error)));
          page.on('response', response => {
            if (response.status() >= 400) badResponses.push([response.status(),response.url()]);
          });
          page.on('request', request => requests.push(request.url()));
          const started = performance.now();
          await page.goto(`http://127.0.0.1:${server.address().port}/ocideck/`);
          await page.waitForFunction(() =>
            performance.getEntriesByName('probe:first-frame').length > 0,
            null, {timeout:120000});
          const observedReadyMs = performance.now() - started;
          await page.waitForTimeout(500);
          const measurements = await page.evaluate(() => ({
            isolated:crossOriginIsolated,
            marks:performance.getEntriesByType('measure').filter(e=>e.name.startsWith('ocideck:'))
              .map(e=>({name:e.name,ms:e.duration})),
            resources:performance.getEntriesByType('resource').map(e=>({
              url:e.name,encoded:e.encodedBodySize,decoded:e.decodedBodySize,transfer:e.transferSize})),
          }));
          const wasm = requests.some(url=>/main\.dart(?:\.[a-f0-9]{8})?\.wasm$/.test(url));
          const skwasm = requests.some(url=>/\/skwasm[^/]*\.wasm$/.test(url));
          const fallback = requests.some(url=>/main\.dart(?:\.[a-f0-9]{8})?\.js$/.test(url));
          if (errors.length || badResponses.length) {
            throw new Error(JSON.stringify({engine,mode,errors,badResponses}));
          }
          if (mode === 'fallback' ? (!fallback || wasm) : (mode === 'auto' && !wasm)) {
            throw new Error(`Unexpected compiler selection: ${engine} ${mode} wasm=${wasm} js=${fallback}`);
          }
          if (mode === 'auto' || mode === 'single-thread') {
            if (!wasm || !skwasm || fallback) throw new Error('Expected WASM + skwasm only');
            const isolated = mode === 'auto';
            if (measurements.isolated !== isolated || (workers.length > 0) !== isolated) {
              throw new Error(`Unexpected rendering isolation/worker: ${JSON.stringify({mode,workers,...measurements})}`);
            }
          }
          const remote = requests.filter(url =>
            !url.startsWith(`http://127.0.0.1:${server.address().port}/`) &&
            !url.startsWith('blob:') && !url.startsWith('data:'));
          if (remote.length) throw new Error(`Third-party startup requests: ${remote.join(', ')}`);
          const item = {engine,browser:browser.version(),mode,run,wasm,skwasm,fallback,
            observedReadyMs,workers,...measurements};
          results.push(item);
          if (run === 0 && process.env.OCIDECK_WASM_SCREENSHOT_DIR) {
            const output = path.resolve(process.env.OCIDECK_WASM_SCREENSHOT_DIR);
            fs.mkdirSync(output, {recursive:true});
            await page.screenshot({path:path.join(output, `${engine}-${mode}.png`)});
          }
          console.error(`${engine} ${mode} #${run+1}: ready=${observedReadyMs.toFixed(0)}ms wasm=${wasm} skwasm=${skwasm}`);
          await context.close();
        }
      } finally { await browser.close(); }
    }
    console.log(JSON.stringify({node:process.version,bundle:root,results},null,2));
  } finally { await new Promise(resolve=>server.close(resolve)); }
})().catch(error=>{console.error(error);process.exitCode=1;});
