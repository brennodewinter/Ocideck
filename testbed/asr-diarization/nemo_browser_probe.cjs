// Requires an explicitly started ASR server and a compiled Flutter probe target.
// NODE_PATH=/path/to/node_modules node nemo_browser_probe.cjs BUILD_DIR FIXTURE OUTPUT
'use strict';
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const crypto = require('node:crypto');
const playwright = require('playwright');
const [directory, fixture, output] = process.argv.slice(2);
if (!directory || !fixture || !output) throw Error('Provide build, fixture and output paths');
const root = path.resolve(directory);
fs.rmSync(output, {force:true});
const wav = fs.readFileSync(fixture);
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const server = http.createServer((request, response) => {
  response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  response.setHeader('Cache-Control', 'no-store');
  if (request.url === '/fixtures/audio.wav') {
    response.setHeader('Content-Type', 'audio/wav'); response.end(wav); return;
  }
  const url = new URL(request.url, 'http://localhost:7357');
  let relative;
  try { relative = decodeURIComponent(url.pathname).replace(/^\/+/, '') || 'index.html'; }
  catch { response.writeHead(400).end(); return; }
  const target = path.resolve(root, relative);
  if (!target.startsWith(root + path.sep) || !fs.existsSync(target) || !fs.statSync(target).isFile()) {
    response.writeHead(404).end(); return;
  }
  const mime = {'.js':'application/javascript','.json':'application/json','.html':'text/html',
    '.wasm':'application/wasm','.css':'text/css','.ttf':'font/ttf'}[path.extname(target)];
  if (mime) response.setHeader('Content-Type', mime);
  response.end(fs.readFileSync(target));
});
(async () => {
  await new Promise(resolve => server.listen(7357, '127.0.0.1', resolve));
  const report = {scope:'compiled Flutter production web transport probe, not full release UI',
    fixture_sha256:digest(wav), compiled_js_sha256:digest(fs.readFileSync(path.join(root,'main.dart.js'))), browsers:[]};
  fs.mkdirSync(path.dirname(path.resolve(output)), {recursive:true});
  for (const name of ['chromium','webkit']) {
    const browser = await playwright[name].launch({headless:true});
    try {
      // Test-only acceptance of the explicitly generated loopback certificate.
      // Production CSP stays intact and still requires HTTPS for remote ASR.
      const page = await browser.newPage({ignoreHTTPSErrors:true});
      await page.goto('http://localhost:7357/', {waitUntil:'domcontentloaded'});
      await page.waitForFunction(() => typeof globalThis.ocideckDiarizationProbeResult === 'string', null, {timeout:300000});
      const result = JSON.parse(await page.evaluate(() => globalThis.ocideckDiarizationProbeResult));
      report.browsers.push({name,version:browser.version(),...result});
      fs.writeFileSync(output, JSON.stringify(report,null,2)+'\n');
      if (!result.success) throw Error(`${name}: real diarization transport probe failed`);
      console.log(`${name}: production web diarization transport and document model verified`);
    } finally { await browser.close(); }
  }
})().catch(error => {console.error(error.message);process.exitCode=1;}).finally(() => server.close());
