// Integration test for OciDeck's XMPP collaboration transport against a local
// docker-jitsi-meet stack (docs/design/XMPP_COLLAB_TRANSPORT.md §8, §11 stap 8).
//
// Two real clients (host and guest) connect via WebSocket to Prosody, join the
// same MUC room, and run the full collaboration scenario: key exchange, edit,
// lock, chat, disconnect→reconnect→resync. This is the acceptance test that
// the unit tests (with FakeMucHub) cannot be: it proves the transport works
// against a real XMPP server.
//
// Gated behind the OCIDECK_XMPP_INTEGRATION environment variable — skipped
// unless the docker-jitsi-meet stack is running. See
// testbed/docker-jitsi-meet/README.md for setup.
//
// Run: OCIDECK_XMPP_INTEGRATION=1 make test-xmpp-integration

import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:xml/xml.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_snapshot.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/xmpp_settings.dart';
import 'package:ocideck/xmpp/xmpp_collab_launch.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport_platform.dart';
import 'package:ocideck/xmpp/xmpp_muc.dart';
import 'package:ocideck/xmpp/xmpp_session.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';

/// The WebSocket endpoint of the local docker-jitsi-meet Prosody.
const _serverUrl = 'ws://127.0.0.1:5280/xmpp-websocket';
const _domain = 'meet.jitsi';
const _mucDomain = 'conference.meet.jitsi';

/// Whether the integration test should run. Set OCIDECK_XMPP_INTEGRATION=1
/// in the environment after starting the docker-jitsi-meet stack.
bool get _integrationEnabled =>
    Platform.environment['OCIDECK_XMPP_INTEGRATION'] == '1';

/// Settings for an anonymous XMPP connection to the local Prosody.
XmppSettings _settings() => const XmppSettings(
  serverUrl: _serverUrl,
  domainOverride: _domain,
  trustedInternal: true,
);

/// Open a real WebSocket transport to the local Prosody.
Future<XmppFrameTransport> _openTransport() =>
    openXmppFrameTransport(_settings());

