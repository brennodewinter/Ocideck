const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const test = require('node:test');
const html = fs.readFileSync(process.env.OCIDECK_VIDEO_HTML, 'utf8');
const script = html.match(/<script>([\s\S]*?)<\/script>/)[1];
test('production Vimeo player bounds every late seek and resets replay once', () => {
  const events = {}, actions = [], messages = [];
  class Player {
    on(name, callback) { events[name] = callback; }
    pause() { actions.push(['pause']); return Promise.resolve(); }
    setCurrentTime(time) { actions.push(['seek', time]); return Promise.resolve(); }
  }
  vm.runInNewContext(script, {document: {getElementById: () => ({})},
    window: {Vimeo: true}, Vimeo: {Player},
    OciDeck: {postMessage: message => (() => {assert.match(message, /^\d+\|/); messages.push(message.slice(message.indexOf('|') + 1));})()}, setTimeout: () => {}});
  events.timeupdate({seconds: 0});
  assert.deepEqual(actions.at(-1), ['seek', 10]);
  events.timeupdate({seconds: 30});
  events.timeupdate({seconds: 45});
  assert.equal(messages.filter(message => message === 'ended').length, 1);
  assert.deepEqual(actions.slice(-4), [['pause'], ['seek', 30], ['pause'], ['seek', 30]]);
  assert(!messages.includes('pos:45000'));
  events.play();
  assert.deepEqual(actions.at(-1), ['seek', 10]);
  events.timeupdate({seconds: 12});
  events.timeupdate({seconds: 30});
  assert.equal(messages.filter(message => message === 'ended').length, 2);
});
