// Tests for parseJitsiConfig (#2533): the comment-aware, last-wins reader for
// a Jitsi deployment's config.js. Covers both assignment forms, commented-out
// upstream defaults, `wss://` URLs inside strings, and missing keys.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_config.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_config_web.dart' as web;

void main() {
  test('the web half fails closed until the CSP/pinning decision lands', () {
    // De web-seam mag geen ongepinde fetch doen: een preflight die "werkt
    // maar niet gecontroleerd" is erger dan een eerlijke afwezigheid.
    expect(
      () => web.fetchJitsiConfig(
        Uri.parse('https://meet.example/config.js'),
        allowPrivate: false,
      ),
      throwsUnsupportedError,
    );
  });

  test('reads the upstream object form', () {
    final c = parseJitsiConfig('''
      var config = {
        hosts: {
          domain: 'meet.jitsi',
          anonymousdomain: 'guest.meet.jitsi',
          muc: 'muc.meet.jitsi',
          focus: 'focus.meet.jitsi'
        },
        bosh: 'https://meet.example/http-bind',
        websocket: 'wss://meet.example/xmpp-websocket',
        websocketKeepAliveUrl: 'https://meet.example/_unlock'
      };
    ''');
    expect(c.domain, 'meet.jitsi');
    expect(c.anonymousDomain, 'guest.meet.jitsi');
    expect(c.muc, 'muc.meet.jitsi');
    expect(c.websocket, 'wss://meet.example/xmpp-websocket');
    expect(c.bosh, 'https://meet.example/http-bind');
  });

  test('wss:// inside a string is not a comment start', () {
    final c = parseJitsiConfig(
      "var config = { websocket: 'wss://h.example/xmpp-websocket' };",
    );
    expect(c.websocket, 'wss://h.example/xmpp-websocket');
  });

  test('commented-out defaults do not count', () {
    final c = parseJitsiConfig('''
      var config = {
        // websocket: 'wss://old.example/ws',
        /* bosh: 'https://block-comment.example/x' */
        hosts: { domain: 'meet.jitsi' },
        websocket: 'wss://real.example/xmpp-websocket'
      };
    ''');
    expect(c.websocket, 'wss://real.example/xmpp-websocket');
    expect(c.bosh, isNull);
  });

  test('a later dotted assignment wins (custom-config.js append)', () {
    final c = parseJitsiConfig('''
      var config = {
        websocket: 'wss://first.example/xmpp-websocket',
        hosts: { domain: 'meet.jitsi' }
      };
      // custom-config.js, appended by the web server:
      config.websocket = 'wss://override.example/xmpp-websocket';
      config.hosts.domain = 'meet.override';
    ''');
    expect(c.websocket, 'wss://override.example/xmpp-websocket');
    expect(c.domain, 'meet.override');
  });

  test('double-quoted values parse too', () {
    final c = parseJitsiConfig(
      'var config = { hosts: { domain: "meet.jitsi" } };',
    );
    expect(c.domain, 'meet.jitsi');
  });

  test('missing keys are null, not an error', () {
    final c = parseJitsiConfig('var config = {};');
    expect(c.websocket, isNull);
    expect(c.domain, isNull);
    expect(c.anonymousDomain, isNull);
  });

  test('hosts fields inside other objects do not leak in', () {
    final c = parseJitsiConfig('''
      var config = {
        unrelated: { domain: 'trap.example' },
        hosts: { domain: 'meet.jitsi' }
      };
    ''');
    expect(c.domain, 'meet.jitsi');
  });
}
