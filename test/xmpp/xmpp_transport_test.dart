// End-to-end-testen voor `XmppTransport` (`lib/xmpp/xmpp_transport.dart`,
// `docs/design/XMPP_COLLAB_TRANSPORT.md` §4 sub-plak 4): twee echte
// [CollabSession]s over de verzegelde companion-MUC, gedreven door de
// in-memory [FakeMucHub]. Sleutels vooraf gedeeld (de key-exchange is
// sub-plak 5). Het doel is te bewijzen dat de data-plane over de MUC
// dezelfde autoriteit/versie/lock-garanties levert als Loopback en Matrix,
// plus de §4 gap→resync die een MUC nodig heeft omdat groupchat niet
// hervatbaar levert.
//
// Daarnaast draait hier het gedeelde CollabTransport-contract over XMPP,
// naast de unit- en adversariële testen uit §8.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/collab_snapshot.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/xmpp/companion_demux.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';
import 'package:ocideck/xmpp/xmpp_transport.dart';
import 'package:xml/xml.dart';

import '../collab/collab_transport_contract.dart';
import 'fake_muc_hub.dart';

/// Het vensterplafond van de inbound-op-rate-limiter — gelijk aan de private
/// `XmppTransport._maxOpsPerSecondPerSender` in lib/xmpp/xmpp_transport.dart.
/// Bewust hier herhaald (de lib-constante is privé, en de transport blijft
/// Flutter-vrij zodat er geen `@visibleForTesting`-import bij hoeft): wijzigt die
/// cap, dan faalt de flood-test luid en werk je 'm hier bij — één plek om te
/// controleren, geen stille drift.
const _rateLimitCap = 50;

