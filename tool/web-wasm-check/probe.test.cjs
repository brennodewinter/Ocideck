const {test, before, after} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {chromium} = require('playwright');
const {observe, assertClean, fileGuard} = require('./scenarios.cjs');
let browser;
before(async () => { browser = await chromium.launch(); });
after(async () => { await browser?.close(); });

test('console.error fails even when the page does not throw or crash', async () => {
  const page = await browser.newPage();
  try {
    const observed = observe(page);
    await page.evaluate(() => console.warn('a warning is not an error'));
    assertClean(observed, 'warning');
    const message = page.waitForEvent('console', m => m.type() === 'error');
    await page.evaluate(() => console.error('browser console regression fixture'));
    await message;
    assert.throws(() => assertClean(observed, 'console fixture'), /console.error.*regression fixture/);
    assert.equal(await page.evaluate(() => 2 + 2), 4);
  } finally { await page.close(); }
});

test('the real file:// guard is clean and fails when its protocol check is removed', async () => {
  const root = path.resolve(process.env.OCIDECK_PROBE_BUNDLE || 'build/web');
  await fileGuard(browser, root);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'ocideck-web-guard-'));
  try {
    const broken = path.join(temp, 'bundle');
    fs.cpSync(root, broken, {recursive:true});
    const boot = path.join(broken, 'boot.js');
    const source = fs.readFileSync(boot, 'utf8');
    const guard = "if (location.protocol !== 'http:' && location.protocol !== 'https:')";
    assert.ok(source.includes(guard), 'the counterfactual must remove the production protocol guard');
    fs.writeFileSync(boot, source.replace(guard, 'if (false)'));
    await assert.rejects(() => fileGuard(browser, broken), /file:\/\/ guard.*console.error/s);
  } finally { fs.rmSync(temp, {recursive:true,force:true}); }
});
