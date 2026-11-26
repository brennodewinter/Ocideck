const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {pathToFileURL} = require('node:url');

const localDeck = Buffer.from('---\nmarp: true\ntitle: Browser local deck\n---\n<!-- _class: title -->\n# Browser local slide\n');
const nestedDeck = Buffer.from('---\nmarp: true\ntitle: Browser nested deck\n---\n# Browser nested slide\n\n<!-- ocideck_image_alt: Browser image -->\n![bg contain](images/browser.png)\n');
const logo = fs.readFileSync(path.join(__dirname, '../../assets/images/ocideck-logo.png'));
exports.fixtures = new Map([
  ['probe/decks/nested/deck.md', {bytes:nestedDeck, type:'text/markdown'}],
  ['probe/decks/nested/images/browser.png', {bytes:logo, type:'image/png'}],
]);

exports.observe = function observe(page) {
  const errors = [], badResponses = [], requests = [], workers = [];
  page.on('console', message => {
    if (message.type() === 'error') errors.push({kind:'console.error', text:message.text(), location:message.location()});
  });
  page.on('pageerror', error => errors.push({kind:'pageerror', text:String(error)}));
  page.on('response', response => {
    if (response.status() >= 400) badResponses.push([response.status(),response.url()]);
  });
  page.on('request', request => requests.push(request.url()));
  page.on('worker', worker => workers.push(worker.url()));
  return {errors,badResponses,requests,workers};
};
exports.assertClean = function assertClean(observed, label) {
  assert.equal(observed.errors.length + observed.badResponses.length, 0,
    `${label}: ${JSON.stringify(observed)}`);
};

