// End-to-end tests for the relay transport (`lib/collab/matrix_relay_transport.dart`,
// SELF_ENCRYPTED_RELAY.md phase P-C): two real [CollabSession]s driven over
// [MatrixRelayTransport] against the shared in-Dart fake homeserver, with the ops
// sealed by [CollabCrypto]. The point is to prove the seam swap changed nothing
// *above* the transport — the authority/version/lock behaviour that the loopback
// tests (`collab_session_test.dart`) established still holds when events travel
// sealed through a (fake) homeserver. Delivery is not synchronous like the
// loopback, so the drive is explicit `syncOnce()` calls, exactly as the WebDAV
// transport tests drive `poll()`.

import 'dart:async';
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
  late _GatingTransport ownerHttp;

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

    // The owner's egress is wrapped so a test can hold its first op PUT and
    // prove the send chain keeps later ops behind it. Inert until armed, so
    // every other test behaves exactly as before.
    ownerHttp = _GatingTransport(hs);
    owner = await _Party.create(
      hs,
      'owner',
      'pw',
      ownerCrypto,
      room,
      resolve,
      isAuthority: true,
      httpTransport: ownerHttp,
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

  test(
    'overlapping authority sends reach the follower in version order (#1040)',
    () async {
      // Two authority edits in quick succession. `submit` commits synchronously
      // for the authority, so both authoritative ops (v1 then v2) are handed to
      // the transport before either PUT completes — the overlap the bug needs.
      // The first op's PUT is held; without the serial send chain the second
      // op's PUT would reach the room first, the follower would drop v2 (it only
      // accepts version + 1) and land on v1 forever.
      ownerHttp.holdFirstOpSend();
      unawaited(
        owner.session.submit(
          SetSlideField(
            version: 0,
            authorId: 'owner',
            slideId: slide.id,
            field: SlideField.title,
            value: 'first',
          ),
        ),
      );
      unawaited(
        owner.session.submit(
          SetSlideField(
            version: 0,
            authorId: 'owner',
            slideId: slide.id,
            field: SlideField.title,
            value: 'second',
          ),
        ),
      );
      await _settle();
      // v1's PUT is still parked; v2 must be queued behind it, not already sent.
      ownerHttp.releaseFirstOpSend();
      await _settle();

      await peer.transport.syncOnce();
      await _settle();

      expect(peer.session.version, 2);
      expect(peer.session.deck.slides.single.title, 'second');
    },
  );

  test(
    'an op that arrives before its sender is known is retried, not lost (#1041)',
    () async {
      // The initial-sync race: at a joiner's first sync a timeline op can be
      // delivered before the sender's device-state has registered the sender's
      // keys, and the since-cursor advances past the op regardless. A follower
      // that dropped it there would lose the edit forever and stay a version
      // behind. Two identities sharing epoch 0; the joiner's directory is blind
      // to the authority until its device-state is "processed", which
      // `resolvePeer` returning null models.
      final hs2 = FakeHomeserver()
        ..addUser('auth', 'pw', userId: '@auth:hs.example')
        ..addUser('join', 'pw', userId: '@join:hs.example');
      final authKeys = await _device('auth');
      final joinKeys = await _device('join');
      final authCrypto = CollabCrypto(authKeys);
      final joinCrypto = CollabCrypto(joinKeys);
      final authPub = await authKeys.publicKeys();
      final joinPub = await joinKeys.publicKeys();
      final rk = await authCrypto.rekey([joinPub]);
      await joinCrypto.installEpochKey(rk.wraps.single, authPub);
      final dir = {'auth': authPub, 'join': joinPub};

      var knowsAuth = false;
      Future<DevicePublicKeys?> authResolve(String id) async => dir[id];
      Future<DevicePublicKeys?> joinResolve(String id) async =>
          (id == 'auth' && !knowsAuth) ? null : dir[id];

      final authority = await _Party.create(
        hs2,
        'auth',
        'pw',
        authCrypto,
        room,
        authResolve,
        isAuthority: true,
      );
      final joiner = await _Party.create(
        hs2,
        'join',
        'pw',
        joinCrypto,
        room,
        joinResolve,
        isAuthority: false,
      );
      addTearDown(authority.dispose);
      addTearDown(joiner.dispose);
      final s = Slide.create(SlideType.bullets).copyWith(title: 'start');
      authority.startSession(_deckWith(s), isAuthority: true);
      joiner.startSession(_deckWith(s), isAuthority: false);

      // The authority edits before the joiner can resolve it.
      await authority.session.submit(
        SetSlideField(
          version: 0,
          authorId: 'auth',
          slideId: s.id,
          field: SlideField.title,
          value: 'early',
        ),
      );
      await _settle();

      // First sync: the op arrives, its sender is unknown, so it is held (not
      // dropped). The version does not advance yet — but the edit is not lost.
      await joiner.transport.syncOnce();
      await _settle();
      expect(joiner.session.version, 0);
      expect(joiner.session.deck.slides.single.title, 'start');

      // The device-state is now processed; a further sync (empty timeline)
      // replays the backlog and the held op finally applies.
      knowsAuth = true;
      await joiner.transport.syncOnce();
      await _settle();
      expect(joiner.session.version, 1);
      expect(joiner.session.deck.slides.single.title, 'early');
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
    MatrixHttpTransport? httpTransport,
  }) async {
    final client = MatrixClient(
      transport: httpTransport ?? hs,
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

/// Wraps a homeserver transport and can park the *first* op-send PUT until
/// released, so a test can force two overlapping sends to race at the egress.
/// Inert until [holdFirstOpSend] is called; everything else is passed straight
/// through, so it is invisible to the other tests.
class _GatingTransport implements MatrixHttpTransport {
  _GatingTransport(this._inner);

  final MatrixHttpTransport _inner;
  Completer<void>? _gate;
  var _opSends = 0;

  void holdFirstOpSend() => _gate = Completer<void>();
  void releaseFirstOpSend() {
    if (_gate?.isCompleted == false) _gate!.complete();
  }

  @override
  Future<MatrixHttpResponse> send({
    required String method,
    required Uri url,
    Map<String, String> headers = const {},
    String? body,
  }) async {
    final isOpSend =
        url.pathSegments.contains('send') &&
        url.pathSegments.contains(MatrixRelayTransport.opEventType);
    if (isOpSend && _gate != null) {
      _opSends++;
      if (_opSends == 1) await _gate!.future;
    }
    return _inner.send(method: method, url: url, headers: headers, body: body);
  }
}
