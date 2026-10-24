// Wire-capture: twee echte Jitsi-clients joinen het testbed terwijl CDP
// alle WebSocket-frames (Strophe's XMPP-stanzas) naar /tmp dumpt. Dit is
// hoe de wire-waarheid uit #2534 is vastgelegd — draai hem opnieuw bij een
// Jitsi-versiebump om het contract opnieuw te verifiëren.
const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');

const BASE = process.env.BASE_URL || 'http://localhost:8000';
const ROOM = process.env.ROOM || `wire${Date.now() % 100000}`;
const HOST_PW = process.env.TEST_HOST_PASSWORD;
const OUT = '/tmp/jitsi-wire';
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
  const log = fs.createWriteStream(path.join(OUT, `${name}-ws.log`));
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable');
  cdp.on('Network.webSocketFrameSent', (e) => {
    log.write(`>>> ${e.response.payloadData}\n`);
  });
  cdp.on('Network.webSocketFrameReceived', (e) => {
    log.write(`<<< ${e.response.payloadData}\n`);
  });
  return { browser, page, name };
}

(async () => {
  const roomUrl = `${BASE}/${ROOM}#config.prejoinConfig.enabled=false`;
  console.log('room:', roomUrl);

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
  } catch (e) { console.log('host: geen auth-dialoog'); }

  const hostJoined = await host.page
    .waitForFunction(() => {
      try { return window.APP && APP.conference.isJoined() === true; }
      catch { return false; }
    }, { timeout: 30000 })
    .then(() => true).catch(() => false);
  console.log('host joined:', hostJoined);

  const guest = await openClient('guest');
  await guest.page.goto(roomUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  const guestJoined = await guest.page
    .waitForFunction(() => {
      try { return window.APP && APP.conference.isJoined() === true; }
      catch { return false; }
    }, { timeout: 30000 })
    .then(() => true).catch(() => false);
  console.log('guest joined:', guestJoined);

  await new Promise((r) => setTimeout(r, 12000));
  for (const c of [host, guest]) {
    await Promise.race([c.browser.close(), new Promise((r) => setTimeout(r, 4000))]);
  }
  console.log('captures in', OUT);
  process.exit(hostJoined && guestJoined ? 0 : 1);
})().catch((e) => { console.error('FAIL', e); process.exit(1); });