void main() {
  runCollabTransportContract('XMPP', _createContractPair);

  group('XmppTransport unit', () {
    test('a malformed groupchat op is dropped fail-closed', () async {
      final env = await _XmppEnv.create();
      addTearDown(env.dispose);
      final received = <DeckOp>[];
      final sub = env.guestTransport.ops.listen(received.add);

      // Inject een garbage op-stanza (geen verzegelde envelope).
      env.guestChannel.sendStanza(_fakeOpStanza(env.room, 'not json'));
      await env.settle();

      expect(received, isEmpty);
      await sub.cancel();
    });

    test('an oversized payload is dropped, not applied', () async {
      final env = await _XmppEnv.create();
      addTearDown(env.dispose);
      final received = <DeckOp>[];
      final sub = env.guestTransport.ops.listen(received.add);

      // Een geldig-uitziende maar onopenbare envelope (verkeerde ciphertext).
      final forged = SealedEnvelope(
        epoch: 0,
        nonce: List.filled(24, 0),
        ciphertext: List.filled(64, 0),
        senderDevice: 'host',
      );
      env.guestChannel.sendStanza(
        _fakeOpStanza(env.room, jsonEncode(forged.toContent())),
      );
      await env.settle();

      expect(received, isEmpty);
      await sub.cancel();
    });

    test(
      'an op that arrives before its sender is known is retried, not lost',
      () async {
        final env = await _XmppEnv.create(knowsHost: false);
        addTearDown(env.dispose);
        final received = <DeckOp>[];
        final sub = env.guestTransport.ops.listen(received.add);

        // De host stuurt een op; de guest kan de afzender nog niet resolveren.
        final slide = Slide.create(SlideType.bullets).copyWith(title: 's');
        await env.hostTransport.sendOp(
          SetSlideField(
            version: 1,
            authorId: 'host',
            slideId: slide.id,
            field: SlideField.title,
            value: 'early',
          ),
        );
        await env.settle();
        expect(received, isEmpty); // uitgesteld, niet gedropt

        // Nu kan de guest de host resolveren. De key-change callback
        // (notifyKeyChanged) triggert de backlog-replay, en de uitgestelde op
        // wordt alsnog toegepast.
        env.knowsHost = true;
        env.guestTransport.notifyKeyChanged();
        await env.settle();

        expect(received, hasLength(1));
        expect((received.single as SetSlideField).value, 'early');
        await sub.cancel();
      },
    );

    test('a flood of ops from one sender is rate-limited (#1433)', () async {
      // Bevries de klok van de transport, zodat alle 100 ops in HETZELFDE
      // rate-limit-venster vallen. Dan toetst de test de begrenzing exact —
      // precies _maxOpsPerSecondPerSender (50) komen door — i.p.v. te leunen op
      // een tijdmarge die onder CPU-belasting wegvalt. Zonder deze bevriezing
      // kruiste de burst op de trage serial-runner een tweede venster (de
      // klok liep tijdens de 100 seriële crypto-opens over de seconde-grens),
      // liet >50 ops door en flakete de poort (#1433/linux-gate).
      final frozen = DateTime.utc(2026);
      final env = await _XmppEnv.create(now: () => frozen);
      addTearDown(env.dispose);
      final received = <DeckOp>[];
      final sub = env.guestTransport.ops.listen(received.add);

      final slide = Slide.create(SlideType.bullets).copyWith(title: 's');
      // Stuur 100 ops in één burst — de rate-limiter laat er max 50 door per
      // venster per sender.
      for (var i = 1; i <= 100; i++) {
        await env.hostTransport.sendOp(
          SetSlideField(
            version: i,
            authorId: 'host',
            slideId: slide.id,
            field: SlideField.title,
            value: 'op-$i',
          ),
        );
      }
      await env.settle();

      // Precies de eerste 50 komen door (het vensterplafond); de staart wordt
      // gedropt. De demux verwerkt strikt op volgorde (#1420), dus het zijn de
      // versies 1..50. Deterministisch — zonder limiter zouden alle 100
      // doorkomen, dus dit bewijst de begrenzing hard.
      expect(
        received.length,
        _rateLimitCap,
        reason: 'de limiter laat precies één vensterplafond aan ops door',
      );
      expect(
        received.map((op) => op.version).toList(),
        List<int>.generate(_rateLimitCap, (i) => i + 1),
        reason: 'de doorgelaten ops zijn de eerste 50, op volgorde',
      );
      await sub.cancel();
    });
  });

  group('XmppTransport gap → resync (§4)', () {
    test(
      'a drop → authority advances → rejoin re-baselines, never freezes',
      () async {
        final env = await _XmppEnv.create();
        addTearDown(env.dispose);
        final slide = Slide.create(SlideType.bullets).copyWith(title: 'start');

        // Beide sessies starten op dezelfde baseline.
        final hostSession = CollabSession(
          initialDeck: _deckWith(slide),
          transport: env.hostTransport,
          isAuthority: true,
        );
        final guestSession = CollabSession(
          initialDeck: _deckWith(slide),
          transport: env.guestTransport,
          isAuthority: false,
        );
        addTearDown(hostSession.dispose);
        addTearDown(guestSession.dispose);

        // Eén edit zodat beide op versie 1 staan.
        await hostSession.submit(
          SetSlideField(
            version: 0,
            authorId: 'host',
            slideId: slide.id,
            field: SlideField.title,
            value: 'v1',
          ),
        );
        await env.settle();
        expect(hostSession.version, 1);
        expect(guestSession.version, 1);

        // Wire de re-baseline: de autoriteit stuurt een snapshot, de follower
        // re-baseert. (De snapshot-channel is sub-plak 6; hier in de test
        // direct afgehandeld om het gap→resync-pad te bewijzen.)
        var resyncRequested = 0;
        env.hostTransport.onResyncRequested = () async {
          resyncRequested++;
          await _sendSnapshot(
            env.hostChannel,
            env.hostCrypto,
            env.room,
            hostSession.deck,
            hostSession.version,
          );
        };
        env.guestDemux.register(OciDeckNamespace.snapshot, (stanza) async {
          final opened = await _openSnapshot(
            stanza,
            env.guestCrypto,
            env.room,
            env.hostPub,
          );
          guestSession.rebaseTo(
            opened.applyTo(guestSession.deck),
            opened.version,
          );
        });

        // Guest dropt; de autoriteit loopt door met twee bewerkingen.
        env.guestChannel.drop();
        await hostSession.submit(
          SetSlideField(
            version: 0,
            authorId: 'host',
            slideId: slide.id,
            field: SlideField.title,
            value: 'v2',
          ),
        );
        await hostSession.submit(
          SetSlideField(
            version: 0,
            authorId: 'host',
            slideId: slide.id,
            field: SlideField.title,
            value: 'v3',
          ),
        );
        await env.settle();
        expect(hostSession.version, 3);
        expect(guestSession.version, 1); // guest heeft v2 en v3 gemist

        // Guest herbetreedt — het reconnect-signaal triggert een resync.
        env.guestChannel.rejoin();
        await env.settle();

        // De autoriteit heeft de resync gekregen en een re-baseline gestuurd;
        // de guest is gere-based naar versie 3 en niet bevroren.
        expect(resyncRequested, 1);
        expect(guestSession.version, 3);
        expect(guestSession.deck.slides.single.title, 'v3');

        // Een volgende bewerking bereikt de guest normaal — het deck is niet
        // bevroren.
        await hostSession.submit(
          SetSlideField(
            version: 0,
            authorId: 'host',
            slideId: slide.id,
            field: SlideField.subtitle,
            value: 'after',
          ),
        );
        await env.settle();
        expect(guestSession.version, 4);
        expect(guestSession.deck.slides.single.subtitle, 'after');
      },
    );

    test('a resync-flood is coalesced on the authority side', () async {
      final env = await _XmppEnv.create(
        resyncCoalesceWindow: const Duration(milliseconds: 200),
      );
      addTearDown(env.dispose);

      var resyncRequested = 0;
      env.hostTransport.onResyncRequested = () async {
        resyncRequested++;
      };

      // Simuleer N gelijktijdige resync-verzoeken van meerdere followers.
      // We injecteren ze direct als stanzas (de follower-kant rate-limiter
      // staat op de emission-kant, hier testen we de autoriteit-kant coalesce).
      for (var i = 0; i < 5; i++) {
        final sealed = await env.guestCrypto.seal(
          {'kind': 'resync', 'from': 'guest'},
          room: env.room,
          type: OciDeckNamespace.resync,
          signed: false,
        );
        env.hostChannel.sendStanza(
          Stanza(
            kind: StanzaKind.message,
            type: 'groupchat',
            to: env.room,
            children: [
              xmppElement(
                'resync',
                namespace: OciDeckNamespace.resync,
                text: jsonEncode(sealed.toContent()),
              ),
            ],
          ),
        );
      }
      await env.settle();

      // Vijf verzoeken, maar slechts één re-baseline — de rest is gecoalesceerd.
      expect(resyncRequested, 1);
    });

    test(
      'a single follower does not flood resync requests (rate-limited)',
      () async {
        final env = await _XmppEnv.create(
          resyncMinInterval: const Duration(milliseconds: 200),
        );
        addTearDown(env.dispose);

        var resyncRequested = 0;
        env.hostTransport.onResyncRequested = () async {
          resyncRequested++;
        };

        // De guest-transport is al verbonden met guestChannel.onReconnected in
        // create. Meerdere reconnect-signalen binnen het rate-limiet-venster →
        // slechts één resync-emissie bereikt de autoriteit.
        env.guestChannel.rejoin();
        env.guestChannel.rejoin();
        env.guestChannel.rejoin();
        await env.settle();

        // Eén resync-verzoek bereikt de autoriteit (de andere twee zijn
        // rate-limited op de follower-kant).
        expect(resyncRequested, 1);
      },
    );
  });

  group('XmppTransport two-party over FakeMucHub', () {
    test('an authority edit reaches the guest, a lock round-trips', () async {
      final env = await _XmppEnv.create();
      addTearDown(env.dispose);
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'start');

      final hostSession = CollabSession(
        initialDeck: _deckWith(slide),
        transport: env.hostTransport,
        isAuthority: true,
      );
      final guestSession = CollabSession(
        initialDeck: _deckWith(slide),
        transport: env.guestTransport,
        isAuthority: false,
      );
      addTearDown(hostSession.dispose);
      addTearDown(guestSession.dispose);

      // Autoriteit edit → guest convergeert.
      await hostSession.submit(
        SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: slide.id,
          field: SlideField.title,
          value: 'renamed',
        ),
      );
      await env.settle();
      expect(guestSession.deck.slides.single.title, 'renamed');
      expect(guestSession.version, 1);

      // Lock round-trip: guest claimt, host ziet het; host forceert vrij.
      await guestSession.acquireLock(slide.id);
      await env.settle();
      expect(hostSession.locks[slide.id], 'guest');

      await hostSession.forceUnlock(slide.id);
      await env.settle();
      expect(guestSession.locks[slide.id], isNull);
    });

    test('a follower edit round-trips through the authority', () async {
      final env = await _XmppEnv.create();
      addTearDown(env.dispose);
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'start');

      final hostSession = CollabSession(
        initialDeck: _deckWith(slide),
        transport: env.hostTransport,
        isAuthority: true,
      );
      final guestSession = CollabSession(
        initialDeck: _deckWith(slide),
        transport: env.guestTransport,
        isAuthority: false,
      );
      addTearDown(hostSession.dispose);
      addTearDown(guestSession.dispose);

      await guestSession.submit(
        SetSlideField(
          version: 0,
          authorId: 'guest',
          slideId: slide.id,
          field: SlideField.subtitle,
          value: 'from guest',
        ),
      );
      await env.settle();

      expect(hostSession.deck.slides.single.subtitle, 'from guest');
      expect(guestSession.deck.slides.single.subtitle, 'from guest');
      expect(hostSession.version, 1);
      expect(guestSession.version, 1);
    });
  });
}

