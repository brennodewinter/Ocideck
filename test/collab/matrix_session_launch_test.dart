// End-to-end tests for the Matrix session lifecycle
// (`lib/collab/matrix_session_launch.dart`, SELF_ENCRYPTED_RELAY.md §6.5, phase
// P-D): a host starts a session and a guest joins it **entirely over the fake
// homeserver** — device keys, key-share and the chunked baseline all travelling
// the wire — after which the guest has adopted the authority's slide-id space
// (§5.5, the whole point of the snapshot) and the two co-author both ways.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_crypto.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/collab/matrix_session_launch.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

import 'fake_homeserver.dart';

void main() {
  const room = '!deck:hs.example';
  late FakeHomeserver hs;
  late MatrixClient hostClient;
  late MatrixClient guestClient;
  late CollabCrypto hostCrypto;
  late CollabCrypto guestCrypto;
  late DevicePublicKeys hostPub;
  late DevicePublicKeys guestPub;

  setUp(() async {
    hs = FakeHomeserver();
    hs.addUser('host', 'pw', userId: '@host:hs.example');
    hs.addUser('guest', 'pw', userId: '@guest:hs.example');
    final hostKeys = await _device('host');
    final guestKeys = await _device('guest');
    hostCrypto = CollabCrypto(hostKeys);
    guestCrypto = CollabCrypto(guestKeys);
    hostPub = await hostKeys.publicKeys();
    guestPub = await guestKeys.publicKeys();
    hostClient = await _login(hs, 'host');
    guestClient = await _login(hs, 'guest');
  });

  test('a guest joins over the wire, adopts slide ids, and co-authors', () async {
    final hostSlide = Slide.create(SlideType.bullets).copyWith(title: 'start');
    final host = await hostMatrixSession(
      client: hostClient,
      crypto: hostCrypto,
      ownKeys: hostPub,
      ownUserId: '@host:hs.example',
      roomId: room,
      deck: Deck(title: 'deck', slides: [hostSlide]),
    );
    // The guest opened the "same" .md independently, so its local slide has a
    // *different* id — the snapshot must overwrite it with the authority's.
    final guestLocal = Deck(
      title: 'deck',
      slides: [Slide.create(SlideType.bullets).copyWith(title: 'start')],
    );
    expect(guestLocal.slides.single.id, isNot(hostSlide.id));

    final guest = await joinMatrixSession(
      client: guestClient,
      crypto: guestCrypto,
      ownKeys: guestPub,
      ownUserId: '@guest:hs.example',
      roomId: room,
      localDeck: guestLocal,
    );

    // Drive the handshake: the host learns the guest and sends the key-share; the
    // guest then receives device state + key-share + baseline and starts.
    await host.syncNow();
    await guest.syncNow();
    await _settle();

    expect(guest.isActive, isTrue, reason: 'the guest received the baseline');
    expect(
      guest.session!.deck.slides.single.id,
      hostSlide.id,
      reason: 'the guest adopted the authority slide id',
    );

    // Authority edit → guest.
    await host.session!.submit(
      SetSlideField(
        version: 0,
        authorId: 'host',
        slideId: hostSlide.id,
        field: SlideField.title,
        value: 'shared',
      ),
    );
    await _settle();
    await guest.syncNow();
    await _settle();
    expect(guest.session!.deck.slides.single.title, 'shared');

    // Guest edit → authority → back to guest (the follower round-trip).
    await guest.session!.submit(
      SetSlideField(
        version: 0,
        authorId: 'guest',
        slideId: hostSlide.id,
        field: SlideField.subtitle,
        value: 'from the guest',
      ),
    );
    await _settle();
    await host.syncNow();
    await _settle();
    await guest.syncNow();
    await _settle();
    expect(host.session!.deck.slides.single.subtitle, 'from the guest');
    expect(guest.session!.deck.slides.single.subtitle, 'from the guest');

    await host.dispose();
    await guest.dispose();
  });

  test('a guest is not active before the baseline arrives', () async {
    final host = await hostMatrixSession(
      client: hostClient,
      crypto: hostCrypto,
      ownKeys: hostPub,
      ownUserId: '@host:hs.example',
      roomId: room,
      deck: Deck(title: 'deck', slides: [Slide.create(SlideType.bullets)]),
    );
    final guest = await joinMatrixSession(
      client: guestClient,
      crypto: guestCrypto,
      ownKeys: guestPub,
      ownUserId: '@guest:hs.example',
      roomId: room,
      localDeck: Deck(title: 'deck', slides: [Slide.create(SlideType.bullets)]),
    );

    // The guest syncs before the host has keyed it: no baseline can open yet.
    await guest.syncNow();
    await _settle();
    expect(guest.isActive, isFalse);

    // Once the host reacts and the guest syncs again, it starts.
    await host.syncNow();
    await guest.syncNow();
    await _settle();
    expect(guest.isActive, isTrue);

    await host.dispose();
    await guest.dispose();
  });
}

Future<void> _settle() => pumpEventQueue(times: 100);

Future<MatrixClient> _login(FakeHomeserver hs, String user) async {
  final client = MatrixClient(
    transport: hs,
    homeserver: Uri.parse('https://hs.example'),
  );
  await client.login(user: user, password: 'pw');
  return client;
}

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
