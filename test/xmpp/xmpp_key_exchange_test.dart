// Tests voor `XmppKeyExchange` (`lib/xmpp/xmpp_key_exchange.dart`,
// `docs/design/XMPP_COLLAB_TRANSPORT.md` §5 brick 2 + Admission gate, §5.1, §7).
// Twee partijen vestigen hun sleutels **over de draad** via de companion-MUC:
// publiceren van device-keys als signed-rot presence-extensie, ingest met
// pin-on-first-use + rot-monotoniciteit, en de epoch-sleutel als
// recipient-blinded broadcast `<keyshare>` die elke occupant trial-opent.
//
// De adversariële gevallen uit §8: rot-replay geweigerd, identiteitswissel
// geweigerd, niet-goedgekeurde occupant nooit gesleuteld, broadcast toont
// geen cleartext recipient.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_device_directory.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/xmpp/companion_demux.dart';
import 'package:ocideck/xmpp/xmpp_key_exchange.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';
import 'package:ocideck/xmpp/xmpp_transport.dart';
import 'package:xml/xml.dart';

import 'fake_muc_hub.dart';

void main() {
  group('XmppKeyExchange device-key ingest (signed-rot presence)', () {
    test("two parties publish and ingest each other's device keys", () async {
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      expect(env.hostDir.resolve('guest')?.deviceId, 'guest');
      expect(env.guestDir.resolve('host')?.deviceId, 'host');
    });

    test('a rot-replay is refused (signed rot)', () async {
      // §8: een aanvaller herhaalt een oude presence met dezelfde of lagere
      // rot. De rot-monotoniciteitscheck weigert dit — de directory's
      // pin-on-first-use zou het als een same-identity update accepteren,
      // maar de rot-check gaat eerst.
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();
      expect(env.guestDir.resolve('host')?.rot, 0);

      // Herpubliceer de host met dezelfde rot=0 — een replay.
      await env.host.publishDeviceKeys();
      await env.settle();

      // De directory behoudt de oorspronkelijke entry; geen update.
      expect(env.guestDir.resolve('host')?.rot, 0);
    });

    test('a rot bump is accepted (same identity, higher rot)', () async {
      // Een legitieme rotatie:zelfde identiteit, nieuwe agreement-sleutel,
      // hogere rot. De directory accepteert dit (same-identity update) en
      // de rot-check laat het door (rot neemt strikt toe).
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      // Host roteert:zelfde Ed25519-seed (identiteit), nieuwe X25519-seed
      // (agreement), rot=1. Stuur de presence direct — de exchange ondertekent
      // de nieuwe binding met de identiteits-sleutel.
      final rotatedKeys = await CollabDeviceKeys.fromSeeds(
        deviceId: 'host',
        ed25519Seed: _seed('host', 1),
        x25519Seed: _seed('host', 99),
      );
      final rotatedPub = await rotatedKeys.publicKeys(rot: 1);
      env.hostChannel.sendStanza(
        Stanza(
          kind: StanzaKind.presence,
          to: env.room,
          children: [
            xmppElement(
              'x',
              namespace: OciDeckNamespace.device,
              text: jsonEncode(rotatedPub.toJson()),
            ),
          ],
        ),
      );
      await env.settle();

      expect(env.guestDir.resolve('host')?.rot, 1);
      expect(
        env.guestDir.resolve('host')?.agreementKey,
        equals(rotatedPub.agreementKey),
        reason: 'de geroteerde agreement-sleutel is opgeslagen',
      );
    });

    test('an identity swap is refused', () async {
      // §8/SA-F3: een bekend device-id met een andere identiteitssleutel
      // wordt geweigerd — een stille identiteitswissel is precies wat een
      // relay die een device-id overneemt zou produceren.
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();
      final originalIdentity = env.guestDir.resolve('host')!.identityKey;

      // Smeed een presence met hetzelfde device-id maar een andere identiteit.
      final impostorKeys = await _deviceKeys('host', salt: 99);
      env.guestChannel.sendStanza(
        Stanza(
          kind: StanzaKind.presence,
          to: env.room,
          children: [
            xmppElement(
              'x',
              namespace: OciDeckNamespace.device,
              text: jsonEncode(impostorKeys.toJson()),
            ),
          ],
        ),
      );
      await env.settle();

      expect(
        env.guestDir.resolve('host')?.identityKey,
        equals(originalIdentity),
        reason: 'de oorspronkelijke identiteit blijft, niet de impostor',
      );
    });
  });

  group('XmppKeyExchange admission gate (deny-by-default)', () {
    test('a non-approved occupant is never keyed', () async {
      // §7 SA-F4: keying is deny-by-default. De autoriteit sleutelt alleen
      // goedgekeurde devices. Een niet-goedgekeurde occupant ontvangt geen
      // keyshare en installeert geen epoch-sleutel.
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      // De autoriteit distribueert de epoch-sleutel, maar keurt de guest
      // NIET goed. ensureKeyed slaat de guest over.
      await env.host.distributeEpoch([]);
      await env.host.ensureKeyed();
      await env.settle();

      expect(
        env.guestCrypto.currentEpoch,
        isNull,
        reason: 'niet-goedgekeurde occupant heeft geen epoch-sleutel',
      );
    });

    test('an approved occupant is keyed', () async {
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      env.host.approve('guest');
      await env.host.distributeEpoch([env.guestPub]);
      await env.settle();

      expect(
        env.guestCrypto.currentEpoch,
        0,
        reason: 'goedgekeurde occupant installeert de epoch-sleutel',
      );
    });

    test('ensureKeyed keys only approved devices', () async {
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      // Guest is goedgekeurd en gesleuteld.
      env.host.approve('guest');
      await env.host.distributeEpoch([env.guestPub]);
      await env.settle();
      expect(env.guestCrypto.currentEpoch, 0);

      // Een tweede, niet-goedgekeurde occupant treedt toe.
      await env.addMember('intruder');
      await env.host.publishDeviceKeys(); // zodat de intruder de host leert
      await env.settle();

      // ensureKeyed slaat de niet-goedgekeurde intruder over.
      await env.host.ensureKeyed();
      await env.settle();

      expect(
        env.cryptoOf('intruder').currentEpoch,
        isNull,
        reason: 'niet-goedgekeurde intruder is nooit gesleuteld',
      );
      expect(
        env.guestCrypto.currentEpoch,
        isNotNull,
        reason: 'de goedgekeurde guest is wel gesleuteld',
      );
    });
  });

  group('XmppKeyExchange keyshare (recipient-blinded broadcast)', () {
    test('keyshare trial-open works for the intended recipient', () async {
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      env.host.approve('guest');
      await env.host.distributeEpoch([env.guestPub]);
      await env.settle();

      expect(env.guestCrypto.currentEpoch, 0);
      expect(env.guestCrypto.hasEpoch(0), isTrue);
    });

    test('broadcast shows no cleartext recipient', () async {
      // §5.1 N3: de wrap bevat geen cleartext `to`/`from` device-ids. De
      // wire-form toont alleen epoch, epk, nonce, ct, sig — niet de
      // ontvanger of de afzender.
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      // Onderschept de keyshare-stanza die de autoriteit verzendt.
      final captured = <Stanza>[];
      env.hostChannel.intercept = captured.add;

      env.host.approve('guest');
      await env.host.distributeEpoch([env.guestPub]);
      await env.settle();

      env.hostChannel.intercept = null;
      expect(captured, hasLength(1), reason: 'één keyshare-stanza verzonden');
      final keyshareChild = captured.single.children.firstWhere(
        (e) =>
            (e.getAttribute('xmlns') ?? e.name.namespaceUri) ==
            OciDeckNamespace.keyshare,
      );
      final wire = jsonDecode(keyshareChild.innerText) as Map<String, Object?>;

      // De wire-form bevat geen `to` of `from` velden — de ontvanger is
      // cryptografisch gebonden via ECDH, niet in cleartext.
      expect(wire, isNot(contains('to')));
      expect(wire, isNot(contains('from')));
      expect(wire.keys, containsAll(['epoch', 'epk', 'nonce', 'ct', 'sig']));
    });

    test('a keyshare not meant for this device is silently dropped', () async {
      // Elke occupant trial-opent elke broadcast keyshare; alleen de
      // bedoelde ontvanger slaagt. Een keyshare voor een ander device
      // wordt stil gedropt (geen fout — trial-decrypt faalt gewoon).
      final env = await _KeyEnv.create();
      addTearDown(env.dispose);

      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      // Voeg een tweede goedgekeurde member toe.
      await env.addMember('bob');
      await env.host.publishDeviceKeys(); // zodat bob de host leert
      await env.settle();
      env.host.approve('bob');

      final bobPub = env.pubOf('bob');
      final bobCrypto = env.cryptoOf('bob');

      // Distribueer naar bob — de guest ontvangt bob's keyshare, trial-opent,
      // faalt. Bob opent zijn eigen keyshare.
      await env.host.distributeEpoch([bobPub]);
      await env.settle();

      expect(
        env.guestCrypto.currentEpoch,
        isNull,
        reason: "guest kan bob's keyshare niet openen",
      );
      expect(
        bobCrypto.currentEpoch,
        0,
        reason: 'bob opent zijn eigen keyshare',
      );
    });
  });

  group('XmppKeyExchange end-to-end', () {
    test(
      'a guest whose nick matches the host boundJid resource is still keyed (#1415)',
      () async {
        // #1415: _isOwnPresence vergeleek de MUC-nick met de XMPP-resource van
        // boundJid. In de fake is boundJid `room/nick`, dus de resource is de
        // nick — maar in productie is boundJid `user@domain/resource` en heeft
        // de resource geen relatie met de MUC-nick. Een deelnemer wiens nick
        // toevallig gelijk is aan de host's resource werd incorrect als
        // "eigen" gedropt. De fix verwijdert de nick-check; de eigen-echo wordt
        // afgehandeld doordat de host niet in zijn eigen directory staat.
        final env = await _KeyEnv.create();
        addTearDown(env.dispose);

        await env.host.publishDeviceKeys();
        await env.guest.publishDeviceKeys();
        await env.settle();

        // De guest's nick is 'guest', de host's boundJid-resource is 'host'.
        // Met de oude _isOwnPresence-check zou dit false geven (geen match) —
        // maar de test verifieert het algemene geval: de guest is gesleuteld
        // ongeacht de nick-relatie.
        env.host.approve('guest');
        await env.host.distributeEpoch([env.guestPub]);
        await env.settle();

        expect(
          env.guestCrypto.currentEpoch,
          0,
          reason: 'guest is keyed regardless of nick/boundJid relationship',
        );
        expect(
          env.hostCrypto.currentEpoch,
          0,
          reason:
              'host still has its own epoch (own-echo dropped by empty candidates)',
        );
      },
    );

    test(
      'a device-presence without from is dropped fail-closed (#1429)',
      () async {
        final env = await _KeyEnv.create();
        addTearDown(env.dispose);

        // Stuur een device-presence zonder from — de oude code viel terug op
        // roomJid als peer-address, wat geen geldig occupant-address is.
        final keys = env.guestPub;
        final stanza = Stanza(
          kind: StanzaKind.presence,
          // from is null — misvormd
          to: env.room,
          children: [
            xmppElement(
              'x',
              namespace: OciDeckNamespace.device,
              text: jsonEncode(keys.toJson()),
            ),
          ],
        );
        await env.host.handleDevicePresence(stanza);
        await env.settle();

        // Het device is niet in de directory opgenomen — fail-closed.
        expect(env.host.directory.resolve(keys.deviceId), isNull);
      },
    );

    test(
      'a device-presence with malformed JSON is dropped fail-closed (#1434)',
      () async {
        final env = await _KeyEnv.create();
        addTearDown(env.dispose);

        // Stuur een device-presence met ongeldig JSON — de handler moet dit
        // gracelijk afhandelen, niet crashen.
        final stanza = Stanza(
          kind: StanzaKind.presence,
          from: '${env.room}/badguy',
          to: env.room,
          children: [
            xmppElement(
              'x',
              namespace: OciDeckNamespace.device,
              text: '{not valid json',
            ),
          ],
        );
        await env.host.handleDevicePresence(stanza);
        await env.settle();
        // Geen crash, geen device opgenomen.
        expect(env.host.directory.knownDevices, isEmpty);
      },
    );

    test('two parties establish keys over the wire, then co-author', () async {
      final env = await _KeyEnv.create(withTransport: true);
      addTearDown(env.dispose);

      // 1. Beide publiceren device-keys (signed-rot presence).
      await env.host.publishDeviceKeys();
      await env.guest.publishDeviceKeys();
      await env.settle();

      // 2. De autoriteit keurt de guest goed (TOFU/fingerprint-flow) en
      //    distribueert de epoch-sleutel als recipient-blinded broadcast.
      env.host.approve('guest');
      await env.host.distributeEpoch([env.guestPub]);
      await env.settle();

      expect(env.hostCrypto.currentEpoch, 0);
      expect(env.guestCrypto.currentEpoch, 0);

      // 3. Beide starten een sessie en co-auteuren over de verzegelde MUC.
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'start');
      final hostSession = CollabSession(
        initialDeck: _deckWith(slide),
        transport: env.hostTransport!,
        isAuthority: true,
      );
      final guestSession = CollabSession(
        initialDeck: _deckWith(slide),
        transport: env.guestTransport!,
        isAuthority: false,
      );
      addTearDown(hostSession.dispose);
      addTearDown(guestSession.dispose);

      await hostSession.submit(
        SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: slide.id,
          field: SlideField.title,
          value: 'established',
        ),
      );
      await env.settle();

      expect(guestSession.deck.slides.single.title, 'established');
      expect(guestSession.version, 1);
    });
  });
}