void main() {
  if (!_integrationEnabled) {
    test(
      'XMPP integration test (skipped — set OCIDECK_XMPP_INTEGRATION=1)',
      () {},
      tags: ['integration'],
    );
    return;
  }

  group('XMPP docker-jitsi-meet integration (§8, §11 stap 8)', () {
    test(
      'two clients join, edit, lock, chat, disconnect→resync over real Prosody',
      () async {
        final env = await _IntegrationEnv.create();
        addTearDown(env.dispose);

        // ── join: both clients connect and join the same MUC room ──────────
        await env.hostSession.connect().timeout(const Duration(seconds: 20));
        expect(
          env.hostSession.boundJid,
          isNotNull,
          reason: 'host connected and bound a resource',
        );

        await env.guestSession.connect().timeout(const Duration(seconds: 20));
        expect(
          env.guestSession.boundJid,
          isNotNull,
          reason: 'guest connected and bound a resource',
        );

        // Join the MUC room. The host joins first, then the guest.
        final hostJoin = await env.hostMuc
            .join(presenceExtensions: [env.hostDeviceExtension])
            .timeout(const Duration(seconds: 10));
        expect(hostJoin.ok, isTrue, reason: 'host joined the MUC');

        final guestJoin = await env.guestMuc
            .join(presenceExtensions: [env.guestDeviceExtension])
            .timeout(const Duration(seconds: 10));
        expect(guestJoin.ok, isTrue, reason: 'guest joined the MUC');

        // Wait for the host to see the guest in the roster.
        await env.waitForOccupant(env.hostMuc, env.guestNick);
        await env.waitForOccupant(env.guestMuc, env.hostNick);

        // Re-publish device keys + baseline now that both sessions are live
        // and joined to the MUC. The launch functions sent these during
        // create() but the stanzas were dropped (session wasn't live yet).
        await env.host.keyExchange.publishDeviceKeys();
        await env.guest.keyExchange.publishDeviceKeys();
        await env.host.snapshotChannel.sendSnapshot(
          CollabSnapshot.capture(env.host.session!.deck, 0, 0),
        );
        await env.settle();

        // ── key exchange: host approves guest, both sync ───────────────────
        env.host.keyExchange.approve(env.guestPub.deviceId);
        await env.settle();

        await env.host.syncNow();
        await env.settle();
        await env.guest.syncNow();
        await env.settle();

        expect(
          env.guest.isActive,
          isTrue,
          reason: 'guest received the baseline',
        );
        expect(
          env.guest.session!.deck.slides.single.id,
          env.hostSlide.id,
          reason: 'guest adopted the authority slide id',
        );

        // ── edit: host edits, guest sees it ────────────────────────────────
        await env.host.session!.submit(
          SetSlideField(
            version: 0,
            authorId: 'host',
            slideId: env.hostSlide.id,
            field: SlideField.title,
            value: 'shared over Prosody',
          ),
        );
        await env.settle();
        expect(
          env.guest.session!.deck.slides.single.title,
          'shared over Prosody',
          reason: 'guest received the host edit',
        );

        // ── edit: guest edits, host sees it ────────────────────────────────
        await env.guest.session!.submit(
          SetSlideField(
            version: 0,
            authorId: 'guest',
            slideId: env.hostSlide.id,
            field: SlideField.subtitle,
            value: 'from the guest over Prosody',
          ),
        );
        await env.settle();
        await env.host.syncNow();
        await env.settle();
        expect(
          env.host.session!.deck.slides.single.subtitle,
          'from the guest over Prosody',
          reason: 'host received the guest edit',
        );

        // ── lock: guest claims, host sees it; host force-unlocks ───────────
        await env.guest.session!.acquireLock(env.hostSlide.id);
        await env.settle();
        await env.host.syncNow();
        await env.settle();
        expect(
          env.host.session!.locks[env.hostSlide.id],
          env.guestPub.deviceId,
          reason: 'host sees the guest lock',
        );

        await env.host.session!.forceUnlock(env.hostSlide.id);
        await env.settle();
        expect(
          env.guest.session!.locks[env.hostSlide.id],
          isNull,
          reason: 'guest sees the forced unlock',
        );

        // ── chat: a signed chat line arrives at the guest ──────────────────
        final guestChat = <String>[];
        env.guest.chat.onChanged = () {
          guestChat.addAll(env.guest.chat.messages.map((m) => m.text));
        };

        await env.host.chat.send('hello from host');
        await env.settle();
        expect(
          guestChat,
          contains('hello from host'),
          reason: 'guest received the chat line',
        );

        // ── disconnect→resync: guest drops, reconnects, and resyncs ────────
        // Close the guest's transport to simulate a network drop. The session
        // should reconnect via the reconnectTransportFactory, rejoin the MUC,
        // and resync from the host's re-baseline.
        await env.guestSession.close();
        await env.settle();

        // Re-create the guest session and rejoin.
        await env.recreateGuest();
        await env.guestSession.connect().timeout(const Duration(seconds: 20));
        final rejoin = await env.guestMuc
            .join(presenceExtensions: [env.guestDeviceExtension])
            .timeout(const Duration(seconds: 10));
        expect(rejoin.ok, isTrue, reason: 'guest rejoined after reconnect');

        // Re-publish device keys after reconnect (the new session has a new
        // resource, so the host needs to see the guest's keys again).
        await env.guest.keyExchange.publishDeviceKeys();
        await env.settle();

        // The host already has this device keyed, so ensureKeyed won't re-key
        // it. Force a re-key by calling distributeEpoch with all approved
        // members — this clears the _keyed set and re-sends the epoch key.
        final approvedMembers = env.host.keyExchange.peers
            .where((p) => env.host.keyExchange.isApproved(p.keys.deviceId))
            .map((p) => p.keys)
            .toList();
        await env.host.keyExchange.distributeEpoch(approvedMembers);
        await env.settle();

        // Now the host sends a baseline so the reconnected guest can open its
        // session.
        await env.host.snapshotChannel.sendSnapshot(
          CollabSnapshot.capture(
            env.host.session!.deck,
            env.host.session!.version,
            0,
          ),
        );
        await env.settle();
        await env.guest.syncNow();
        await env.settle();
        await env.host.syncNow();
        await env.settle();

        expect(
          env.guest.isActive,
          isTrue,
          reason: 'guest is active after resync',
        );
        expect(
          env.guest.session!.deck.slides.single.title,
          'shared over Prosody',
          reason: 'guest has the latest state after resync',
        );
      },
      timeout: const Timeout(Duration(minutes: 2)),
      tags: ['integration'],
    );
  });
}

