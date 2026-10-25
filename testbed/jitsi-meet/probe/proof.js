// Tegenpartij-probe voor de platformproeven (#2541/#2544): één echte
// Chrome-deelnemer met fake-device-signaal die in de room blijft en —
// anders dan solo.js — ook de REMOTE track details en periodieke
// screenshots vastlegt. Dat is het bewijs dat OciDeck's mic/cam/scherm
// bij een onafhankelijke client aankomt (videoType 'desktop' bij delen).
//
// Gebruik:
//   set -a && . ../.env && set +a
//   ROOM=ocideckproef-<datum> DURATION_MS=1800000 node probe/proof.js
//
// Output: probe-out/proof/<ROOM>/state.log (5s-regels) + shot-*.png.
// Stop netjes met SIGINT/SIGTERM — de browser sluit dan en de laatste
// state-regel wordt nog geschreven.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE_URL || 'http://127.0.0.1:8000';
const ROOM = process.env.ROOM || 'ocideckproof';
const HOST_PW = process.env.TEST_HOST_PASSWORD;
const DURATION_MS = Number(process.env.DURATION_MS || 1800000);
const OUT = process.env.PROBE_OUT ||
  path.join(__dirname, 'probe-out', 'proof', ROOM);
fs.mkdirSync(OUT, { recursive: true });
const LOG = fs.createWriteStream(path.join(OUT, 'state.log'));

if (!HOST_PW) {
  console.error('TEST_HOST_PASSWORD ontbreekt — source testbed/jitsi-meet/.env');
  process.exit(2);
}

let phase = 'opstarten';
let page;

function stamp() {
  return new Date().toISOString().slice(11, 19);
}

// Markeer het begin van een proefstap zodat state.log-regels aan een
// PROCEDURE.md-stap hangen: `node probe/proof.js` print dit zelf niet —
// de bestuurder schrijft `echo <n> > OUT/phase` en de poll leest hem.
function currentPhase() {
  try {
    const p = fs.readFileSync(path.join(OUT, 'phase'), 'utf8').trim();
    if (p && p !== phase) phase = p;
  } catch { /* geen fasebestand: laatste fase geldt */ }
  return phase;
}

async function state() {
  return page.evaluate(() => {
    const tracks = APP.store.getState()['features/base/tracks'] || [];
    const remote = tracks.filter((t) => !t.local).map((t) =>
      `${t.mediaType}:${t.muted ? 'muted' : 'live'}:${t.videoType ?? ''}`);
    return {
      joined: (() => { try { return APP.conference.isJoined(); } catch { return undefined; } })(),
      members: (() => { try { return APP.conference.membersCount(); } catch { return undefined; } })(),
      localTracks: tracks.filter((t) => t.local)
        .map((t) => `${t.mediaType}:${t.muted ? 'muted' : 'live'}:${t.videoType ?? ''}`).join(','),
      remoteTracks: remote.join(','),
      remoteVideos: [...document.querySelectorAll('video')]
        .filter((v) => !v.paused && v.currentTime > 0).length,
      remoteAudios: [...document.querySelectorAll('audio')]
        .filter((a) => !a.paused && a.currentTime > 0).length,
    };
  }).catch(() => ({}));
}

let shots = 0;
async function snapshot() {
  try {
    await page.screenshot({ path: path.join(OUT, `shot-${String(shots++).padStart(2, '0')}-${phase}.png`) });
  } catch { /* pagina aan het laden */ }
}

(async () => {
  const browser = await chromium.launch({
    channel: 'chrome',
    headless: true,
    args: [
      '--use-fake-device-for-media-stream',
      '--use-fake-ui-for-media-stream',
      '--autoplay-policy=no-user-gesture-required',
      '--mute-audio',
    ],
  });
  const ctx = await browser.newContext({
    permissions: ['microphone', 'camera'],
    ignoreHTTPSErrors: true,
  });
  page = await ctx.newPage();
  page.on('console', (m) => {
    if (m.type() === 'error') LOG.write(`[${stamp()}] [browser] ${m.text().slice(0, 200)}\n`);
  });

  const roomUrl = `${BASE}/${ROOM}#config.prejoinConfig.enabled=false`;
  LOG.write(`[${stamp()}] room: ${roomUrl}\n`);
  await page.goto(roomUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  try {
    await page.click(
      'button:has-text("Inloggen"), button:has-text("Log in"), button:has-text("Sign in")',
      { timeout: 15000 });
    await page.waitForSelector('input[name="username"], #username', { timeout: 8000 });
    await page.fill('input[name="username"], #username', 'host');
    await page.fill('input[name="password"], #password', HOST_PW);
    await page.click(
      '#modal-dialog-ok-button, button[type="submit"], button:has-text("OK"), button:has-text("Inloggen"), button:has-text("Log in")');
    LOG.write(`[${stamp()}] host: credentials ingediend\n`);
  } catch (e) { LOG.write(`[${stamp()}] host: geen auth-dialoog — ${e.message.slice(0, 120)}\n`); }

  const joined = await page
    .waitForFunction(() => {
      try { return window.APP && APP.conference.isJoined() === true; }
      catch { return false; }
    }, { timeout: 30000 })
    .then(() => true).catch(() => false);
  LOG.write(`[${stamp()}] host joined: ${joined}\n`);
  if (!joined) process.exit(1);

  // Zelfde unmute als solo.js: jicofo joint deze deployment gemuteerd.
  for (let attempt = 0; attempt < 12; attempt++) {
    const live = await page.evaluate(async () => {
      try {
        await APP.conference.muteAudio(false);
        await APP.conference.muteVideo(false);
        return {
          a: APP.conference.isLocalAudioMuted(),
          v: APP.conference.isLocalVideoMuted(),
        };
      } catch (e) { return { err: String(e).slice(0, 80) }; }
    });
    if (live.a === false && live.v === false) {
      LOG.write(`[${stamp()}] host media live\n`);
      break;
    }
    if (attempt === 11) LOG.write(`[${stamp()}] host unmute faalde: ${JSON.stringify(live)}\n`);
    await new Promise((r) => setTimeout(r, 2500));
  }

  let ticks = 0;
  const deadline = Date.now() + DURATION_MS;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 5000));
    const s = await state();
    LOG.write(`[${stamp()}] [fase ${currentPhase()}] ${JSON.stringify(s)}\n`);
    if (ticks % 6 === 0) await snapshot(); // elke 30s een beeld van B
    ticks++;
  }
  await Promise.race([
    browser.close(),
    new Promise((r) => setTimeout(r, 5000)),
  ]);
  LOG.end();
  process.exit(0);
})().catch((e) => {
  LOG.write(`[${stamp()}] FATAAL: ${e.message}\n`);
  LOG.end();
  process.exit(1);
});

process.on('SIGINT', () => { LOG.write(`[${stamp()}] SIGINT\n`); process.exit(0); });
process.on('SIGTERM', () => { LOG.write(`[${stamp()}] SIGTERM\n`); process.exit(0); });