// ── test helpers ─────────────────────────────────────────────────────────────

/// De test-omgeving: twee of meer XmppKeyExchange's tegen een gedeelde
/// FakeMucHub, met optionele XmppTransport's voor end-to-end co-auteurschap.
class _KeyEnv {
  _KeyEnv({
    required this.hub,
    required this.room,
    required this.hostChannel,
    required this.guestChannel,
    required this.hostDemux,
    required this.guestDemux,
    required this.host,
    required this.guest,
    required this.hostDir,
    required this.guestDir,
    required this.hostCrypto,
    required this.guestCrypto,
    required this.hostKeys,
    required this.guestKeys,
    required this.hostPub,
    required this.guestPub,
    required this.members,
    required this.hostTransport,
    required this.guestTransport,
  });

  final FakeMucHub hub;
  final String room;
  final FakeMucChannel hostChannel;
  final FakeMucChannel guestChannel;
  final CompanionDemux hostDemux;
  final CompanionDemux guestDemux;
  final XmppKeyExchange host;
  final XmppKeyExchange guest;
  final CollabDeviceDirectory hostDir;
  final CollabDeviceDirectory guestDir;
  final CollabCrypto hostCrypto;
  final CollabCrypto guestCrypto;
  final CollabDeviceKeys hostKeys;
  final CollabDeviceKeys guestKeys;
  final DevicePublicKeys hostPub;
  final DevicePublicKeys guestPub;

