// Tests voor `XmppChat` (`lib/xmpp/xmpp_chat.dart`,
// `docs/design/XMPP_COLLAB_TRANSPORT.md` §5 brick 5, §3, §4, §8, sub-plak 7):
// de sessie-chat over de companion-MUC — de XMPP-tegenhanger van `MatrixChat`,
// met één kritiek verschil dat voortvloeit uit §4: een MUC heeft geen `/sync`-
// cursor, dus MAM/resync herleveren een bericht, en chat heeft (net als Matrix)
// geen dedup. Daarom draagt elk `<chat>`-bericht een **id = hash van de
// verzegelde bytes** (`sealed.toContent()`, inclusief een verse per-seal nonce —
// een geforceerde botsing is onmogelijk en een replay is correct idempotent; een
// *plaintext* hash zou ten onrechte identieke tekst onderdrukken). De dedup-set
// is begrensd. Chat is **ondertekend** (elk lid houdt dezelfde epoch-sleutel, dus
// een ondertekend bericht laat één lid er een vervalsen toegeschreven aan een
// ander — een slechte handtekening wordt fail-closed gedropt).

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_device_directory.dart';
import 'package:ocideck/xmpp/companion_demux.dart';
import 'package:ocideck/xmpp/xmpp_chat.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';
import 'package:ocideck/xmpp/xmpp_transport.dart' show OciDeckNamespace;
import 'package:xml/xml.dart';

import 'fake_muc_hub.dart';