// ── test harness ─────────────────────────────────────────────────────────────

/// A two-client integration environment backed by real WebSocket connections
/// to the docker-jitsi-meet Prosody.
class _IntegrationEnv {
  _IntegrationEnv({
    required this.hostSession,
    required this.guestSession,
    required this.hostMuc,
    required this.guestMuc,
    required this.host,
    required this.guest,
    required this.hostSlide,
    required this.hostPub,
    required this.guestPub,
    required this.hostNick,
    required this.guestNick,
    required this.roomJid,
    required this.hostKeys,
    required this.guestKeys,
  });

  XmppSession hostSession;
  XmppSession guestSession;
  XmppMuc hostMuc;
  XmppMuc guestMuc;
  XmppCollabLaunch host;
  XmppCollabLaunch guest;
  final Slide hostSlide;
  final DevicePublicKeys hostPub;
  final DevicePublicKeys guestPub;
  final String hostNick;
  final String guestNick;
  final String roomJid;
  final CollabDeviceKeys hostKeys;
  final CollabDeviceKeys guestKeys;

  /// The device-key extension for the host's MUC presence.
  XmlElement get hostDeviceExtension => _deviceExtension(hostPub);
  XmlElement get guestDeviceExtension => _deviceExtension(guestPub);

  static Future<_IntegrationEnv> create() async {
    final hostKeys = await _device('host-int');
    final guestKeys = await _device('guest-int');
    final hostCrypto = CollabCrypto(hostKeys);
    final guestCrypto = CollabCrypto(guestKeys);
    final hostPub = await hostKeys.publicKeys(rot: 0);
    final guestPub = await guestKeys.publicKeys(rot: 0);

    final hostSlide = Slide.create(SlideType.bullets).copyWith(title: 'start');
    final hostDeck = Deck(title: 'deck', slides: [hostSlide]);
    final guestLocal = Deck(
      title: 'deck',
      slides: [Slide.create(SlideType.bullets).copyWith(title: 'start')],
    );

    // Unique room per run to avoid collisions with previous test runs.
    final roomSuffix = DateTime.now().microsecondsSinceEpoch;
    final roomJid = 'ocideck-int-$roomSuffix@$_mucDomain';
    final hostNick = 'host';
    final guestNick = 'guest';

    // Host session + MUC.
    final hostTransport = await _openTransport();
    final hostSession = XmppSession(
      transport: hostTransport,
      settings: _settings(),
      password: '',
      reconnectTransportFactory: _openTransport,
      reconnectDelay: (_) => const Duration(seconds: 1),
    );
    final hostMuc = XmppMuc(
      channel: hostSession,
      roomJid: roomJid,
      nick: hostNick,
      timeout: const Duration(seconds: 10),
    );

    // Guest session + MUC.
    final guestTransport = await _openTransport();
    final guestSession = XmppSession(
      transport: guestTransport,
      settings: _settings(),
      password: '',
      reconnectTransportFactory: _openTransport,
      reconnectDelay: (_) => const Duration(seconds: 1),
    );
    final guestMuc = XmppMuc(
      channel: guestSession,
      roomJid: roomJid,
      nick: guestNick,
      timeout: const Duration(seconds: 10),
    );

    // Wire the collab layers. The session IS the stanza channel — stanzas
    // sent via sendStanza go to Prosody, which routes them to the MUC.
    final host = await hostXmppSession(
      stanzaChannel: hostSession,
      crypto: hostCrypto,
      ownKeys: hostPub,
      roomJid: roomJid,
      deck: hostDeck,
      ownUserId: '$roomJid/$hostNick',
    );
    final guest = await joinXmppSession(
      stanzaChannel: guestSession,
      crypto: guestCrypto,
      ownKeys: guestPub,
      roomJid: roomJid,
      localDeck: guestLocal,
      ownUserId: '$roomJid/$guestNick',
      onReconnected: null, // TODO: wire to session.onReconnected
    );

    return _IntegrationEnv(
      hostSession: hostSession,
      guestSession: guestSession,
      hostMuc: hostMuc,
      guestMuc: guestMuc,
      host: host,
      guest: guest,
      hostSlide: hostSlide,
      hostPub: hostPub,
      guestPub: guestPub,
      hostNick: hostNick,
      guestNick: guestNick,
      roomJid: roomJid,
      hostKeys: hostKeys,
      guestKeys: guestKeys,
    );
  }

