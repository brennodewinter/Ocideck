// Tests voor `XmppSnapshotChannel` (`lib/xmpp/xmpp_snapshot.dart`,
// `docs/design/XMPP_COLLAB_TRANSPORT.md` §5 brick 3, §4, sub-plak 6): de
// sessie-baseline rijdt verzegeld en **gechunked** over de companion-MUC —
// één AEAD-tag over de hele baseline, de ciphertext-blob verspreid over
// `<snap>`-stanzas — en reassembleert + opent aan de andere kant met de
// autoriteit's slide-id's behouden (§5.5, de reden dat een snapshot bestaat).
// Fail-closed: een gesmokkelde of ontbrekende chunk levert geen snapshot, en
// een baseline die aankomt vóór de epoch-sleutel wordt gebufferd tot
// [retryPending] (de joiner ziet de chunks vóór zijn keyshare, §6).

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_device_directory.dart';
import 'package:ocideck/collab/collab_snapshot.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/xmpp/companion_demux.dart';
import 'package:ocideck/xmpp/xmpp_snapshot.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';
import 'package:ocideck/xmpp/xmpp_transport.dart' show OciDeckNamespace;
import 'package:xml/xml.dart';

import 'fake_muc_hub.dart';

void main() {
  test('a chunked snapshot reassembles with slide ids preserved', () async {
    final env = await _SnapEnv.create();
    addTearDown(env.dispose);

    await env.authority.sendSnapshot(env.sent);
    await env.settle();

    final received = await env.receiver.firstSnapshot;
    expect(received.version, env.sent.version);
    expect(received.slides.map((s) => s.id), env.sent.slides.map((s) => s.id));
    expect(received.slides.first.title, env.sent.slides.first.title);
  });

  test('a single-stanza snapshot (no chunking) still opens', () async {
    final env = await _SnapEnv.create(maxChunkChars: 1 << 20);
    addTearDown(env.dispose);

    await env.authority.sendSnapshot(env.sent);
    await env.settle();

    final received = await env.receiver.firstSnapshot;
    expect(received.slides.map((s) => s.id), env.sent.slides.map((s) => s.id));
  });

  test('a tampered chunk yields no snapshot (fail-closed)', () async {
    final env = await _SnapEnv.create();
    addTearDown(env.dispose);
    final chunks = await _captureChunks(env: env);

    // Vermink de eerste chunk's data-veld; voed de rest ongewijzigd.
    final tampered = [...chunks];
    final first = tampered.first;
    final child = first.children.firstWhere(
      (c) =>
          (c.getAttribute('xmlns') ?? c.name.namespaceUri) ==
          OciDeckNamespace.snapshot,
    );
    final decoded = jsonDecode(child.innerText) as Map<String, Object?>;
    decoded['data'] = 'xx${decoded['data']}';
    tampered[0] = Stanza(
      kind: StanzaKind.message,
      type: 'groupchat',
      from: first.from,
      to: first.to,
      id: first.id,
      children: [
        xmppElement(
          'snap',
          namespace: OciDeckNamespace.snapshot,
          text: jsonEncode(decoded),
        ),
      ],
    );

    var completed = false;
    unawaited(env.receiver.firstSnapshot.then((_) => completed = true));
    for (final s in tampered) {
      await env.receiver.handleSnapshot(s);
    }
    await env.settle();
    expect(completed, isFalse);
  });

  test('a missing chunk yields no snapshot', () async {
    final env = await _SnapEnv.create();
    addTearDown(env.dispose);
    final chunks = await _captureChunks(env: env);

    var completed = false;
    unawaited(env.receiver.firstSnapshot.then((_) => completed = true));
    // Drop de eerste chunk — de rest komt aan, maar de baseline reassembleert
    // nooit (een ontbrekend stuk).
    for (final s in chunks.skip(1)) {
      await env.receiver.handleSnapshot(s);
    }
    await env.settle();
    expect(completed, isFalse);
  });

  test(
    'a chunk spoofing another sender deviceId is dropped (#1411)',
    () async {
      final env = await _SnapEnv.create();
      addTearDown(env.dispose);
      final chunks = await _captureChunks(env: env);

      // Een vijandige occupant stuurt een chunk die de autoriteit's deviceId
      // in het `id` claimt, maar vanuit een andere nick (`from`). De
      // afzender-controle moet hem fail-closed droppen.
      final first = chunks.first;
      final child = first.children.firstWhere(
        (c) =>
            (c.getAttribute('xmlns') ?? c.name.namespaceUri) ==
            OciDeckNamespace.snapshot,
      );
      final decoded = jsonDecode(child.innerText) as Map<String, Object?>;
      final spoofed = Stanza(
        kind: StanzaKind.message,
        type: 'groupchat',
        from: '${env.room}/hostile',
        to: first.to,
        id: first.id,
        children: [
          xmppElement(
            'snap',
            namespace: OciDeckNamespace.snapshot,
            text: jsonEncode({
              ...decoded,
              'data': 'garbage',
            }),
          ),
        ],
      );

      var completed = false;
      unawaited(env.receiver.firstSnapshot.then((_) => completed = true));
      // De spoofed chunk eerst, dan de legitieme chunks — de spoofed moet
      // gedropt zijn, zodat de legitieme baseline ongeschonden reassembleert.
      await env.receiver.handleSnapshot(spoofed);
      for (final s in chunks) {
        await env.receiver.handleSnapshot(s);
      }
      await env.settle();

      expect(completed, isTrue);
      final received = await env.receiver.firstSnapshot;
      expect(
        received.slides.map((s) => s.id),
        env.sent.slides.map((s) => s.id),
      );
    },
  );

  test(
    'a snapshot that arrives before its key is buffered, then opens',
    () async {
      final env = await _SnapEnv.create(keyReceiver: false);
      addTearDown(env.dispose);

      // De baseline arriveert vóór de epoch-sleutel — gebufferd, niet gedropt.
      await env.authority.sendSnapshot(env.sent);
      await env.settle();
      expect(env.receiver.hasSnapshot, isFalse);

      // Nu installeert de receiver de sleutel en retryPending opent de buffer.
      await env.installKey();
      await env.receiver.retryPending();
      await env.settle();

      expect(env.receiver.hasSnapshot, isTrue);
      final received = await env.receiver.firstSnapshot;
      expect(
        received.slides.map((s) => s.id),
        env.sent.slides.map((s) => s.id),
      );
    },
  );

  test(
    'a re-baseline snapshot (after the first) emits on rebaselines',
    () async {
      final env = await _SnapEnv.create();
      addTearDown(env.dispose);

      await env.authority.sendSnapshot(env.sent);
      await env.settle();
      await env.receiver.firstSnapshot;

      final rebaselines = <CollabSnapshot>[];
      final sub = env.receiver.rebaselines.listen(rebaselines.add);

      // De autoriteit re-baselineert (§4 resync) op een hogere versie.
      final advanced = CollabSnapshot.capture(
        Deck(title: 't', slides: env.sent.slides).copyWith(
          slides: [
            env.sent.slides.first.copyWith(title: 'rebased'),
            ...env.sent.slides.skip(1),
          ],
        ),
        7,
        0,
      );
      await env.authority.sendSnapshot(advanced);
      await env.settle();

      expect(rebaselines, hasLength(1));
      expect(rebaselines.single.version, 7);
      expect(rebaselines.single.slides.first.title, 'rebased');
      await sub.cancel();
    },
  );

  test(
    'the assembled map is bounded — overflow evicts the oldest (#1414)',
    () async {
      // Geen epoch-sleutel bij de receiver: elke snapshot reassembleert en
      // blijft in _assembled staan (onopenbaar). De cap op _assembled voorkomt
      // onbegrensde groei — een vijandige server kan niet cyclen.
      final env = await _SnapEnv.create(
        keyReceiver: false,
        maxAssembledSnapshots: 2,
      );
      addTearDown(env.dispose);

      // Stuur 4 snapshots; _assembled past er 2, dus de oudste worden verdreven.
      for (var i = 0; i < 4; i++) {
        await env.authority.sendSnapshot(
          CollabSnapshot.capture(
            Deck(
              title: 't',
              slides: env.sent.slides,
            ).copyWith(
              slides: [
                env.sent.slides.first.copyWith(title: 'v$i'),
                ...env.sent.slides.skip(1),
              ],
            ),
            i + 1,
            0,
          ),
        );
        await env.settle();
      }

      // Installeer de sleutel en heropen — slechts 2 snapshots overleven de
      // cap: 1 voltooit firstSnapshot, 1 emit op rebaselines.
      final rebaselines = <CollabSnapshot>[];
      final sub = env.receiver.rebaselines.listen(rebaselines.add);
      await env.installKey();
      await env.receiver.retryPending();
      await env.settle();

      expect(env.receiver.hasSnapshot, isTrue);
      expect(
        rebaselines,
        hasLength(1),
        reason: 'only maxAssembledSnapshots survive — 1 first + 1 re-baseline',
      );
      await sub.cancel();
    },
  );
}