void main() {
  test('a signed chat line arrives sealed and opens at the receiver', () async {
    final env = await _ChatEnv.create();
    addTearDown(env.dispose);

    await env.sender.send('hallo');
    await env.settle();

    expect(env.receiver.messages, hasLength(1));
    expect(env.receiver.messages.single.text, 'hallo');
    expect(env.receiver.messages.single.deviceId, env.senderCrypto.deviceId);
    expect(env.receiver.messages.single.isSelf, isFalse);
  });

  test(
    'own echo is suppressed — the sender sees only its local echo',
    () async {
      final env = await _ChatEnv.create();
      addTearDown(env.dispose);

      await env.sender.send('hallo');
      await env.settle();

      // De MUC reflecteert de afzender zijn eigen bericht terug; de sender ziet
      // enkel de lokale echo (isSelf: true), niet een tweede exemplaar.
      expect(env.sender.messages, hasLength(1));
      expect(env.sender.messages.single.text, 'hallo');
      expect(env.sender.messages.single.isSelf, isTrue);
    },
  );

  test('chat dedups a replayed sealed-id (§4)', () async {
    final env = await _ChatEnv.create();
    addTearDown(env.dispose);

    // Onderschept de uitgaande stanza vóór de hub hem routeert.
    Stanza? captured;
    env.senderChannel.intercept = (s) {
      captured = s;
      env.senderChannel.intercept = null;
    };
    await env.sender.send('hallo');
    await env.settle();
    expect(env.receiver.messages, hasLength(1), reason: 'first copy arrives');

    // Herlever dezelfde stanza (een MAM/resync-herlevering) — hetzelfde
    // verzegelde-id, dus de dedup dropt hem.
    final replay = captured!;
    env.senderChannel.intercept = null;
    await env.receiver.handleChat(replay);
    await env.settle();

    expect(
      env.receiver.messages,
      hasLength(1),
      reason: 'a replayed sealed-id is deduped, not doubled',
    );
  });

  test('a tampered signature is rejected fail-closed (§8)', () async {
    final env = await _ChatEnv.create();
    addTearDown(env.dispose);

    Stanza? captured;
    env.senderChannel.intercept = (s) {
      captured = s;
      env.senderChannel.intercept = null;
    };
    await env.sender.send('hallo');
    await env.settle();
    // De receiver kreeg het origineel al via de hub — reset zijn berichtenlijst
    // zodat de tampered-levering de enige is die telt.
    env.receiver.discardMessages();

    final decoded =
        jsonDecode(
              captured!.children
                  .firstWhere(
                    (c) =>
                        (c.getAttribute('xmlns') ?? c.name.namespaceUri) ==
                        OciDeckNamespace.chat,
                  )
                  .innerText,
            )
            as Map<String, Object?>;
    final sealed = decoded['sealed'] as Map<String, Object?>;
    // Flip een byte in de base64-handtekening — de Ed25519-verificatie faalt.
    final sig = sealed['sig'] as String;
    sealed['sig'] = sig.replaceFirst(
      sig[sig.length - 1],
      sig[sig.length - 1] == 'A' ? 'B' : 'A',
      sig.length - 1,
    );
    final tampered = Stanza(
      kind: StanzaKind.message,
      type: 'groupchat',
      to: captured!.to,
      children: [
        xmppElement(
          'chat',
          namespace: OciDeckNamespace.chat,
          text: jsonEncode({'id': decoded['id'], 'sealed': sealed}),
        ),
      ],
    );
    await env.receiver.handleChat(tampered);
    await env.settle();

    expect(
      env.receiver.messages,
      isEmpty,
      reason: 'a bad signature is dropped fail-closed',
    );
  });

  test(
    'a chat that arrives before its key is buffered, then opens on retry',
    () async {
      final env = await _ChatEnv.create(keyReceiver: false);
      addTearDown(env.dispose);

      await env.sender.send('hallo');
      await env.settle();
      expect(env.receiver.messages, isEmpty, reason: 'buffered before keying');

      await env.installKey();
      await env.receiver.retryPending();
      await env.settle();

      expect(env.receiver.messages, hasLength(1));
      expect(env.receiver.messages.single.text, 'hallo');
    },
  );

  test(
    'an unknown sender does not block later messages (no head-of-line, #1412)',
    () async {
      final env = await _ChatEnv.create();
      addTearDown(env.dispose);

      // Een bericht van een onbekende afzender ('ghost') — niet in de
      // directory, dus _open retourneert null en het blijft in _pending staan.
      // Met de oude code blokkeerde dit alle latere berichten (head-of-line
      // blocking); nu wordt het overgeslagen.
      final ghost = SealedEnvelope(
        epoch: 0,
        nonce: List.filled(24, 0),
        ciphertext: List.filled(32, 0),
        senderDevice: 'ghost',
      );
      final ghostStanza = Stanza(
        kind: StanzaKind.message,
        type: 'groupchat',
        to: env.room,
        children: [
          xmppElement(
            'chat',
            namespace: OciDeckNamespace.chat,
            text: jsonEncode({
              'id': 'ghost-id',
              'sealed': ghost.toContent(),
            }),
          ),
        ],
      );
      await env.receiver.handleChat(ghostStanza);
      await env.settle();
      expect(env.receiver.messages, isEmpty, reason: 'unknown sender buffered');

      // Nu een legitiem bericht van de bekende afzender — dit moet door de
      // gebufferde 'ghost' heen verschijnen, niet erachter vastlopen.
      await env.sender.send('hallo');
      await env.settle();
      expect(env.receiver.messages, hasLength(1));
      expect(env.receiver.messages.single.text, 'hallo');
    },
  );

  test(
    'the dedup set is bounded — an evicted id is no longer suppressed',
    () async {
      // ponytail: de dedup-set is begrensd (§4 "like the message list"). De
      // plafond-ceiling: na dedupCap unieke berichten wordt het oudste id
      // verwijderd, waarna een replay daarvan wél opnieuw verschijnt. Dat is de
      // bewuste afruil tegen een onbegrensde set — een vijandige server kan de
      // set niet uitputten, maar een oude herlevering kan na verdrijving terug-
      // komen. Dit test documenteert dat plafond.
      final env = await _ChatEnv.create(dedupCap: 2);
      addTearDown(env.dispose);

      // Stuur drie unieke berichten; de set past er 2, dus het id van 'm1' wordt
      // verdreven als 'm3' aankomt — de set houdt dan [id2, id3].
      final captured = <Stanza>[];
      env.senderChannel.intercept = captured.add;
      await env.sender.send('m1');
      await env.settle();
      await env.sender.send('m2');
      await env.settle();
      await env.sender.send('m3');
      await env.settle();
      env.senderChannel.intercept = null;
      expect(env.receiver.messages, hasLength(3));

      // Eerst de live replay: 'm3' staat nog in de set → nog steeds gedropt.
      await env.receiver.handleChat(captured[2]);
      await env.settle();
      expect(
        env.receiver.messages,
        hasLength(3),
        reason: 'a live id is still deduped',
      );

      // Dan de verdreven replay: 'm1' is uit de set → komt opnieuw door.
      await env.receiver.handleChat(captured.first);
      await env.settle();
      expect(
        env.receiver.messages,
        hasLength(4),
        reason:
            'an evicted sealed-id is no longer deduped (the bounded ceiling)',
      );
    },
  );
}

