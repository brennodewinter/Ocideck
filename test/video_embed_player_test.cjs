const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');
const html = fs.readFileSync(process.env.OCIDECK_VIDEO_HTML, 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
const origin = 'https://www.youtube-nocookie.com';
function player() {
  const commands = [], messages = [], timers = [], elements = {};
  const frame = {postMessage: (text, target) => {
    assert.equal(target, origin); commands.push(JSON.parse(text));
  }};
  for (const name of ['f', 'recovery', 'play', 'reason']) {
    elements[name] = {style: {}, contentWindow: frame, events: {},
      addEventListener(name, callback) {this.events[name] = callback;}};
  }
  const window = {addEventListener(name, callback) {this[name] = callback;}};
  vm.runInNewContext(script, {document: {getElementById: id => elements[id]},
    window, OciDeck: {postMessage: message => (() => {assert.match(message, /^\d+\|/); messages.push(message.slice(message.indexOf('|') + 1));})()},
    setTimeout: (callback, delay) => timers.push({callback, delay}),
    setInterval: () => 1, clearInterval: () => {}});
  const event = (name, info, overrides = {}) => window.message({origin,
    source: frame, data: JSON.stringify({event: name, info}), ...overrides});
  return {commands, messages, timers, elements, event};
}
test('handshake subscribes to real events; ready does not mean playing', () => {
  const p = player(); p.event('initialDelivery', {playerState: -1, currentTime: 10});
  assert(p.messages.includes('ok'));
  assert(!p.messages.includes('playback:playing'));
  assert.deepEqual(p.commands.filter(c => c.func === 'addEventListener').map(c => c.args[0]),
    ['onReady','onStateChange','onError','onAutoplayBlocked']);
  assert(p.commands.every(c => c.id === 1 && c.channel === 'widget'));
  p.event('onReady');
  assert.equal(p.commands.filter(c => c.func === 'addEventListener').length, 4);
});
test('blocked autoplay exposes a real click action without reload or mute', () => {
  const p = player(); p.event('onAutoplayBlocked');
  assert.equal(p.elements.recovery.style.display, 'flex');
  assert(p.messages.includes('playback:blocked'));
  p.elements.play.events.click();
  assert.equal(p.commands.at(-1).func, 'playVideo');
  assert(!p.commands.some(c => c.func === 'mute' || c.func === 'loadVideoById'));
  p.event('onStateChange', 1);
  assert.equal(p.elements.recovery.style.display, 'none');
  p.timers.find(t => t.delay === 6000).callback();
  assert.equal(p.elements.recovery.style.display, 'none');
});
test('silent ready player offers recovery, silent unloaded frame is an error', () => {
  const p = player(); p.event('onReady');
  p.timers.find(t => t.delay === 6000).callback();
  assert(p.messages.includes('playback:waiting'));
  p.timers.find(t => t.delay === 8000).callback();
  assert(!p.messages.includes('err:noapi'));
  const silent = player(); silent.timers.find(t => t.delay === 8000).callback();
  assert(silent.messages.includes('err:noapi'));
});
test('origin and exact iframe source are required', () => {
  const p = player();
  p.event('onStateChange', 1, {origin: 'https://evil.example'});
  p.event('onStateChange', 1, {source: {}});
  assert(!p.messages.includes('playback:playing'));
  assert.equal(p.commands.length, 0);
});
test('every late seek is clamped after a single end notification', () => {
  const p = player();
  p.event('infoDelivery', {currentTime: 30});
  p.event('infoDelivery', {currentTime: 40});
  assert.equal(p.messages.filter(m => m === 'ended').length, 1);
  assert.deepEqual(p.commands.filter(c => c.func === 'seekTo').map(c => c.args),
    [[30, true], [30, true]]);
  assert.equal(p.commands.filter(c => c.func === 'pauseVideo').length, 2);
  assert(!p.messages.includes('pos:40000'));
  p.elements.play.events.click();
  assert.deepEqual(p.commands.at(-2).args, [10, true]);
  assert.equal(p.commands.at(-1).func, 'playVideo');
});
test('seek before clip start is corrected; seek progress is not playback proof', () => {
  const p = player(); p.event('infoDelivery', {currentTime: 0});
  assert.deepEqual(p.commands.at(-1).args, [10, true]);
  p.event('infoDelivery', {currentTime: 10});
  p.event('infoDelivery', {currentTime: 10.2});
  assert(!p.messages.includes('playback:playing'));
  p.event('onStateChange', 1);
  assert(p.messages.includes('playback:playing'));
  assert(!p.messages.includes('ended'));
});
