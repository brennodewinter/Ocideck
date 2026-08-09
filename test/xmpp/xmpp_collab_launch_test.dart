// End-to-end-testen voor de XMPP-sessie-lifecycle
// (`lib/xmpp/xmpp_collab_launch.dart`, `docs/design/XMPP_COLLAB_TRANSPORT.md`
// §5–6, §8, sub-plak 6): een host start een sessie en een guest joinet hem
// **volledig over de [FakeMucHub]** — device-keys, keyshare en de gechunkte
// baseline rijden allemaal de draad — waarna de guest de autoriteit's slide-id-
// ruimte heeft aangenomen (§5.5) en ze twee kanten op co-auteuren. Dit is de
// acceptatie-mijlpaal: het werkt écht tussen twee clients zonder infrastructuur.
//
// Daarnaast: de admission-gate (een niet-goedgekeurde guest wordt nooit
// gesleuteld, SA-F4), de twee herstelpaden uit NEW-6 (drop vóór keying →
// re-join + ensureKeyed; drop ná keying → verzegelde §4-resync), en de
// exclusiviteit-als-test (§1: geen Matrix-client in een XMPP-sessie).

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/matrix_relay_transport.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/xmpp/xmpp_collab_launch.dart';
import 'package:ocideck/xmpp/xmpp_transport.dart';

import 'fake_muc_hub.dart';

