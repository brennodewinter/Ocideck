import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/literal_loopback.dart';

void main() {
  group('isLiteralLoopbackHost', () {
    test('accepteert letterlijke loopback-adressen', () {
      for (final host in [
        '127.0.0.1',
        '127.0.0.2',
        '127.255.255.254',
        '::1',
        '[::1]',
      ]) {
        expect(isLiteralLoopbackHost(host), isTrue, reason: host);
      }
    });

    test('weigert namen en niet-loopback adressen', () {
      for (final host in [
        'localhost',
        '127.localhost.example',
        '128.0.0.1',
        '10.0.0.1',
        '192.168.1.1',
        '::2',
        'example.org',
        '127.0.0.01',
        '127.0.0',
        '127.0.0.1.1',
        '',
      ]) {
        expect(isLiteralLoopbackHost(host), isFalse, reason: host);
      }
    });
  });

  group('isLiteralInternalHost', () {
    test('accepteert wat NetGuard zonder DNS zou blokkeren', () {
      for (final host in [
        '127.0.0.1',
        '127.255.255.254',
        '::1',
        '[::1]',
        '::',
        '10.0.0.1',
        '10.255.255.255',
        '10.0.0.01',
        '0.0.0.0',
        '172.16.0.1',
        '172.31.255.255',
        '192.168.0.1',
        '192.168.1.20',
        '169.254.1.1',
        '100.64.0.1',
        '100.127.255.255',
        '224.0.0.1',
        'localhost',
        'foo.localhost',
        'fe80::1',
        'fd00::1',
        'fc00::1',
        'ff02::1',
        '::ffff:127.0.0.1',
        '::ffff:192.168.1.20',
        '64:ff9b::127.0.0.1',
        '::gggg',
        '',
      ]) {
        expect(isLiteralInternalHost(host), isTrue, reason: host);
      }
    });

    test('weigert publieke adressen en gewone namen', () {
      for (final host in [
        '128.0.0.1',
        '172.15.255.255',
        '172.32.0.1',
        '192.167.1.1',
        '192.169.1.1',
        '100.63.255.255',
        '100.128.0.1',
        '223.255.255.255',
        '8.8.8.8',
        'example.org',
        '127.localhost.example',
        '2001:4860:4860::8888',
        '::ffff:8.8.8.8',
        '64:ff9b::1.1.1.1',
      ]) {
        expect(isLiteralInternalHost(host), isFalse, reason: host);
      }
    });
  });

  group('schemegrens van de web-call', () {
    test('config.js is https, of http op letterlijk loopback', () {
      expect(
        allowsWebConfigFetch(Uri.parse('https://meet.example/config.js')),
        isTrue,
      );
      expect(
        allowsWebConfigFetch(Uri.parse('http://127.0.0.1:8000/config.js')),
        isTrue,
      );
      expect(allowsWebConfigFetch(Uri.parse('http://[::1]/config.js')), isTrue);
      expect(
        allowsWebConfigFetch(Uri.parse('http://localhost/config.js')),
        isFalse,
      );
      expect(
        allowsWebConfigFetch(Uri.parse('http://meet.example/config.js')),
        isFalse,
      );
      expect(
        allowsWebConfigFetch(Uri.parse('ws://127.0.0.1/config.js')),
        isFalse,
      );
    });

    test('XMPP is wss, of ws op letterlijk loopback', () {
      expect(
        allowsWebXmppSocket(Uri.parse('wss://meet.example/xmpp-websocket')),
        isTrue,
      );
      expect(
        allowsWebXmppSocket(Uri.parse('ws://127.0.0.1:8000/xmpp-websocket')),
        isTrue,
      );
      expect(
        allowsWebXmppSocket(Uri.parse('ws://localhost/xmpp-websocket')),
        isFalse,
      );
      expect(
        allowsWebXmppSocket(Uri.parse('wss://127.0.0.1/xmpp-websocket')),
        isTrue,
      );
      expect(allowsWebXmppSocket(Uri.parse('http://127.0.0.1/')), isFalse);
    });
  });

  test('de webhelften roepen de schemegrens aan', () {
    // package:web laadt niet in de VM-runner, dus de socket zelf niet.
    // Wel afdwingen dat die bestanden de geteste beslissing niet omzeilen.
    final config = File(
      'lib/meetings/providers/jitsi/jitsi_config_web.dart',
    ).readAsStringSync();
    final xmpp = File(
      'lib/xmpp/xmpp_frame_transport_web.dart',
    ).readAsStringSync();
    expect(config, contains('allowsWebConfigFetch('));
    expect(xmpp, contains('allowsWebXmppSocket('));
  });
}