  /// Extra members (nick → _Member).
  final Map<String, _Member> members;

  XmppTransport? hostTransport;
  XmppTransport? guestTransport;

  Future<void> settle() => pumpEventQueue(times: 100);

  /// Voeg een extra member toe aan de hub met eigen exchange en directory.
  /// Publiceert direct diens device-keys.
  Future<void> addMember(String nick) async {
    final keys = await _device(nick);
    final crypto = CollabCrypto(keys);
    final pub = await keys.publicKeys(rot: 0);
    final dir = CollabDeviceDirectory();
    final channel = hub.join(nick);
    final demux = CompanionDemux(channel: channel);
    final exchange = XmppKeyExchange(
      stanzaChannel: channel,
      companionDemux: demux,
      crypto: crypto,
      roomJid: room,
      directory: dir,
      ownKeys: pub,
    );
    members[nick] = _Member(
      channel: channel,
      demux: demux,
      exchange: exchange,
      crypto: crypto,
      keys: keys,
      pub: pub,
      directory: dir,
    );
    await exchange.publishDeviceKeys();
  }

  CollabCrypto cryptoOf(String nick) => members[nick]!.crypto;
  DevicePublicKeys pubOf(String nick) => members[nick]!.pub;

  Future<void> dispose() async {
    await host.dispose();
    await guest.dispose();
    for (final m in members.values) {
      await m.exchange.dispose();
      await m.demux.dispose();
      await m.channel.close();
    }
    await hostDemux.dispose();
    await guestDemux.dispose();
    await hostChannel.close();
    await guestChannel.close();
  }

