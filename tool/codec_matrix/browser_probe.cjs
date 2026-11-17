// Explicit decoder probe, not an ASR/UI test. Requires locally installed Playwright.
// NODE_PATH=/path/to/node_modules node tool/codec_matrix/browser_probe.cjs OUTPUT.json chromium webkit
'use strict';
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');
const crypto = require('node:crypto');
const playwright = require('playwright');
const root = path.resolve(__dirname, '../..');
const fixtureRoot = path.join(root, 'integration_test/fixtures/audio_formats');
const manifest = JSON.parse(fs.readFileSync(path.join(fixtureRoot, 'manifest.json')));
const output = process.argv[2];
const browsers = process.argv.slice(3);
if (!output || !browsers.length || browsers.some(name => !['chromium', 'firefox', 'webkit'].includes(name))) {
  throw Error('Provide an output JSON path and explicit browser names');
}
const bridge = fs.readFileSync(path.join(root, 'web/whisper/bridge.js'));
const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
const files = new Map(manifest.fixtures.map(item => {
  const bytes = fs.readFileSync(path.join(fixtureRoot, item.source));
  if (digest(bytes) !== item.source_sha256) throw Error(`Fixture hash mismatch: ${item.source}`);
  return [`/fixtures/${encodeURIComponent(item.source)}`, bytes];
}));
const server = http.createServer((request, response) => {
  response.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  response.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  if (request.url === '/') {
    response.setHeader('Content-Type', 'text/html');
    response.end('<!doctype html><script src="/bridge.js"></script>');
  } else if (request.url === '/bridge.js') {
    response.setHeader('Content-Type', 'application/javascript');
    response.end(bridge);
  } else if (files.has(request.url)) {
    response.end(files.get(request.url));
  } else {
    response.writeHead(404).end();
  }
});
(async () => {
  const report = {scope: 'Production browser decoder; synthetic tones; no ASR/UI claim',
    platform: process.platform, bridge_sha256: digest(bridge), browsers: []};
  let failed = false;
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    for (const name of browsers) {
      const row = {browser: name, results: []};
      report.browsers.push(row);
      let browser;
      try {
        browser = await playwright[name].launch({headless: true});
        row.version = browser.version();
        const page = await browser.newPage();
        await page.goto(`http://127.0.0.1:${server.address().port}/`);
        row.user_agent = await page.evaluate(() => navigator.userAgent);
        for (const fixture of manifest.fixtures) {
          const result = await page.evaluate(async source => {
            let timer;
            try {
              const bytes = new Uint8Array(await (await fetch(`/fixtures/${encodeURIComponent(source)}`)).arrayBuffer());
              const pcm = await Promise.race([ocideckWhisper.decodeAudio(bytes),
                new Promise((_, reject) => { timer = setTimeout(() => reject(Error('decode timeout')), 10000); })]);
              let energy = 0;
              for (const sample of pcm) energy += Math.abs(sample);
              return {samples: pcm.length, duration_ms: pcm.length / 16, energy};
            } catch (error) { return {error: String(error)}; }
            finally { clearTimeout(timer); }
          }, fixture.source);
          if (!result.error && (!(result.energy > 0) || Math.abs(result.duration_ms - fixture.expected_duration_ms) > fixture.duration_tolerance_ms)) {
            result.invalid_output = true;
            failed = true;
          }
          row.results.push({source: fixture.source, source_sha256: fixture.source_sha256, ...result});
        }
      } catch (error) {
        row.probe_error = String(error);
        failed = true;
      } finally {
        if (browser) await browser.close();
      }
    }
  } finally {
    await new Promise(resolve => server.close(resolve));
    fs.writeFileSync(output, JSON.stringify(report, null, 2) + '\n');
  }
  if (failed) process.exitCode = 1;
})().catch(error => { console.error(error); process.exitCode = 1; server.close(); });
