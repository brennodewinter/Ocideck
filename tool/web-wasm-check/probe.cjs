// Runs the actual release bundle under its shipped CSP, isolation and MIME rules.
// Usage: node probe.cjs [bundle] [browser,...] [auto|fallback|single-thread|baseline] [runs]
// npm ci; npx playwright install chromium firefox webkit
const fs = require('node:fs');
const path = require('node:path');
const {execFileSync} = require('node:child_process');
const {performance} = require('node:perf_hooks');
const playwright = require('playwright');
const scenarios = require('./scenarios.cjs');
const root = path.resolve(process.argv[2] || 'build/web');
const engines = (process.argv[3] || 'chromium,firefox,webkit').split(',');
const mode = process.argv[4] || 'auto';
const runs = Number(process.argv[5] || 3);
if (!['auto', 'fallback', 'single-thread', 'baseline'].includes(mode) || !Number.isInteger(runs) || !(runs > 0)) {
  throw new Error('Expected auto|fallback|single-thread|baseline and a positive integer run count');
}
const source = {bundle:JSON.parse(fs.readFileSync(path.join(root,'build-info.json'),'utf8')),commit:execFileSync('git',['rev-parse','HEAD'],{encoding:'utf8'}).trim(),
  dirty:execFileSync('git',['status','--porcelain'],{encoding:'utf8'}).trim().length > 0};
const server = require('./server.cjs')(root, mode);
(async () => {
  const results = [];
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  try {
    for (const engine of engines) {
      const browser = await playwright[engine].launch({headless:true});
      try {
        const fileGuard = await scenarios.fileGuard(browser, root);
        for (let run = 0; run < runs; run++) {
          const context = await browser.newContext({viewport:{width:1440,height:900},locale:'en-GB'});
          await context.addInitScript(() => {
            window.addEventListener('flutter-first-frame', () => performance.mark('probe:first-frame'));
          });
          const page = await context.newPage();
          const observed = scenarios.observe(page);
          const {errors,badResponses,requests,workers} = observed;
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
          const startupRequests = [...requests];
          const startupWorkers = [...workers];
          const snapshot = async name => {
            if (!process.env.OCIDECK_WASM_SCREENSHOT_DIR) return;
            const output = path.resolve(process.env.OCIDECK_WASM_SCREENSHOT_DIR);
            fs.mkdirSync(output, {recursive:true});
            await page.screenshot({path:path.join(output, `${engine}-${mode}-${run}-${name}.png`)});
          };
          let journey;
          try {
            journey = await scenarios.journey(page, `http://127.0.0.1:${server.address().port}/ocideck/`, observed, snapshot);
          } catch (error) {
            await snapshot('failure');
            console.error(JSON.stringify({engine,mode,errors,badResponses,ui:await page.locator('body').ariaSnapshot()}));
            throw error;
          }
          const wasm = startupRequests.some(url=>/main\.dart(?:\.[a-f0-9]{8})?\.wasm$/.test(url));
          const skwasm = startupRequests.some(url=>/\/skwasm[^/]*\.wasm$/.test(url));
          const fallback = startupRequests.some(url=>/main\.dart(?:\.[a-f0-9]{8})?\.js$/.test(url));
          if (errors.length || badResponses.length) {
            throw new Error(JSON.stringify({engine,mode,errors,badResponses}));
          }
          if (mode === 'fallback' ? (!fallback || wasm) : (mode === 'auto' && !wasm)) {
            throw new Error(`Unexpected compiler selection: ${engine} ${mode} wasm=${wasm} js=${fallback}`);
          }
          if (mode === 'auto' || mode === 'single-thread') {
            if (!wasm || !skwasm || fallback) throw new Error('Expected WASM + skwasm only');
            const isolated = mode === 'auto';
            if (measurements.isolated !== isolated || (startupWorkers.length > 0) !== isolated) {
              throw new Error(`Unexpected rendering isolation/worker: ${JSON.stringify({mode,workers,...measurements})}`);
            }
          }
          const remote = startupRequests.filter(url =>
            !url.startsWith(`http://127.0.0.1:${server.address().port}/`) &&
            !url.startsWith('blob:') && !url.startsWith('data:'));
          if (remote.length) throw new Error(`Third-party startup requests: ${remote.join(', ')}`);
          const item = {engine,browser:browser.version(),mode,run,wasm,skwasm,fallback,
            observedReadyMs,workers:startupWorkers,journeyRequests:requests.slice(startupRequests.length),errors,badResponses,scenarios:[fileGuard.name,...journey],...measurements};
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
    console.log(JSON.stringify({node:process.version,bundle:root,source,results},null,2));
  } finally { await new Promise(resolve=>server.close(resolve)); }
})().catch(error=>{console.error(error);process.exitCode=1;});