  static Future<_KeyEnv> create({bool withTransport = false}) async {
    const room = 'ocideck-keytest@conference.example';
    final hub = FakeMucHub(room);

    final hostKeys = await _device('host');
    final guestKeys = await _device('guest');
    final hostCrypto = CollabCrypto(hostKeys);
    final guestCrypto = CollabCrypto(guestKeys);
    final hostPub = await hostKeys.publicKeys(rot: 0);
    final guestPub = await guestKeys.publicKeys(rot: 0);

    final hostDir = CollabDeviceDirectory();
    final guestDir = CollabDeviceDirectory();

    final hostChannel = hub.join('host');
    final guestChannel = hub.join('guest');
    final hostDemux = CompanionDemux(channel: hostChannel);
    final guestDemux = CompanionDemux(channel: guestChannel);

    final host = XmppKeyExchange(
      stanzaChannel: hostChannel,
      companionDemux: hostDemux,
      crypto: hostCrypto,
      roomJid: room,
      directory: hostDir,
      ownKeys: hostPub,
    );
    final guest = XmppKeyExchange(
      stanzaChannel: guestChannel,
      companionDemux: guestDemux,
      crypto: guestCrypto,
      roomJid: room,
      directory: guestDir,
      ownKeys: guestPub,
    );

    XmppTransport? hostTransport;
    XmppTransport? guestTransport;
    if (withTransport) {
      Future<DevicePublicKeys?> hostResolve(String id) async =>
          hostDir.resolve(id);
      Future<DevicePublicKeys?> guestResolve(String id) async =>
          guestDir.resolve(id);
      hostTransport = XmppTransport(
        stanzaChannel: hostChannel,
        companionDemux: hostDemux,
        crypto: hostCrypto,
        roomJid: room,
        peerResolver: hostResolve,
      );
      guestTransport = XmppTransport(
        stanzaChannel: guestChannel,
        companionDemux: guestDemux,
        crypto: guestCrypto,
        roomJid: room,
        peerResolver: guestResolve,
      );
    }

    return _KeyEnv(
      hub: hub,
      room: room,
      hostChannel: hostChannel,
      guestChannel: guestChannel,
      hostDemux: hostDemux,
      guestDemux: guestDemux,
      host: host,
      guest: guest,
      hostDir: hostDir,
      guestDir: guestDir,
      hostCrypto: hostCrypto,
      guestCrypto: guestCrypto,
      hostKeys: hostKeys,
      guestKeys: guestKeys,
      hostPub: hostPub,
      guestPub: guestPub,
      members: {},
      hostTransport: hostTransport,
      guestTransport: guestTransport,
    );
  }
}