// ── test helpers ─────────────────────────────────────────────────────────────

/// Twee [XmppSnapshotChannel]s tegen een gedeelde [FakeMucHub]: een autoriteit
/// die zendt en een receiver die ontvangt. Sleutels vooraf gedeeld tenzij
/// [keyReceiver] false (dan installeert de receiver pas na [installKey]).
class _SnapEnv {
  _SnapEnv({
    required this.hub,
    required this.room,
    required this.authorityChannel,
    required this.receiverChannel,
    required this.authorityDemux,
    required this.receiverDemux,
    required this.authority,
    required this.receiver,
    required this.authorityCrypto,
    required this.receiverCrypto,
    required this.authorityPub,
    required this.receiverPub,
    required this.receiverDirectory,
    required this.rekeyResult,
    required this.sent,
  });

  final FakeMucHub hub;
  final String room;
  final FakeMucChannel authorityChannel;
  final FakeMucChannel receiverChannel;
  final CompanionDemux authorityDemux;
  final CompanionDemux receiverDemux;
  final XmppSnapshotChannel authority;
  final XmppSnapshotChannel receiver;
  final CollabCrypto authorityCrypto;
  final CollabCrypto receiverCrypto;
  final DevicePublicKeys authorityPub;
  final DevicePublicKeys receiverPub;
  final CollabDeviceDirectory receiverDirectory;
  final RekeyResult rekeyResult;
  final CollabSnapshot sent;