// ── test helpers ─────────────────────────────────────────────────────────────

/// De test-omgeving: twee XmppTransport's tegen een gedeelde FakeMucHub,
/// met vooraf gedeelde epoch-sleutels.
class _XmppEnv {
  _XmppEnv({
    required this.hub,
    required this.room,
    required this.hostChannel,
    required this.guestChannel,
    required this.hostDemux,
    required this.guestDemux,
    required this.hostTransport,
    required this.guestTransport,
    required this.hostCrypto,
    required this.guestCrypto,
    required this.hostPub,
    required this.guestPub,
    required this.knowsHostBox,
  });

  final FakeMucHub hub;
  final String room;
  final FakeMucChannel hostChannel;
  final FakeMucChannel guestChannel;
  final CompanionDemux hostDemux;
  final CompanionDemux guestDemux;
  final XmppTransport hostTransport;
  final XmppTransport guestTransport;
  final CollabCrypto hostCrypto;
  final CollabCrypto guestCrypto;
  final DevicePublicKeys hostPub;
  final DevicePublicKeys guestPub;

  /// Een één-elementige lijst als mutable box — de resolve-closure in [create]
  /// leest `knowsHostBox[0]`, en de test schrijft het om de deferred-backlog
  /// te triggeren (`env.knowsHostBox[0] = true`). Dart sluit over de variabele
  /// zelf, niet de waarde, dus een lokale bool in `create` was niet van buiten
  /// te muteren; een gedeelde lijst wel.
  final List<bool> knowsHostBox;

