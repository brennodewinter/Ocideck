import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/xmpp_settings.dart';

void main() {
  group('XmppSettings.domain', () {
    test('derives from the JID when set', () {
      const s = XmppSettings(
        serverUrl: 'wss://xmpp.example.org/xmpp-websocket',
        jid: 'alice@conference.example.org',
      );
      expect(s.domain, 'conference.example.org');
    });

    test('falls back to the WebSocket host for anonymous access', () {
      const s = XmppSettings(serverUrl: 'wss://meet.jit.si/xmpp-websocket');
      expect(s.domain, 'meet.jit.si');
      expect(s.isAnonymous, isTrue);
    });

    test('domainOverride takes precedence over JID and host', () {
      const s = XmppSettings(
        serverUrl: 'ws://127.0.0.1:5280/xmpp-websocket',
        jid: 'alice@example.org',
        domainOverride: 'meet.jitsi',
        trustedInternal: true,
      );
      expect(s.domain, 'meet.jitsi');
    });

    test(
      'domainOverride enables anonymous access to a named domain via loopback',
      () {
        const s = XmppSettings(
          serverUrl: 'ws://127.0.0.1:5280/xmpp-websocket',
          domainOverride: 'meet.jitsi',
          trustedInternal: true,
        );
        expect(s.isAnonymous, isTrue);
        expect(s.domain, 'meet.jitsi');
      },
    );

    test('empty domainOverride falls back to the derived domain', () {
      const s = XmppSettings(
        serverUrl: 'wss://meet.jit.si/xmpp-websocket',
        domainOverride: '',
      );
      expect(s.domain, 'meet.jit.si');
    });
  });

  group('XmppSettings round-trip', () {
    test('toJson + fromJson preserves domainOverride', () {
      const s = XmppSettings(
        serverUrl: 'ws://127.0.0.1:5280/xmpp-websocket',
        domainOverride: 'meet.jitsi',
        trustedInternal: true,
      );
      final restored = XmppSettings.fromJson(s.toJson());
      expect(restored, s);
      expect(restored.domainOverride, 'meet.jitsi');
    });

    test('copyWith carries domainOverride', () {
      const s = XmppSettings(
        serverUrl: 'ws://127.0.0.1:5280/xmpp-websocket',
        domainOverride: 'meet.jitsi',
      );
      final updated = s.copyWith(jid: 'alice@meet.jitsi');
      expect(updated.domainOverride, 'meet.jitsi');
      expect(updated.jid, 'alice@meet.jitsi');
    });

    test('fromJson handles missing domainOverride (backward compat)', () {
      final s = XmppSettings.fromJson({
        'serverUrl': 'wss://meet.jit.si/xmpp-websocket',
        'jid': '',
      });
      expect(s.domainOverride, '');
      expect(s.domain, 'meet.jit.si');
    });
  });

  group('XmppSettings equality', () {
    test('domainOverride participates in equality', () {
      const a = XmppSettings(
        serverUrl: 'ws://127.0.0.1:5280/xmpp-websocket',
        domainOverride: 'meet.jitsi',
      );
      const b = XmppSettings(
        serverUrl: 'ws://127.0.0.1:5280/xmpp-websocket',
        domainOverride: 'conference.jitsi',
      );
      expect(a == b, isFalse);
      expect(a == a, isTrue);
    });
  });
}
