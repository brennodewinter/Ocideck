// End-to-end tests for the relay transport (`lib/collab/matrix_relay_transport.dart`,
// SELF_ENCRYPTED_RELAY.md phase P-C): two real [CollabSession]s driven over
// [MatrixRelayTransport] against the shared in-Dart fake homeserver, with the ops
// sealed by [CollabCrypto]. The point is to prove the seam swap changed nothing
// *above* the transport — the authority/version/lock behaviour that the loopback
// tests (`collab_session_test.dart`) established still holds when events travel
// sealed through a (fake) homeserver. Delivery is not synchronous like the
// loopback, so the drive is explicit `syncOnce()` calls, exactly as the WebDAV
// transport tests drive `poll()`.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/collab/matrix_relay_transport.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

import 'fake_homeserver.dart';

void main() {
  const room = '!deck:hs.example';
  late FakeHomeserver hs;
  late _Party owner;
  late _Party peer;
  late Slide slide;

  setUp(() async {
    hs = FakeHomeserver();
    hs.addUser('owner', 'pw', userId: '@owner:hs.example');
    hs.addUser('peer', 'pw', userId: '@peer:hs.example');

    // Two device identities that already share epoch 0 (the P-A key-wrap flow;
    // distributing it over the wire is P-D). A directory resolves each peer.
    final ownerKeys = await _device('owner');
    final peerKeys = await _device('peer');
    final ownerCrypto = CollabCrypto(ownerKeys);
    final peerCrypto = CollabCrypto(peerKeys);
    final ownerPub = await ownerKeys.publicKeys();
    final peerPub = await peerKeys.publicKeys();
    final rk = await ownerCrypto.rekey([peerPub]);
    await peerCrypto.installEpochKey(rk.wraps.single, ownerPub);
    final directory = {'owner': ownerPub, 'peer': peerPub};
    Future<DevicePublicKeys?> resolve(String id) async => directory[id];

    owner = await _Party.create(
      hs,
      'owner',
      'pw',
      ownerCrypto,
      room,
      resolve,
      isAuthority: true,
    );
    peer = await _Party.create(
      hs,
      'peer',
      'pw',
      peerCrypto,
      room,
      resolve,
      isAuthority: false,
    );

    slide = Slide.create(SlideType.bullets).copyWith(title: 'start');
    owner.startSession(_deckWith(slide), isAuthority: true);
    peer.startSession(_deckWith(slide), isAuthority: false);
  });

  tearDown(() async {
    await owner.dispose();
    await peer.dispose();
  });

  test(
    'an authority edit reaches the follower, sealed through the relay',
    () async {
      await owner.session.submit(
        SetSlideField(
          version: 0,
          authorId: 'owner',
          slideId: slide.id,
          field: SlideField.title,
          value: 'renamed',
        ),
      );
      await _settle();
      await peer.transport.syncOnce();
      await _settle();

      expect(owner.session.deck.slides.single.title, 'renamed');
      expect(peer.session.deck.slides.single.title, 'renamed');
      expect(owner.session.version, 1);
      expect(peer.session.version, 1);
    },
  );

  test(
    'a follower edit round-trips through the authority and converges',
    () async {
      await peer.session.submit(
        SetSlideField(
          version: 0,
          authorId: 'peer',
          slideId: slide.id,
          field: SlideField.subtitle,
          value: 'from the peer',
        ),
      );
      await _settle();
      // Authority receives the intent, commits it (assigns a version, rebroadcasts).
      await owner.transport.syncOnce();
      await _settle();
      // Follower receives the authoritative op and applies it.
      await peer.transport.syncOnce();
      await _settle();

      expect(owner.session.deck.slides.single.subtitle, 'from the peer');
      expect(peer.session.deck.slides.single.subtitle, 'from the peer');
      expect(owner.session.version, 1);
      expect(peer.session.version, 1);
    },
  );

  test('a participant never applies its own echoed op', () async {
    await owner.session.submit(
      SetSlideField(
        version: 0,
        authorId: 'owner',
        slideId: slide.id,
        field: SlideField.title,
        value: 'once',
      ),
    );
    await _settle();
    // The authority syncs its OWN event back; own-echo suppression means it is
    // not re-applied, so the version does not advance a second time.
    await owner.transport.syncOnce();
    await _settle();

    expect(owner.session.version, 1);
    expect(owner.session.deck.slides.single.title, 'once');
  });

  test('a lock claim is delivered to the other participant', () async {
    await peer.session.acquireLock(slide.id);
    await _settle();
    await owner.transport.syncOnce();
    await _settle();

    expect(owner.session.locks[slide.id], 'peer');
  });

  test(
    'a malformed relay event is dropped without desyncing the session',
    () async {
      // Establish a baseline the follower is caught up to.
      await owner.session.submit(
        SetSlideField(
          version: 0,
          authorId: 'owner',
          slideId: slide.id,
          field: SlideField.title,
          value: 'good',
        ),
      );
      await _settle();
      await peer.transport.syncOnce();
      await _settle();
      expect(peer.session.deck.slides.single.title, 'good');

      // A garbage op event (not a sealed envelope) and an event from a device the
      // directory does not know both fail closed: logged, dropped, session intact.
      hs.pushTimeline(
        room,
        type: MatrixRelayTransport.opEventType,
        sender: '@evil:hs.example',
        content: {'not': 'a sealed envelope'},
      );
      await peer.transport.syncOnce();
      await _settle();

      expect(peer.session.deck.slides.single.title, 'good');
      expect(peer.session.version, 1);
    },
  );
}

Deck _deckWith(Slide s) => Deck(title: 'deck', slides: [s]);

Future<void> _settle() => pumpEventQueue(times: 100);

/// Deterministic device keys from a label (seeds are the label folded to 32
/// bytes), so every run reproduces the same identity — mirrors the P-A fixture.
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

/// One participant: a logged-in client, its relay transport, and (once started)
/// the session driven over it.
class _Party {
  _Party(this.transport);

  final MatrixRelayTransport transport;
  late final CollabSession session;

  static Future<_Party> create(
    FakeHomeserver hs,
    String user,
    String password,
    CollabCrypto crypto,
    String room,
    PeerResolver resolve, {
    required bool isAuthority,
  }) async {
    final client = MatrixClient(
      transport: hs,
      homeserver: Uri.parse('https://hs.example'),
    );
    await client.login(user: user, password: password);
    final transport = MatrixRelayTransport(
      client: client,
      crypto: crypto,
      roomId: room,
      resolvePeer: resolve,
    );
    return _Party(transport);
  }

  void startSession(Deck deck, {required bool isAuthority}) {
    session = CollabSession(
      initialDeck: deck,
      transport: transport,
      isAuthority: isAuthority,
    );
  }

  Future<void> dispose() => session.dispose(); // disposes the transport too
}