async function frames(page) {
  await page.evaluate(() => new Promise(resolve => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}
async function scrollTo(page, locator) {
  await locator.waitFor({state:'attached'});
  const dialog = await page.getByRole('dialog').boundingBox();
  const top = dialog.y + 85, bottom = dialog.y + dialog.height - 65;
  const deadline = Date.now() + 15000;
  while (Date.now() < deadline) {
    const box = await locator.boundingBox();
    if (box && box.y >= top && box.y + box.height <= bottom) return;
    await page.mouse.move(dialog.x + 400, dialog.y + dialog.height / 2);
    await page.mouse.wheel(0, box && box.y < top ? -400 : 400);
    await frames(page);
  }
  throw new Error('Could not scroll the native Flutter settings pane to the control');
}
async function click(locator) {
  await locator.waitFor({state:'visible'});
  // Flutter's accessibility scroll overlays can cover a sibling DOM node.
  // The real pointer still reaches Flutter's hit test at the element's centre.
  await locator.click({force:true});
}
async function semantics(page) {
  await page.locator('flt-semantics-placeholder').waitFor({state:'attached',timeout:120000});
  // Activate the actual assistive-technology entry point; no app state is injected.
  await page.locator('flt-semantics-placeholder').dispatchEvent('click');
}
async function welcome(page) {
  await semantics(page);
  const agree = page.getByRole('button',{name:'Agree',exact:true});
  await agree.or(page.getByRole('button',{name:'Open...',exact:true})).first().waitFor({state:'visible'});
  if (await agree.count()) {
    await page.getByRole('checkbox').click();
    await agree.click();
  }
}
async function visibleText(page, text) {
  await page.getByText(text,{exact:true}).first().waitFor({state:'visible'});
}
async function styleMenu(page) {
  const manage = page.getByRole('button',{name:'Manage style profiles…',exact:true});
  if (!await manage.isVisible()) await click(page.getByRole('button',{name:'Design',exact:true}));
  await click(manage);
  await page.getByRole('textbox',{name:'Style profile',exact:true}).waitFor();
}
async function exportedLogo(page) {
  const exporting = page.waitForEvent('download');
  const button = page.getByRole('button',{name:'Export profile',exact:true});
  await scrollTo(page, button);
  await click(button);
  const download = await exporting;
  assert.equal(await download.failure(), null);
  const stream = await download.createReadStream();
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  const profile = JSON.parse(Buffer.concat(chunks));
  assert.ok(profile.profile.name, 'the exported profile must retain its name');
  assert.ok(Buffer.from(profile.logo.data,'base64').equals(logo), 'the selected logo bytes must survive style export');
  return profile.profile.name;
}
exports.fileGuard = async function fileGuard(browser, root) {
  const context = await browser.newContext();
  try {
    const page = await context.newPage();
    const observed = exports.observe(page);
    await page.goto(pathToFileURL(path.join(root,'index.html')).href);
    // file:// must stay on the explanation page, without starting the engine.
    await page.waitForTimeout(1500);
    exports.assertClean(observed, 'file:// guard');
    assert.match(await page.locator('#splash').innerText(), /cannot run from an opened file/);
    assert.ok(!observed.requests.some(url => /flutter_bootstrap|main\.dart|canvaskit/.test(url)), 'file:// must not bootstrap Flutter');
    return {name:'file-protocol-guard', errors:observed.errors};
  } finally { await context.close(); }
};
exports.journey = async function journey(page, base, observed, screenshot) {
  page.setDefaultTimeout(20000);
  await welcome(page);
  const choosing = page.waitForEvent('filechooser');
  await click(page.getByRole('button',{name:'Open...',exact:true}));
  await (await choosing).setFiles({name:'browser-local.md',mimeType:'text/markdown',buffer:localDeck});
  await page.getByRole('button',{name:/^Slide 1\/1: Browser local slide /}).waitFor({state:'visible'});
  exports.assertClean(observed, 'local deck open');
  await screenshot('local-deck');

  const url = `${base}probe/decks/nested/deck.md`;
  const imageLoaded = page.waitForResponse(r => r.url() === `${base}probe/decks/nested/images/browser.png` && r.status() === 200);
  await page.goto(`${base}?deck=${encodeURIComponent(url)}`);
  await semantics(page);
  await page.getByRole('button',{name:/^Slide 1\/1: Browser nested slide /}).waitFor({state:'visible'});
  await imageLoaded;
  assert.ok(observed.requests.includes(`${base}probe/decks/nested/images/browser.png`), 'relative image must resolve next to its nested deck');
  exports.assertClean(observed, 'nested deck and image');
  await screenshot('nested-deck');

  const saving = page.waitForEvent('download');
  await click(page.getByRole('button',{name:'Save (Ctrl/Cmd+S)',exact:true}));
  await click(page.getByRole('button',{name:'Download as a file',exact:true}));
  const saved = await saving;
  assert.equal(await saved.failure(), null);
  const chunks = [];
  for await (const chunk of await saved.createReadStream()) chunks.push(chunk);
  const markdown = Buffer.concat(chunks);
  assert.match(markdown.toString(), /images\/browser\.png/);
  assert.ok(!markdown.toString().includes(base), 'saving must preserve the relative asset reference');
  exports.fixtures.set('probe/decks/nested/saved.md', {bytes:markdown,type:'text/markdown'});
  const reloadedImage = page.waitForResponse(r => r.url() === `${base}probe/decks/nested/images/browser.png` && r.status() === 200);
  await page.goto(`${base}?deck=${encodeURIComponent(base+'probe/decks/nested/saved.md')}`);
  await semantics(page);
  await page.getByRole('button',{name:/^Slide 1\/1: Browser nested slide /}).waitFor({state:'visible'});
  await reloadedImage;
  exports.assertClean(observed, 'saved relative image reopened');

  await styleMenu(page);
  const choose = page.getByRole('button',{name:'Choose',exact:true}).first();
  await scrollTo(page, choose);
  const selecting = page.waitForEvent('filechooser');
  await click(choose);
  await (await selecting).setFiles({name:'browser-logo.png',mimeType:'image/png',buffer:logo});
  await visibleText(page,'browser-logo.png');
  await screenshot('style-logo');
  const savedProfile = await exportedLogo(page);
  await click(page.getByRole('button',{name:'Save',exact:true}));
  await page.getByRole('dialog').waitFor({state:'hidden'});
  await styleMenu(page);
  assert.equal(await exportedLogo(page), savedProfile);
  exports.assertClean(observed, 'saved style and embedded logo');
  return ['local-deck-open','nested-deck-relative-image-roundtrip','style-logo-pick-save-export'];
};