// ── test helpers ─────────────────────────────────────────────────────────────

/// Twee [XmppChat]s tegen een gedeelde [FakeMucHub]: een sender die zendt en een
/// receiver die ontvangt. Sleutels vooraf gedeeld tenzij [keyReceiver] false.
class _ChatEnv {
  _ChatEnv({
    required this.hub,
    required this.room,
    required this.senderChannel,
    required this.receiverChannel,
    required this.senderDemux,
    required this.receiverDemux,
    required this.sender,
    required this.receiver,
    required this.senderCrypto,
    required this.receiverCrypto,
    required this.senderPub,
    required this.rekeyResult,
  });

  final FakeMucHub hub;
  final String room;
  final FakeMucChannel senderChannel;
  final FakeMucChannel receiverChannel;
  final CompanionDemux senderDemux;
  final CompanionDemux receiverDemux;
  final XmppChat sender;
  final XmppChat receiver;
  final CollabCrypto senderCrypto;
  final CollabCrypto receiverCrypto;
  final DevicePublicKeys senderPub;
  final RekeyResult rekeyResult;

  static Future<_ChatEnv> create({
    bool keyReceiver = true,
    int dedupCap = 256,
  }) async {
    const room = 'ocideck-chat@conference.example';
    final hub = FakeMucHub(room);

    final sendKeys = await _device('send');
    final recvKeys = await _device('recv');
    final senderCrypto = CollabCrypto(sendKeys);
    final receiverCrypto = CollabCrypto(recvKeys);
    final senderPub = await sendKeys.publicKeys(rot: 0);
    final receiverPub = await recvKeys.publicKeys(rot: 0);
    final rekey = await senderCrypto.rekey([receiverPub]);
    if (keyReceiver) {
      await receiverCrypto.installEpochKey(rekey.wraps.single, senderPub);
    }

    final receiverDirectory = CollabDeviceDirectory();
    await receiverDirectory.ingest(peerAddress: '$room/send', keys: senderPub);

    final senderChannel = hub.join('send');
    final receiverChannel = hub.join('recv');
    final senderDemux = CompanionDemux(channel: senderChannel);
    final receiverDemux = CompanionDemux(channel: receiverChannel);

    final sender = XmppChat(
      stanzaChannel: senderChannel,
      companionDemux: senderDemux,
      crypto: senderCrypto,
      roomJid: room,
      directory: CollabDeviceDirectory(),
      ownUserId: '$room/send',
      dedupCap: dedupCap,
    );
    final receiver = XmppChat(
      stanzaChannel: receiverChannel,
      companionDemux: receiverDemux,
      crypto: receiverCrypto,
      roomJid: room,
      directory: receiverDirectory,
      ownUserId: '$room/recv',
      dedupCap: dedupCap,
    );

    return _ChatEnv(
      hub: hub,
      room: room,
      senderChannel: senderChannel,
      receiverChannel: receiverChannel,
      senderDemux: senderDemux,
      receiverDemux: receiverDemux,
      sender: sender,
      receiver: receiver,
      senderCrypto: senderCrypto,
      receiverCrypto: receiverCrypto,
      senderPub: senderPub,
      rekeyResult: rekey,
    );
  }

  Future<void> installKey() async {
    await receiverCrypto.installEpochKey(rekeyResult.wraps.single, senderPub);
  }

  Future<void> settle() => pumpEventQueue(times: 100);

  Future<void> dispose() async {
    await sender.dispose();
    await receiver.dispose();
    await senderDemux.dispose();
    await receiverDemux.dispose();
    await senderChannel.close();
    await receiverChannel.close();
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
