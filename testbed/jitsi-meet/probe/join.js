// Geautomatiseerde tweepersoonsproef voor het gepinde Jitsi-testbed (#2540).
//
// Twee echte Chrome-instanties (geen fake adapter): de host logt in met het
// geregistreerde XMPP-account, de guest komt anoniem via guest.meet.jitsi
// binnen. Chrome's --use-fake-device-* levert een deterministisch
// audio-/videosignaal; media loopt via de JVB (P2P staat uit in .env).
//
// Gebruik:
//   npm --prefix probe install          (eenmalig, playwright-core + systeem-Chrome)
//   set -a && . ../.env && set +a       (TEST_HOST_PASSWORD uit .env)
//   node probe/join.js
//
// Exitcode 0 als beide clients joinen; eind-state + screenshots in $PROBE_OUT.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE_URL || 'http://localhost:8000';
const ROOM = process.env.ROOM || `ocideckprobe${Date.now() % 100000}`;
const HOST_PW = process.env.TEST_HOST_PASSWORD;
const OUT = process.env.PROBE_OUT || path.join(__dirname, 'probe-out');
fs.mkdirSync(OUT, { recursive: true });

const LAUNCH = {
  channel: 'chrome',
  headless: true,
  args: [
    '--use-fake-device-for-media-stream',
    '--use-fake-ui-for-media-stream',
    '--autoplay-policy=no-user-gesture-required',
    '--mute-audio',
  ],
};

async function openClient(name) {
  const browser = await chromium.launch(LAUNCH);
  const ctx = await browser.newContext({
    permissions: ['microphone', 'camera'],
    ignoreHTTPSErrors: true,
  });
  const page = await ctx.newPage();
  page.on('console', (m) => {
    if (m.type() === 'error') console.log(`[${name}]`, m.text().slice(0, 200));
  });
  return { browser, page, name };
}

async function state(page) {
  return page.evaluate(() => ({
    joined: (() => { try { return APP.conference.isJoined(); } catch { return undefined; } })(),
    members: (() => { try { return APP.conference.membersCount(); } catch { return undefined; } })(),
    remoteVideos: [...document.querySelectorAll('video')]
      .filter((v) => !v.paused && v.currentTime > 0).length,
    remoteAudios: [...document.querySelectorAll('audio')]
      .filter((a) => !a.paused && a.currentTime > 0).length,
    connState: (() => { try { return APP.conference.getConnectionState(); } catch { return undefined; } })(),
  })).catch(() => ({}));
}

(async () => {
  const roomUrl = `${BASE}/${ROOM}#config.prejoinConfig.enabled=false`;
  console.log('room:', roomUrl);

  // ── host: join + inloggen als geregistreerde gebruiker ───────────────
  const host = await openClient('host');
  await host.page.goto(roomUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  try {
    await host.page.click(
      'button:has-text("Inloggen"), button:has-text("Log in"), button:has-text("Sign in")',
      { timeout: 15000 });
    await host.page.waitForSelector('input[name="username"], #username', { timeout: 8000 });
    await host.page.fill('input[name="username"], #username', 'host');
    await host.page.fill('input[name="password"], #password', HOST_PW);
    await host.page.click(
      '#modal-dialog-ok-button, button[type="submit"], button:has-text("OK"), button:has-text("Inloggen"), button:has-text("Log in")');
    console.log('host: credentials ingediend');
  } catch (e) { console.log('host: geen auth-dialoog —', e.message.slice(0, 120)); }

  const hostJoined = await host.page
    .waitForFunction(() => {
      try { return window.APP && APP.conference.isJoined() === true; }
      catch { return false; }
    }, { timeout: 30000 })
    .then(() => true).catch(() => false);
  console.log('host joined:', hostJoined, JSON.stringify(await state(host.page)));

  // ── guest: anoniem joinen in de bestaande kamer ──────────────────────
  const guest = await openClient('guest');
  await guest.page.goto(roomUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  const guestJoined = await guest.page
    .waitForFunction(() => {
      try { return window.APP && APP.conference.isJoined() === true; }
      catch { return false; }
    }, { timeout: 30000 })
    .then(() => true).catch(() => false);
  console.log('guest joined:', guestJoined, JSON.stringify(await state(guest.page)));

  // ── 15s draaien voor ICE + media ─────────────────────────────────────
  await new Promise((r) => setTimeout(r, 15000));
  for (const [n, c] of [['host', host], ['guest', guest]]) {
    console.log(`${n} eind-state:`, JSON.stringify(await state(c.page)));
    await c.page.screenshot({ path: path.join(OUT, `${n}.png`) });
  }

  // browser.close() blijft op macOS met channel:'chrome' soms hangen —
  // de bewijslast is dan al gelegd, dus niet langer wachten dan nodig.
  for (const c of [host, guest]) {
    await Promise.race([
      c.browser.close(),
      new Promise((r) => setTimeout(r, 5000)),
    ]);
  }

  if (!(hostJoined && guestJoined)) {
    console.error('NIET geslaagd: beide clients moeten joinen.');
    process.exit(1);
  }
  console.log('Geslaagd: twee echte clients in', ROOM, '— screenshots in', OUT);
  process.exit(0);
})().catch((e) => { console.error('FAIL', e); process.exit(1); });