void main() {
  test(
    'a guest joins over the wire, adopts slide ids, and co-authors',
    () async {
      final env = await _LaunchEnv.create();
      addTearDown(env.dispose);

      // De autoriteit keurt de guest goed (admission-gate, SA-F4) vóór keying.
      env.host.keyExchange.approve(env.guestPub.deviceId);

      // Laat de device-presence stansen door de hub/demux vloeien vóór de host
      // de guest probeert te sleutelen (push, niet poll — de demux verwerkt
      // asynchroon op de event-loop).
      await env.settle();

      // Drive de handshake: de host leert de guest en sleutelt hem; de guest
      // ontvangt keyshare + baseline en start.
      await env.host.syncNow();
      await env.settle();
      await env.guest.syncNow();
      await env.settle();

      expect(
        env.guest.isActive,
        isTrue,
        reason: 'the guest received the baseline',
      );
      expect(
        env.guest.session!.deck.slides.single.id,
        env.hostSlide.id,
        reason: 'the guest adopted the authority slide id',
      );

      // Autoriteit-edit → guest (push via de demux).
      await env.host.session!.submit(
        SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: env.hostSlide.id,
          field: SlideField.title,
          value: 'shared',
        ),
      );
      await env.settle();
      expect(env.guest.session!.deck.slides.single.title, 'shared');

      // Guest-edit → autoriteit → terug naar guest (de follower-round-trip).
      await env.guest.session!.submit(
        SetSlideField(
          version: 0,
          authorId: 'guest',
          slideId: env.hostSlide.id,
          field: SlideField.subtitle,
          value: 'from the guest',
        ),
      );
      await env.settle();
      await env.host.syncNow();
      await env.settle();
      expect(env.host.session!.deck.slides.single.subtitle, 'from the guest');
      expect(env.guest.session!.deck.slides.single.subtitle, 'from the guest');

      // Lock-round-trip: guest claimt, host ziet het; host forceert vrij.
      await env.guest.session!.acquireLock(env.hostSlide.id);
      await env.settle();
      await env.host.syncNow();
      await env.settle();
      expect(env.host.session!.locks[env.hostSlide.id], env.guestPub.deviceId);

      await env.host.session!.forceUnlock(env.hostSlide.id);
      await env.settle();
      expect(env.guest.session!.locks[env.hostSlide.id], isNull);
    },
  );

  test('a non-approved guest is never keyed and never goes active', () async {
    final env = await _LaunchEnv.create();
    addTearDown(env.dispose);

    // Geen approve — de admission-gate (SA-F4) moet de guest tegenhouden.
    await env.settle();
    await env.host.syncNow();
    await env.settle();
    await env.guest.syncNow();
    await env.settle();
    await env.host.syncNow();
    await env.settle();
    await env.guest.syncNow();
    await env.settle();

    expect(
      env.guest.isActive,
      isFalse,
      reason: 'an unapproved guest is never keyed',
    );
    expect(env.host.keyExchange.isApproved(env.guestPub.deviceId), isFalse);
  });

  group('XMPP launch recovery (NEW-6)', () {
    test('a drop after keying resyncs via the sealed §4 re-baseline', () async {
      final env = await _LaunchEnv.create();
      addTearDown(env.dispose);
      env.host.keyExchange.approve(env.guestPub.deviceId);
      await env.settle();
      await env.host.syncNow();
      await env.settle();
      await env.guest.syncNow();
      await env.settle();
      expect(env.guest.isActive, isTrue);

      // Eén edit zodat beide op versie 1 staan.
      await env.host.session!.submit(
        SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: env.hostSlide.id,
          field: SlideField.title,
          value: 'v1',
        ),
      );
      await env.settle();
      expect(env.guest.session!.version, 1);

      // Guest dropt; de autoriteit loopt door met twee bewerkingen.
      env.guestChannel.drop();
      await env.host.session!.submit(
        SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: env.hostSlide.id,
          field: SlideField.title,
          value: 'v2',
        ),
      );
      await env.host.session!.submit(
        SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: env.hostSlide.id,
          field: SlideField.title,
          value: 'v3',
        ),
      );
      await env.settle();
      expect(env.host.session!.version, 3);
      expect(env.guest.session!.version, 1, reason: 'guest miste v2 en v3');

      // Guest herbetreedt — het reconnect-signaal triggert een verzegelde
      // resync (de guest heeft zijn epoch-sleutel), de autoriteit re-
      // baselineert, en de guest re-baseert (forward-only).
      env.guestChannel.rejoin();
      await env.settle();
      // De autoriteit moet de resync afhandelen (syncNow drijft de reactive
      // handshake — de resync-stanza zelf komt push binnen, maar de re-
      // baseline komt uit onResyncRequested).
      await env.host.syncNow();
      await env.settle();

      expect(env.guest.session!.version, 3);
      expect(env.guest.session!.deck.slides.single.title, 'v3');

      // Een volgende bewerking bereikt de guest normaal — niet bevroren.
      await env.host.session!.submit(
        SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: env.hostSlide.id,
          field: SlideField.subtitle,
          value: 'after',
        ),
      );
      await env.settle();
      expect(env.guest.session!.version, 4);
      expect(env.guest.session!.deck.slides.single.subtitle, 'after');
    });

    test(
      'a drop before keying recovers by re-join + ensureKeyed, not resync',
      () async {
        final env = await _LaunchEnv.create();
        addTearDown(env.dispose);
        env.host.keyExchange.approve(env.guestPub.deviceId);

        // De guest publiceert zijn device-keys maar dropt VÓÓR de host hem
        // sleutelt — de host heeft nog geen keyshare verzonden, dus _keyed
        // bevat de guest niet. De guest houdt geen epoch-sleutel, dus kan geen
        // verzegelde resync verzenden (NEW-6: drop vóór keying → re-join +
        // ensureKeyed).
        await env.settle();
        env.guestChannel.drop();

        // Guest herbetreedt. De transport's resync-emissie faalt stil (no-epoch);
        // de host's ensureKeyed sleutelt de guest (hij staat niet in _keyed —
        // de host heeft nog nooit een keyshare verzonden).
        env.guestChannel.rejoin();
        await env.settle();
        await env.host.syncNow();
        await env.settle();
        await env.guest.syncNow();
        await env.settle();

        expect(
          env.guest.isActive,
          isTrue,
          reason: 'recovered by re-keying, not resync',
        );
        expect(
          env.guest.session!.deck.slides.single.id,
          env.hostSlide.id,
          reason: 'the guest adopted the authority slide id',
        );
      },
    );
  });

  group('XMPP-mode exclusivity (§1)', () {
    test(
      'a launched XMPP session runs on XmppTransport, not MatrixRelayTransport',
      () async {
        final env = await _LaunchEnv.create();
        addTearDown(env.dispose);

        // De sessie rijdt op de XMPP-data-plane, niet op de Matrix-relay —
        // exclusiviteit als test (§1, §7). Een XMPP-sessie kent geen MatrixClient.
        expect(env.host.transport, isA<XmppTransport>());
        expect(env.host.transport, isNot(isA<MatrixRelayTransport>()));
        expect(env.guest.transport, isA<XmppTransport>());
        expect(env.guest.transport, isNot(isA<MatrixRelayTransport>()));
      },
    );
  });

  group('XMPP presence + chat over the wire (§5 sub-plak 7)', () {
    test('a signed chat line arrives at the guest (§8 acceptance)', () async {
      final env = await _LaunchEnv.create();
      addTearDown(env.dispose);
      env.host.keyExchange.approve(env.guestPub.deviceId);
      await env.settle();
      await env.host.syncNow();
      await env.settle();
      await env.guest.syncNow();
      await env.settle();
      expect(env.guest.isActive, isTrue);

      // De host zendt een chat-regel; de guest ontvangt hem verzegeld +
      // ondertekend over de draad.
      await env.host.sendChat('hallo van de host');
      await env.settle();

      expect(env.guest.chatMessages, hasLength(1));
      expect(env.guest.chatMessages.single.text, 'hallo van de host');
      expect(env.guest.chatMessages.single.deviceId, env.hostPub.deviceId);
      expect(env.guest.chatMessages.single.isSelf, isFalse);
      // De host ziet enkel zijn lokale echo.
      expect(env.host.chatMessages, hasLength(1));
      expect(env.host.chatMessages.single.isSelf, isTrue);
    });

    test(
      'a guest chat line arrives at the host, and back to the guest',
      () async {
        final env = await _LaunchEnv.create();
        addTearDown(env.dispose);
        env.host.keyExchange.approve(env.guestPub.deviceId);
        await env.settle();
        await env.host.syncNow();
        await env.settle();
        await env.guest.syncNow();
        await env.settle();
        expect(env.guest.isActive, isTrue);

        await env.guest.sendChat('van de guest');
        await env.settle();
        await env.host.syncNow(); // drijft de host's chat-retryPending
        await env.settle();

        expect(
          env.host.chatMessages.any((m) => m.text == 'van de guest'),
          isTrue,
        );
        // De guest ziet enkel zijn lokale echo (geen duplicaat van de reflectie).
        final guestOwn = env.guest.chatMessages.where((m) => m.isSelf).toList();
        expect(guestOwn, hasLength(1));
        expect(guestOwn.single.text, 'van de guest');
      },
    );

    test(
      'presence announces a slide position the peer sees (latest-per-sender)',
      () async {
        final env = await _LaunchEnv.create();
        addTearDown(env.dispose);
        env.host.keyExchange.approve(env.guestPub.deviceId);
        await env.settle();
        await env.host.syncNow();
        await env.settle();
        await env.guest.syncNow();
        await env.settle();
        expect(env.guest.isActive, isTrue);

        // De host kondigt zijn slide aan; de guest ziet hem in zijn presence-lijst.
        await env.host.announcePresence(env.hostSlide.id);
        await env.settle();
        await env.guest.syncNow(); // drijft presence-retryPending
        await env.settle();

        expect(env.guest.presencePeers, hasLength(1));
        expect(env.guest.presencePeers.single.deviceId, env.hostPub.deviceId);
        expect(env.guest.presencePeers.single.slideId, env.hostSlide.id);
        // De host staat niet in zijn eigen presence-lijst (eigen echo gedropt).
        expect(env.host.presencePeers, isEmpty);
      },
    );
  });
}

