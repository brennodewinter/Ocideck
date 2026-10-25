// OciDeck-web-driver voor de platformproef (#2544): rijdt de gebouwde
// webbundel in echte Chrome en vertaalt commando's uit OUT/cmd naar UI-
// handelingen op de Flutter-semantics-laag (a11y-boom, zichtbaar na de
// enable-klik) — plus beeldbewijs en browserconsole in state.log.
//
// Gebruik:
//   OCIDECK_WEB=http://127.0.0.1:8000/static/ocideck/ \
//   PROBE_OUT=probe-out/webcall/<run> node probe/webcall.js
//
// Commando's (één per regel in $OUT/cmd):
//   shot <naam>        schermafbeelding
//   click <tekst>      klik semantics-node met deze aria-label (substring)
//   fill <label>|<waarde>  textbox-label, dan getypte waarde
//   tap <x> <y>        ruwe muis-klik op CSS-coördinaten
//   key <toets>        toetsaanslag (Enter, Tab, Escape)
//   wait <ms>          wachten
//   dump               schrijf semantics-boom naar dump.txt
//   done               browser sluiten en eindigen
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const APP = process.env.OCIDECK_WEB || 'http://127.0.0.1:8000/static/ocideck/';
const OUT = process.env.PROBE_OUT || path.join(__dirname, 'probe-out', 'webcall', 'run');
const CMD = path.join(OUT, 'cmd');
fs.mkdirSync(OUT, { recursive: true });
fs.writeFileSync(CMD, '');
const LOG = fs.createWriteStream(path.join(OUT, 'state.log'));

let page;
let shots = 0;
const stamp = () => new Date().toISOString().slice(11, 19);
const say = (m) => { LOG.write(`[${stamp()}] ${m}\n`); };

async function shot(name) {
  const f = path.join(OUT, `shot-${String(shots++).padStart(2, '0')}-${name}.png`);
  await page.screenshot({ path: f }).catch((e) => say(`shot ${name} faalde: ${e.message}`));
  say(`shot ${name}`);
}