  /// Of de guest de host momenteel kan resolveren. Schrijf dit in de test
  /// om de deferred-backlog te triggeren.
  bool get knowsHost => knowsHostBox[0];
  set knowsHost(bool v) => knowsHostBox[0] = v;

  static Future<_XmppEnv> create({
    Duration resyncMinInterval = const Duration(milliseconds: 50),
    Duration resyncCoalesceWindow = const Duration(milliseconds: 50),
    bool knowsHost = true,
    DateTime Function()? now,
  }) async {
    const room = 'ocideck-test@conference.example';
    final hub = FakeMucHub(room);

    final hostKeys = await _device('host');
    final guestKeys = await _device('guest');
    final hostCrypto = CollabCrypto(hostKeys);
    final guestCrypto = CollabCrypto(guestKeys);
    final hostPub = await hostKeys.publicKeys(rot: 0);
    final guestPub = await guestKeys.publicKeys(rot: 0);
    final rk = await hostCrypto.rekey([guestPub]);
    await guestCrypto.installEpochKey(rk.wraps.single, hostPub);
    final directory = {'host': hostPub, 'guest': guestPub};

    // Mutable box voor de deferred-backlog-test: de closure leest box[0],
    // de test schrijft het via env.knowsHost.
    final knowsBox = [knowsHost];
    Future<DevicePublicKeys?> resolve(String id) async {
      if (id == 'host' && !knowsBox[0]) return null;
      return directory[id];
    }

    final hostChannel = hub.join('host');
    final guestChannel = hub.join('guest');
    final hostDemux = CompanionDemux(channel: hostChannel);
    final guestDemux = CompanionDemux(channel: guestChannel);

    final hostTransport = XmppTransport(
      stanzaChannel: hostChannel,
      companionDemux: hostDemux,
      crypto: hostCrypto,
      roomJid: room,
      peerResolver: resolve,
      resyncMinInterval: resyncMinInterval,
      resyncCoalesceWindow: resyncCoalesceWindow,
      now: now,
    );
    final guestTransport = XmppTransport(
      stanzaChannel: guestChannel,
      companionDemux: guestDemux,
      crypto: guestCrypto,
      roomJid: room,
      peerResolver: resolve,
      onReconnected: guestChannel.onReconnected,
      resyncMinInterval: resyncMinInterval,
      resyncCoalesceWindow: resyncCoalesceWindow,
      now: now,
    );

    return _XmppEnv(
      hub: hub,
      room: room,
      hostChannel: hostChannel,
      guestChannel: guestChannel,
      hostDemux: hostDemux,
      guestDemux: guestDemux,
      hostTransport: hostTransport,
      guestTransport: guestTransport,
      hostCrypto: hostCrypto,
      guestCrypto: guestCrypto,
      hostPub: hostPub,
      guestPub: guestPub,
      knowsHostBox: knowsBox,
    );
  }

