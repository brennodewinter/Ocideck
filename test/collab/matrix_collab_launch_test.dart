// End-to-end test of the app-level orchestration (`lib/collab/matrix_collab_launch.dart`,
// P-D UX): host creates a room + shares a link, guest pastes it and joins — device
// keys loaded from the keychain, all over the fake homeserver — then they
// co-author. The layer under test is the seam a provider calls: room creation,
// device-key loading and the invite link, on top of the already-tested session
// lifecycle.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_device_store.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/collab/matrix_collab_launch.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/matrix_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/secret_store.dart';

import 'fake_homeserver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeserver = 'https://hs.example';
  late FakeHomeserver hs;
  late SecretStore secretStore;

  setUp(() {
    hs = FakeHomeserver();
    hs.addUser('host', 'pw', userId: '@host:hs.example');
    hs.addUser('guest', 'pw', userId: '@guest:hs.example');
    FlutterSecureStorage.setMockInitialValues({});
    secretStore = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
  });

  Future<MatrixClient> login(String user) async {
    final client = MatrixClient(
      transport: hs,
      homeserver: Uri.parse(homeserver),
    );
    await client.login(user: user, password: 'pw');
    return client;
  }

  MatrixServer account(String userId, String deviceId) => MatrixServer(
    homeserverUrl: homeserver,
    userId: userId,
    deviceId: deviceId,
  );

  test('host shares a link, guest joins it, and they co-author', () async {
    final hostClient = await login('host');
    final guestClient = await login('guest');

    final hostSlide = Slide.create(SlideType.bullets).copyWith(title: 'start');
    final host = await hostMatrixCollab(
      client: hostClient,
      secretStore: secretStore,
      account: account('@host:hs.example', 'hostdev'),
      deck: Deck(title: 'deck', slides: [hostSlide]),
    );
    expect(host.inviteLink, startsWith('https://matrix.to/#/'));

    // The guest opened the same .md independently, so its slide id differs.
    final guest = await joinMatrixCollab(
      client: guestClient,
      secretStore: secretStore,
      account: account('@guest:hs.example', 'guestdev'),
      localDeck: Deck(
        title: 'deck',
        slides: [Slide.create(SlideType.bullets).copyWith(title: 'start')],
      ),
      inviteLink: host.inviteLink,
    );

    await host.launch.syncNow(); // learns the guest, sends the key-share
    await guest.syncNow(); // gets device + key-share + baseline, starts
    await _settle();

    expect(guest.isActive, isTrue);
    expect(guest.session!.deck.slides.single.id, hostSlide.id);

    await host.launch.session!.submit(
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

    await host.launch.dispose();
    await guest.dispose();
  });

  test('joining a non-invite is refused', () async {
    final client = await login('guest');
    await expectLater(
      () => joinMatrixCollab(
        client: client,
        secretStore: secretStore,
        account: account('@guest:hs.example', 'guestdev'),
        localDeck: Deck(title: 'd', slides: [Slide.create(SlideType.bullets)]),
        inviteLink: 'just some text',
      ),
      throwsA(
        isA<MatrixException>().having(
          (e) => e.kind,
          'kind',
          MatrixErrorKind.config,
        ),
      ),
    );
  });

  test('the device identity is persisted and reused across sessions', () async {
    final acct = account('@host:hs.example', 'hostdev');
    final first = await loadOrCreateDeviceKeys(
      secretStore: secretStore,
      homeserver: acct.homeserverUrl,
      userId: acct.userId,
      deviceId: acct.deviceId,
    );
    // hostMatrixCollab reuses the same stored seeds — same identity.
    final hostClient = await login('host');
    final host = await hostMatrixCollab(
      client: hostClient,
      secretStore: secretStore,
      account: acct,
      deck: Deck(title: 'd', slides: [Slide.create(SlideType.bullets)]),
    );
    // The published device key equals the persisted one (same seeds).
    final reloaded = await loadOrCreateDeviceKeys(
      secretStore: secretStore,
      homeserver: acct.homeserverUrl,
      userId: acct.userId,
      deviceId: acct.deviceId,
    );
    expect(
      (await reloaded.publicKeys(rot: 0)).identityKey,
      (await first.publicKeys(rot: 0)).identityKey,
    );
    await host.launch.dispose();
  });
}

Future<void> _settle() => pumpEventQueue(times: 100);