// ── test helpers ─────────────────────────────────────────────────────────────

/// Een host- en guest-launch over een gedeelde [FakeMucHub], met vooraf
/// gegenereerde device-sleutels. De launch-functies bouwen zelf hun demux en
/// bricks; de test hoeft alleen [syncNow] te drijven en de gast goed te keuren.
class _LaunchEnv {
  _LaunchEnv({
    required this.hub,
    required this.room,
    required this.hostChannel,
    required this.guestChannel,
    required this.host,
    required this.guest,
    required this.hostSlide,
    required this.hostPub,
    required this.guestPub,
  });

  final FakeMucHub hub;
  final String room;
  final FakeMucChannel hostChannel;
  final FakeMucChannel guestChannel;
  final XmppCollabLaunch host;
  final XmppCollabLaunch guest;
  final Slide hostSlide;
  final DevicePublicKeys hostPub;
  final DevicePublicKeys guestPub;

  static Future<_LaunchEnv> create() async {
    const room = 'ocideck-launch@conference.example';
    final hub = FakeMucHub(room);

    final hostKeys = await _device('host');
    final guestKeys = await _device('guest');
    final hostCrypto = CollabCrypto(hostKeys);
    final guestCrypto = CollabCrypto(guestKeys);
    final hostPub = await hostKeys.publicKeys(rot: 0);
    final guestPub = await guestKeys.publicKeys(rot: 0);

    final hostSlide = Slide.create(SlideType.bullets).copyWith(title: 'start');
    final hostDeck = Deck(title: 'deck', slides: [hostSlide]);
    // De guest opende "dezelfde" .md onafhankelijk — zijn lokale slide heeft een
    // *andere* id. De snapshot moet hem overschrijven met de autoriteit's.
    final guestLocal = Deck(
      title: 'deck',
      slides: [Slide.create(SlideType.bullets).copyWith(title: 'start')],
    );
    expect(guestLocal.slides.single.id, isNot(hostSlide.id));

    final hostChannel = hub.join('host');
    final guestChannel = hub.join('guest');

    final host = await hostXmppSession(
      stanzaChannel: hostChannel,
      crypto: hostCrypto,
      ownKeys: hostPub,
      roomJid: room,
      deck: hostDeck,
      ownUserId: '$room/host',
    );
    final guest = await joinXmppSession(
      stanzaChannel: guestChannel,
      crypto: guestCrypto,
      ownKeys: guestPub,
      roomJid: room,
      localDeck: guestLocal,
      ownUserId: '$room/guest',
      onReconnected: guestChannel.onReconnected,
    );

    final env = _LaunchEnv(
      hub: hub,
      room: room,
      hostChannel: hostChannel,
      guestChannel: guestChannel,
      host: host,
      guest: guest,
      hostSlide: hostSlide,
      hostPub: hostPub,
      guestPub: guestPub,
    );
    // Herpubliceer de host's device-keys ná beide launches — de host
    // publiceerde vóór de guest's demux geabonneerd was, dus de guest miste
    // de host's presence. Een echte MUC levert bestaande presence opnieuw aan
    // bij join (XEP-0045 §7.2.2); de fake doet dat alleen voor presence vóór
    // de join, niet ertussen. Dit simuleert die herlevering.
    await host.keyExchange.publishDeviceKeys();
    return env;
  }

  Future<void> settle() => pumpEventQueue(times: 100);

  Future<void> dispose() async {
    await host.dispose();
    await guest.dispose();
    await hostChannel.close();
    await guestChannel.close();
  }
}

/// Deterministische device-sleutels van een label (spiegelt de fixture in
/// `xmpp_transport_test.dart`).
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