// Klik een semantics-node op aria-label-substring. Flutter's a11y-laag levert
// <flt-semantics role=… aria-label=…> in een shadow-root; playwright's css
// doorbreekt die standaard.
async function clickLabel(text) {
  const loc = page.locator(`flt-semantics[aria-label*="${cssEscape(text)}"]`).last();
  await loc.scrollIntoViewIfNeeded().catch(() => {});
  await loc.click({ timeout: 5000 });
  say(`click "${text}"`);
}
function cssEscape(s) { return s.replace(/["\\]/g, '\\$&'); }

async function fillLabel(label, value) {
  const loc = page.locator(`flt-semantics[aria-label*="${cssEscape(label)}"]`).last();
  await loc.click({ timeout: 5000 });
  await page.keyboard.type(value);
  say(`fill "${label}" = "${value}"`);
}

async function dump() {
  const nodes = await page.evaluate(() => {
    const out = [];
    const root = document.querySelector('flt-semantics-host') || document;
    root.querySelectorAll('flt-semantics').forEach((n) => {
      const r = n.getBoundingClientRect();
      const label = n.getAttribute('aria-label');
      if (label || n.getAttribute('role') === 'button') {
        out.push(`${n.getAttribute('role') || '?'}|${label || ''}|${Math.round(r.x)},${Math.round(r.y)},${Math.round(r.width)}x${Math.round(r.height)}`);
      }
    });
    return out;
  });
  fs.writeFileSync(path.join(OUT, 'dump.txt'), nodes.join('\n') + '\n');
  say(`dump: ${nodes.length} nodes`);
}

// De verborgen "Enable accessibility"-knop van Flutter web: eenmaal geklikt
// groeit de echte semantics-boom. Voor die klik bestaat hij nog niet als
// flt-semantics maar als placeholder in dezelfde shadow-root.
async function enableSemantics() {
  for (let i = 0; i < 40; i++) {
    const ok = await page.evaluate(() => {
      const ph = document.querySelector('flt-semantics-placeholder') ||
        document.querySelector('flt-glass-pane')?.shadowRoot
          ?.querySelector('flt-semantics-placeholder');
      if (ph) { ph.dispatchEvent(new MouseEvent('click', { bubbles: true })); return 'clicked'; }
      if (document.querySelector('flt-semantics')) return 'already';
      return 'wait';
    }).catch(() => 'wait');
    if (ok === 'clicked' || ok === 'already') { say(`semantics: ${ok}`); return true; }
    await new Promise((r) => setTimeout(r, 500));
  }
  say('semantics: placeholder niet gevonden');
  return false;
}

async function run(line) {
  const [cmd, ...rest] = line.trim().split(/\s+/);
  const arg = rest.join(' ');
  try {
    if (cmd === 'shot') await shot(arg || 'x');
    else if (cmd === 'click') await clickLabel(arg);
    else if (cmd === 'semantics') await enableSemantics();
    else if (cmd === 'reload') { await page.reload(); say('reload'); }
    else if (cmd === 'fill') {
      const [label, ...v] = arg.split('|');
      await fillLabel(label.trim(), v.join('|').trim());
    } else if (cmd === 'tap') {
      const [x, y] = arg.split(/\s+/).map(Number);
      await page.mouse.click(x, y);
      say(`tap ${x},${y}`);
    } else if (cmd === 'tapcanvas') {
      // Klik op de Flutter-canvas door de a11y-laag heen — zet pointer-events
      // uit op flt-glass-pane, klik, wacht op een TextInput-input in de shadow
      // root, zet pointer-events terug.
      const [x, y] = arg.split(/\s+/).map(Number);
      await page.evaluate(() => {
        const g = document.querySelector('flt-glass-pane');
        if (g) g.style.pointerEvents = 'none';
      });
      await page.mouse.click(x, y);
      await new Promise((r) => setTimeout(r, 2000));
      await page.evaluate(() => {
        const g = document.querySelector('flt-glass-pane');
        if (g) g.style.pointerEvents = '';
      });
      say(`tapcanvas ${x},${y}`);
    } else if (cmd === 'key') {
      await page.keyboard.press(arg);
      say(`key ${arg}`);
    } else if (cmd === 'type') {
      await page.keyboard.type(arg, { delay: 30 });
      say(`type "${arg}"`);
    } else if (cmd === 'inserttext') {
      // inserttext <tekst> — stuurt één input-event via execCommand('insertText').
      // Gebruik na tapcanvas: activeert Flutter's TextInputHandler zonder
      // verdubbeling (keyboard.type stuurt per-toets keydown naar zowel de
      // DOM input als Flutter's handler).
      await page.evaluate((t) => document.execCommand('insertText', false, t), arg);
      say(`inserttext "${arg}"`);
    } else if (cmd === 'fillinput') {
      // fillinput <aria-label>|<waarde> — focus de hidden input en typ via keyboard
      const [label, ...v] = arg.split('|');
      const val = v.join('|').trim();
      const loc = page.locator(`input[aria-label="${label.trim()}"],textarea[aria-label="${label.trim()}"]`);
      await loc.focus({ timeout: 3000 });
      await page.keyboard.type(val, { delay: 50 });
      say(`fillinput "${label}" = "${val}"`);
    } else if (cmd === 'openfile') {
      // openfile <pad>|<knop-x> <knop-y> — wacht op file-chooser, klik knop, set bestand
      const [filePath, xy] = arg.split('|');
      const [bx, by] = xy.trim().split(/\s+/).map(Number);
      const fcPromise = page.waitForEvent('filechooser', { timeout: 5000 });
      await page.mouse.click(bx, by);
      const fc = await fcPromise;
      await fc.setFiles(filePath.trim());
      say(`openfile ${filePath} via (${bx},${by})`);
    } else if (cmd === 'eval') {
      const r = await page.evaluate(arg);
      say(`eval: ${JSON.stringify(r)}`);
    } else if (cmd === 'fillxy') {
      // tap <x> <y>|<tekst> — klik, wacht, typ in wat dan focus heeft
      const [xy, ...v] = arg.split('|');
      const [x, y] = xy.trim().split(/\s+/).map(Number);
      await page.mouse.click(x, y);
      await new Promise((r) => setTimeout(r, 800));
      await page.keyboard.type(v.join('|').trim());
      say(`fillxy ${x},${y} = "${v.join('|').trim()}"`);
    } else if (cmd === 'wait') await new Promise((r) => setTimeout(r, Number(arg) || 1000));
    else if (cmd === 'dump') await dump();
    else if (cmd === 'done') return false;
    else say(`onbekend commando: ${line}`);
    say(`ok: ${line}`);
  } catch (e) {
    say(`FAIL: ${line} — ${e.message.slice(0, 160)}`);
  }
  return true;
}

(async () => {
  const browser = await chromium.launch({
    channel: 'chrome',
    headless: true,
    args: [
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      '--auto-select-desktop-capture-source=Entire screen',
      '--autoplay-policy=no-user-gesture-required',
      '--mute-audio',
    ],
  });
  const ctx = await browser.newContext({
    permissions: ['microphone', 'camera', 'clipboard-read'],
    ignoreHTTPSErrors: true,
    viewport: { width: 1440, height: 900 },
  });
  // De module is default-uit; dezelfde prefs-vlag als de instellingenkaart
  // schrijft — maar dan deterministisch vóór de eerste frame.
  await ctx.addInitScript(() => {
    try {
      localStorage.setItem('flutter.videoCallsModuleEnabled', 'true');
      localStorage.setItem('flutter.app_consent_accepted', 'true');
      localStorage.setItem('flutter.meetingProviderProfiles', JSON.stringify([
        {"id":"testbed","providerId":"jitsi","origin":"http://127.0.0.1:8000","allowedJoinPathPrefixes":[],"trustedInternal":true,"pinnedCertSha256":""},
      ]));
    } catch {}
  });
  page = await ctx.newPage();
  page.on('console', (m) => {
    if (m.type() === 'error' || m.type() === 'warning') {
      say(`[browser:${m.type()}] ${m.text().slice(0, 200)}`);
    }
  });
  page.on('pageerror', (e) => say(`[pageerror] ${String(e).slice(0, 200)}`));

  say(`open ${APP}`);
  await page.goto(APP, { waitUntil: 'domcontentloaded', timeout: 60000 });
  // flt-glass-pane staat ook na renderen op 'hidden' voor playwright's
  // zichtbaarheidsregel — 'attached' + de eerste echte frame is de waarheid.
  await page.waitForSelector('flt-glass-pane', {
    state: 'attached',
    timeout: 120000,
  });
  await page.waitForFunction(
    () => document.querySelector('flutter-view')?.shadowRoot ||
      document.querySelector('flt-scene-host, flt-semantics-placeholder'),
    { timeout: 120000 },
  );
  say('flutter geladen');
  await enableSemantics();
  await shot('opstart');

  // Commandolijnen verwerken: elke nieuwe regel in OUT/cmd wordt één stap.
  let consumed = 0;
  const deadline = Date.now() + 6 * 3600 * 1000;
  while (Date.now() < deadline) {
    const lines = fs.readFileSync(CMD, 'utf8').split('\n').filter(Boolean);
    while (consumed < lines.length) {
      const go = await run(lines[consumed++]);
      if (!go) { await browser.close(); LOG.end(); process.exit(0); }
    }
    await new Promise((r) => setTimeout(r, 300));
  }
  await browser.close();
  LOG.end();
  process.exit(0);
})().catch(async (e) => {
  say(`FATAAL: ${e.message}`);
  LOG.end();
  process.exit(1);
});

process.on('SIGINT', () => { say('SIGINT'); process.exit(0); });
process.on('SIGTERM', () => { say('SIGTERM'); process.exit(0); });
