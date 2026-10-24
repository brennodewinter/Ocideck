const { chromium } = require('playwright-core');
const fs = require('fs');
const path = require('path');
const BASE = process.env.BASE_URL || 'http://localhost:8000';
const ROOM = process.env.ROOM || `wirem${Date.now() % 100000}`;
const HOST_PW = process.env.TEST_HOST_PASSWORD;
const OUT = '/tmp/jitsi-wire-mute';
fs.mkdirSync(OUT, { recursive: true });
const LAUNCH = { channel: 'chrome', headless: true, args: [
  '--use-fake-device-for-media-stream','--use-fake-ui-for-media-stream',
  '--autoplay-policy=no-user-gesture-required','--mute-audio'] };
async function openClient(name) {
  const browser = await chromium.launch(LAUNCH);
  const ctx = await browser.newContext({ permissions: ['microphone','camera'], ignoreHTTPSErrors: true });
  const page = await ctx.newPage();
  const log = fs.createWriteStream(path.join(OUT, `${name}-ws.log`));
  const cdp = await ctx.newCDPSession(page);
  await cdp.send('Network.enable');
  cdp.on('Network.webSocketFrameSent', (e) => log.write(`>>> ${e.response.payloadData}\n`));
  cdp.on('Network.webSocketFrameReceived', (e) => log.write(`<<< ${e.response.payloadData}\n`));
  return { browser, page, name, log };
}
(async () => {
  const roomUrl = `${BASE}/${ROOM}#config.prejoinConfig.enabled=false`;
  const host = await openClient('host');
  await host.page.goto(roomUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  try {
    await host.page.click('button:has-text("Inloggen"), button:has-text("Log in"), button:has-text("Sign in")', { timeout: 15000 });
    await host.page.waitForSelector('input[name="username"], #username', { timeout: 8000 });
    await host.page.fill('input[name="username"], #username', 'host');
    await host.page.fill('input[name="password"], #password', HOST_PW);
    await host.page.click('#modal-dialog-ok-button, button[type="submit"], button:has-text("OK")');
  } catch (e) {}
  await host.page.waitForFunction(() => { try { return window.APP && APP.conference.isJoined() === true; } catch { return false; } }, { timeout: 30000 });
  const guest = await openClient('guest');
  await guest.page.goto(roomUrl, { waitUntil: 'domcontentloaded', timeout: 30000 });
  await guest.page.waitForFunction(() => { try { return window.APP && APP.conference.isJoined() === true; } catch { return false; } }, { timeout: 30000 });
  console.log('both joined');
  host.log.write('\n=== MUTE-PHASE ===\n');
  await new Promise(r => setTimeout(r, 3000));
  // guest mutes audio then video
  await guest.page.evaluate(() => APP.conference.muteAudio(true));
  await new Promise(r => setTimeout(r, 2500));
  await guest.page.evaluate(() => APP.conference.muteVideo(true));
  await new Promise(r => setTimeout(r, 2500));
  // host grants nothing; guest unmutes audio
  await guest.page.evaluate(() => APP.conference.muteAudio(false));
  await new Promise(r => setTimeout(r, 2500));
  // guest leaves
  guest.log.write('\n=== LEAVE-PHASE ===\n');
  await guest.page.evaluate(() => APP.conference.hangup());
  await new Promise(r => setTimeout(r, 4000));
  console.log('done; captures in', OUT);
  for (const c of [host, guest]) await Promise.race([c.browser.close(), new Promise(r => setTimeout(r, 4000))]);
  process.exit(0);
})().catch(e => { console.error('FAIL', e); process.exit(1); });