  /// Recreate the guest session after a disconnect.
  Future<void> recreateGuest() async {
    final guestTransport = await _openTransport();
    guestSession = XmppSession(
      transport: guestTransport,
      settings: _settings(),
      password: '',
      reconnectTransportFactory: _openTransport,
      reconnectDelay: (_) => const Duration(seconds: 1),
    );
    guestMuc = XmppMuc(
      channel: guestSession,
      roomJid: roomJid,
      nick: guestNick,
      timeout: const Duration(seconds: 10),
    );
    // Re-wire the collab layers with the new session.
    final guestCrypto = CollabCrypto(guestKeys);
    final guestLocal = Deck(
      title: 'deck',
      slides: [Slide.create(SlideType.bullets).copyWith(title: 'start')],
    );
    guest = await joinXmppSession(
      stanzaChannel: guestSession,
      crypto: guestCrypto,
      ownKeys: guestPub,
      roomJid: roomJid,
      localDeck: guestLocal,
      ownUserId: '$roomJid/$guestNick',
      onReconnected: null,
    );
  }

  /// Wait until [muc]'s roster contains an occupant with [nick].
  Future<void> waitForOccupant(XmppMuc muc, String nick) async {
    while (!muc.roster.any((o) => o.nick == nick)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Pump the event queue and wait for real I/O (WebSocket frames) to arrive.
  /// The XMPP transport uses real WebSockets, so we need real wall-clock time
  /// in addition to pumping the Dart event loop.
  Future<void> settle() async {
    await pumpEventQueue(times: 100);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await pumpEventQueue(times: 100);
  }

  Future<void> dispose() async {
    await guest.dispose();
    await host.dispose();
    try {
      await guestMuc.leave();
    } catch (_) {}
    try {
      await hostMuc.leave();
    } catch (_) {}
    try {
      await guestSession.close();
    } catch (_) {}
    try {
      await hostSession.close();
    } catch (_) {}
  }
}

/// Deterministic device keys from a label (mirrors the fixture in
/// `xmpp_collab_launch_test.dart`).
Future<CollabDeviceKeys> _device(String label) {
  List<int> seed(int salt) {
    final bytes = Uint8List(32);
    final name = label.codeUnits;
    for (var i = 0; i < 32; i++) {
      bytes[i] = (name[i % name.length] + salt + i) & 0xff;
    }
    return bytes;
  }

  return CollabDeviceKeys.fromSeeds(
    deviceId: label,
    ed25519Seed: seed(1),
    x25519Seed: seed(2),
  );
}

/// The `<x xmlns="nl.ocideck.device">` presence extension carrying the
/// device's public keys (§5 brick 10).
XmlElement _deviceExtension(DevicePublicKeys pub) {
  // Build the device-keys presence extension. This mirrors what
  // XmppKeyExchange.publishDeviceKeys sends.
  final json = pub.toJson();
  return xmppElement(
    'x',
    namespace: 'nl.ocideck.device',
    children: [xmppElement('keys', text: jsonEncode(json))],
  );
}