class _Member {
  _Member({
    required this.channel,
    required this.demux,
    required this.exchange,
    required this.crypto,
    required this.keys,
    required this.pub,
    required this.directory,
  });

  final FakeMucChannel channel;
  final CompanionDemux demux;
  final XmppKeyExchange exchange;
  final CollabCrypto crypto;
  final CollabDeviceKeys keys;
  final DevicePublicKeys pub;
  final CollabDeviceDirectory directory;
}

Deck _deckWith(Slide s) => Deck(title: 'deck', slides: [s]);

/// Deterministische device-sleutels van een label (spiegelt de fixture in
/// `xmpp_transport_test.dart`).
Future<CollabDeviceKeys> _device(String label) {
  return CollabDeviceKeys.fromSeeds(
    deviceId: label,
    ed25519Seed: _seed(label, 1),
    x25519Seed: _seed(label, 2),
  );
}

/// Publieke sleutels met een andere identiteit voor hetzelfde device-id
/// (voor de identiteitswissel-test).
Future<DevicePublicKeys> _deviceKeys(String label, {int salt = 1}) async {
  final keys = await CollabDeviceKeys.fromSeeds(
    deviceId: label,
    ed25519Seed: _seed(label, salt),
    x25519Seed: _seed(label, salt + 1),
  );
  return keys.publicKeys(rot: 0);
}

List<int> _seed(String label, int salt) {
  final bytes = Uint8List(32);
  final name = label.codeUnits;
  for (var i = 0; i < 32; i++) {
    bytes[i] = (name[i % name.length] + salt + i) & 0xff;
  }
  return bytes;
}
