// Eén browser-deelnemer als tegenpartij voor de macOS-mediaproof (#2535).
//
// Anders dan probe/join.js (twee clients die elkaar bewijzen) is dit de
// tegenpartij voor OciDeck zelf: de host logt in met het geregistreerde
// account, joint met Chrome's --use-fake-device-* (deterministisch
// audio/videosignaal, echte RTP via de JVB) en blijft DURATION_MS in de
// kamer. OciDeck joint ondertussen anoniem als gast; de probe logt wat de
// browser aan remote tracks ziet — waaronder OciDeck's eigen mic/cam.
// jitsi-meet joint zónder media als de prejoin-stap via de URL uit staat —
// de probe unmuted daarom expliciet na de join.
//
// Gebruik:
//   set -a && . ../.env && set +a
//   DURATION_MS=1200000 ROOM=ocideck_media_it node probe/solo.js
const { chromium } = require('playwright-core');

const BASE = process.env.BASE_URL || 'http://127.0.0.1:8000';
const ROOM = process.env.ROOM || 'ocideck_media_it';
const HOST_PW = process.env.TEST_HOST_PASSWORD;
const DURATION_MS = Number(process.env.DURATION_MS || 240000);

if (!HOST_PW) {
  console.error('TEST_HOST_PASSWORD ontbreekt — source testbed/jitsi-meet/.env');
  process.exit(2);
}

async function state(page) {
  return page.evaluate(() => ({
    joined: (() => { try { return APP.conference.isJoined(); } catch { return undefined; } })(),
    members: (() => { try { return APP.conference.membersCount(); } catch { return undefined; } })(),
    // De lokale fake-device tracks staan in de redux-store
    // (features/base/tracks, local:true); audioMuted/videoMuted zijn wat
    // de client zelf aan jicofo rapporteert.
    localTracks: (() => {
      try {
        const tracks = APP.store.getState()['features/base/tracks'] || [];
        return tracks.filter((t) => t.local)
          .map((t) => `${t.mediaType}:${t.muted ? 'muted' : 'live'}:${t.videoType ?? ''}`)
          .join(',');
      } catch { return undefined; }
    })(),
    audioMuted: (() => { try { return APP.conference.isLocalAudioMuted(); } catch { return undefined; } })(),
    videoMuted: (() => { try { return APP.conference.isLocalVideoMuted(); } catch { return undefined; } })(),
    remoteVideos: [...document.querySelectorAll('video')]
      .filter((v) => !v.paused && v.currentTime > 0).length,
    remoteAudios: [...document.querySelectorAll('audio')]
      .filter((a) => !a.paused && a.currentTime > 0).length,
  })).catch(() => ({}));
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
  const page = await ctx.newPage();
  page.on('console', (m) => {
    if (m.type() === 'error') console.log('[host]', m.text().slice(0, 200));
  });

  const roomUrl = `${BASE}/${ROOM}#config.prejoinConfig.enabled=false`;
  console.log('room:', roomUrl);
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
    console.log('host: credentials ingediend');
  } catch (e) { console.log('host: geen auth-dialoog —', e.message.slice(0, 120)); }

  const joined = await page
    .waitForFunction(() => {
      try { return window.APP && APP.conference.isJoined() === true; }
      catch { return false; }
    }, { timeout: 30000 })
    .then(() => true).catch(() => false);
  console.log('host joined:', joined, JSON.stringify(await state(page)));
  if (!joined) process.exit(1);

  // De probe moet écht media sturen — jitsi-meet joint op deze deployment
  // gemuteerd (jicofo: audioMuted=true videoMuted=true). Unmute expliciet;
  // de fake-device levert dan een deterministisch signaal via de JVB.
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
      console.log('host media live:', JSON.stringify(await state(page)));
      break;
    }
    if (attempt === 11) console.log('host unmute faalde:', JSON.stringify(live));
    await new Promise((r) => setTimeout(r, 2500));
  }

  const deadline = Date.now() + DURATION_MS;
  while (Date.now() < deadline) {
    await new Promise((r) => setTimeout(r, 5000));
    console.log('host state:', JSON.stringify(await state(page)));
  }
  await Promise.race([
    browser.close(),
    new Promise((r) => setTimeout(r, 5000)),
  ]);
  process.exit(0);
})();