  static Future<_SnapEnv> create({
    int maxChunkChars = 200,
    bool keyReceiver = true,
    void Function(Stanza)? intercept,
    int maxAssembledSnapshots = 4,
  }) async {
    const room = 'ocideck-snap@conference.example';
    final hub = FakeMucHub(room);

    final authKeys = await _device('auth');
    final recvKeys = await _device('recv');
    final authorityCrypto = CollabCrypto(authKeys);
    final receiverCrypto = CollabCrypto(recvKeys);
    final authorityPub = await authKeys.publicKeys(rot: 0);
    final receiverPub = await recvKeys.publicKeys(rot: 0);
    final rekey = await authorityCrypto.rekey([receiverPub]);
    if (keyReceiver) {
      await receiverCrypto.installEpochKey(rekey.wraps.single, authorityPub);
    }

    final receiverDirectory = CollabDeviceDirectory();
    await receiverDirectory.ingest(
      peerAddress: '$room/auth',
      keys: authorityPub,
    );

    final authorityChannel = hub.join('auth');
    final receiverChannel = hub.join('recv');
    // De autoriteit's uitgaande stanzas onderscheppen vóór routing (voor de
    // tamper/missing-chunk testen). De receiver-kant hoeft niet.
    authorityChannel.intercept = intercept;
    final authorityDemux = CompanionDemux(channel: authorityChannel);
    final receiverDemux = CompanionDemux(channel: receiverChannel);

    final authority = XmppSnapshotChannel(
      stanzaChannel: authorityChannel,
      companionDemux: authorityDemux,
      crypto: authorityCrypto,
      roomJid: room,
      directory: CollabDeviceDirectory(),
      maxChunkChars: maxChunkChars,
    );
    final receiver = XmppSnapshotChannel(
      stanzaChannel: receiverChannel,
      companionDemux: receiverDemux,
      crypto: receiverCrypto,
      roomJid: room,
      directory: receiverDirectory,
      maxChunkChars: maxChunkChars,
      maxAssembledSnapshots: maxAssembledSnapshots,
    );

    final slides = [
      for (var i = 0; i < 4; i++)
        Slide.create(SlideType.bullets).copyWith(
          title: 'slide $i with enough text to grow the payload a bit',
        ),
    ];
    final sent = CollabSnapshot.capture(Deck(title: 't', slides: slides), 3, 0);

    return _SnapEnv(
      hub: hub,
      room: room,
      authorityChannel: authorityChannel,
      receiverChannel: receiverChannel,
      authorityDemux: authorityDemux,
      receiverDemux: receiverDemux,
      authority: authority,
      receiver: receiver,
      authorityCrypto: authorityCrypto,
      receiverCrypto: receiverCrypto,
      authorityPub: authorityPub,
      receiverPub: receiverPub,
      receiverDirectory: receiverDirectory,
      rekeyResult: rekey,
      sent: sent,
    );
  }

  /// Installeer de epoch-sleutel achteraf (voor de buffer-tot-keyed test).
  Future<void> installKey() async {
    await receiverCrypto.installEpochKey(
      rekeyResult.wraps.single,
      authorityPub,
    );
  }

  Future<void> settle() => pumpEventQueue(times: 100);

  Future<void> dispose() async {
    await authority.dispose();
    await receiver.dispose();
    await authorityDemux.dispose();
    await receiverDemux.dispose();
    await authorityChannel.close();
    await receiverChannel.close();
  }
}

/// Leg de chunk-stanzas vast die de autoriteit verzendt, zónder dat de
/// receiver ze via de hub ontvangt (de receiver wordt tijdelijk gedropt).
/// De tamper/missing-testen voeden ze daarna (gewijzigd of onvolledig) direct
/// aan [XmppSnapshotChannel.handleSnapshot] — spiegelt de matrix-test die
/// `handleSystemEvent` direct voert.
Future<List<Stanza>> _captureChunks({required _SnapEnv env}) async {
  final recorded = <Stanza>[];
  // De hub zet `from` op reflectie (room@conf/nick); de intercept ziet de
  // uitgaande stanza vóór routing, dus zet het zelf — de chunks worden
  // direct aan handleSnapshot gevoed en de afzender-controle (#1411) leest
  // `from`.
  env.authorityChannel.intercept = (s) {
    recorded.add(
      Stanza(
        kind: s.kind,
        type: s.type,
        from: '${env.room}/auth',
        to: s.to,
        id: s.id,
        children: s.children,
      ),
    );
  };
  env.receiverChannel.drop();
  await env.authority.sendSnapshot(env.sent);
  await env.settle();
  env.receiverChannel.rejoin();
  env.authorityChannel.intercept = null;
  return recorded;
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