  Future<void> settle() => pumpEventQueue(times: 100);

  Future<void> dispose() async {
    await hostTransport.dispose();
    await guestTransport.dispose();
    await hostDemux.dispose();
    await guestDemux.dispose();
    await hostChannel.close();
    await guestChannel.close();
  }
}

Future<CollabTransportPair> _createContractPair() async {
  const room = 'ocideck-contract@conference.example';
  final hub = FakeMucHub(room);

  final aKeys = await _device('alice');
  final bKeys = await _device('bob');
  final aCrypto = CollabCrypto(aKeys);
  final bCrypto = CollabCrypto(bKeys);
  final aPub = await aKeys.publicKeys(rot: 0);
  final bPub = await bKeys.publicKeys(rot: 0);
  final rk = await aCrypto.rekey([bPub]);
  await bCrypto.installEpochKey(rk.wraps.single, aPub);
  final directory = {'alice': aPub, 'bob': bPub};
  Future<DevicePublicKeys?> resolve(String id) async => directory[id];

  final aChannel = hub.join('alice');
  final bChannel = hub.join('bob');
  final aDemux = CompanionDemux(channel: aChannel);
  final bDemux = CompanionDemux(channel: bChannel);

  final aTransport = XmppTransport(
    stanzaChannel: aChannel,
    companionDemux: aDemux,
    crypto: aCrypto,
    roomJid: room,
    peerResolver: resolve,
  );
  final bTransport = XmppTransport(
    stanzaChannel: bChannel,
    companionDemux: bDemux,
    crypto: bCrypto,
    roomJid: room,
    peerResolver: resolve,
  );

  return CollabTransportPair(
    a: aTransport,
    b: bTransport,
    pump: () => pumpEventQueue(times: 100),
    dispose: () async {
      await aTransport.dispose();
      await bTransport.dispose();
      await aDemux.dispose();
      await bDemux.dispose();
      await aChannel.close();
      await bChannel.close();
    },
  );
}

Deck _deckWith(Slide s) => Deck(title: 'deck', slides: [s]);

/// Deterministische device-sleutels van een label (spiegelt de fixture in
/// `matrix_relay_transport_test.dart`).
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

/// Bouw een groupchat-op-stanza met [text] als de payload-text.
Stanza _fakeOpStanza(String room, String text) => Stanza(
  kind: StanzaKind.message,
  type: 'groupchat',
  to: room,
  children: [xmppElement('op', namespace: OciDeckNamespace.op, text: text)],
);

/// Stuur een verzegelde snapshot via [channel] als een `<snap>` groupchat.
Future<void> _sendSnapshot(
  FakeMucChannel channel,
  CollabCrypto crypto,
  String room,
  Deck deck,
  int version,
) async {
  final snap = CollabSnapshot.capture(deck, version, 0);
  final sealed = await crypto.seal(
    {'kind': 'snap', 'snapshot': snap.toJson()},
    room: room,
    type: OciDeckNamespace.snapshot,
    signed: true,
  );
  channel.sendStanza(
    Stanza(
      kind: StanzaKind.message,
      type: 'groupchat',
      to: room,
      children: [
        xmppElement(
          'snap',
          namespace: OciDeckNamespace.snapshot,
          text: jsonEncode(sealed.toContent()),
        ),
      ],
    ),
  );
}

/// Open een verzegelde snapshot uit een stanza.
Future<CollabSnapshot> _openSnapshot(
  Stanza stanza,
  CollabCrypto crypto,
  String room,
  DevicePublicKeys sender,
) async {
  XmlElement? snapChild;
  for (final child in stanza.children) {
    final ns = child.getAttribute('xmlns') ?? child.name.namespaceUri;
    if (ns == OciDeckNamespace.snapshot) {
      snapChild = child;
      break;
    }
  }
  if (snapChild == null) {
    throw StateError('snapshot stanza has no <snap> child');
  }
  final sealed = SealedEnvelope.fromContent(
    jsonDecode(snapChild.innerText) as Map<String, Object?>,
  );
  final opened = await crypto.open(
    sealed,
    room: room,
    type: OciDeckNamespace.snapshot,
    sender: sender,
  );
  return CollabSnapshot.fromJson(_asObject(opened['snapshot']));
}

Map<String, Object?> _asObject(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) return value.map((k, v) => MapEntry('$k', v));
  throw const FormatException('expected an object');
}
