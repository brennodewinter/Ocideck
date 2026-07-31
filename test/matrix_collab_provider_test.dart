// The app-glue that makes the Matrix data plane usable from a tab: the
// `matrixClientProvider`/`buildMatrixClient` seam and the `CollabSessionNotifier`
// Matrix host/join branch (`docs/design/SELF_ENCRYPTED_RELAY.md` §6.5). The
// crypto, transport and session lifecycle are tested in their own files against
// the fake homeserver; here we test only the provider wiring: an account resolves
// to a client, a host goes active and shares a link, a guest joins that link and
// goes active once the baseline arrives, and the error keys the UI localises.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/matrix_settings.dart';
import 'package:ocideck/models/settings.dart' show ThemeProfile;
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/collab_session_provider.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/matrix_client_provider.dart';
import 'package:ocideck/state/secret_store_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';

import 'collab/fake_homeserver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const homeserver = 'https://hs.example';
  late SecretStore secrets;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    secrets = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
  });

  MatrixServer account(String userId, String deviceId) => MatrixServer(
    homeserverUrl: homeserver,
    userId: userId,
    deviceId: deviceId,
  );

  Future<MatrixClient> login(FakeHomeserver hs, String user) async {
    final client = MatrixClient(
      transport: hs,
      homeserver: Uri.parse(homeserver),
    );
    await client.login(user: user, password: 'pw');
    return client;
  }

  DeckNotifier deckWith(Deck deck) {
    final md = MarkdownService();
    final file = FileService(md, ImageService(), () => const ThemeProfile());
    return DeckNotifier(md, file)..loadDeck(deck);
  }

  TabInfo tabFor(DeckNotifier deckN) => TabInfo(
    id: 1,
    recoveryId: 'rec',
    deckNotifier: deckN,
    editorNotifier: EditorNotifier(),
  );

  ProviderContainer containerFor({
    MatrixServer? account,
    MatrixClient? client,
    required DeckNotifier deckN,
    required TabInfo tab,
  }) {
    final container = ProviderContainer(
      overrides: [
        matrixAccountProvider.overrideWithValue(account),
        matrixClientProvider.overrideWith((ref) async => client),
        secretStoreProvider.overrideWithValue(secrets),
        deckProvider.overrideWith((ref) => deckN),
        collabSessionProvider.overrideWith(
          (ref) => CollabSessionNotifier(ref, tab),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Deck oneSlide(String title) => Deck(
    title: 'd',
    slides: [Slide.create(SlideType.bullets).copyWith(title: title)],
  );

  group('buildMatrixClient', () {
    test('builds a client on the account origin carrying the token', () {
      final client = buildMatrixClient(
        account: account('@u:hs.example', 'dev'),
        token: 'tok',
        transport: FakeHomeserver(),
      );
      expect(client.accessToken, 'tok');
    });

    test('throws config when the homeserver url has no host', () {
      expect(
        () => buildMatrixClient(
          account: const MatrixServer(
            homeserverUrl: 'not-a-url',
            userId: '@u:hs',
            deviceId: 'dev',
          ),
          token: null,
          transport: FakeHomeserver(),
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
  });

  group('matrixClientProvider', () {
    test('is null when no account is configured', () async {
      final container = ProviderContainer(
        overrides: [matrixAccountProvider.overrideWithValue(null)],
      );
      addTearDown(container.dispose);
      expect(await container.read(matrixClientProvider.future), isNull);
    });
  });

  group('CollabSessionNotifier — Matrix', () {
    test('hosting reaches active and exposes an invite link', () async {
      final hs = FakeHomeserver()
        ..addUser('host', 'pw', userId: '@host:hs.example');
      final deckN = deckWith(oneSlide('a'));
      final tab = tabFor(deckN);
      final container = containerFor(
        account: account('@host:hs.example', 'hostdev'),
        client: await login(hs, 'host'),
        deckN: deckN,
        tab: tab,
      );
      final notifier = container.read(collabSessionProvider.notifier);

      await notifier.hostMatrix();
      await pumpEventQueue();

      final state = container.read(collabSessionProvider);
      expect(state.phase, CollabPhase.active);
      expect(state.role, CollabRole.host);
      expect(state.inviteLink, startsWith('https://matrix.to/#/'));
      expect(tab.collabSession, isNotNull);

      await notifier.leave();
      expect(container.read(collabSessionProvider).phase, CollabPhase.idle);
    });

    test('a guest joins the shared link and reaches active', () async {
      final hs = FakeHomeserver()
        ..addUser('host', 'pw', userId: '@host:hs.example')
        ..addUser('guest', 'pw', userId: '@guest:hs.example');

      final hostSlide = Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'start');
      final hostDeckN = deckWith(Deck(title: 'd', slides: [hostSlide]));
      final hostTab = tabFor(hostDeckN);
      final hostContainer = containerFor(
        account: account('@host:hs.example', 'hostdev'),
        client: await login(hs, 'host'),
        deckN: hostDeckN,
        tab: hostTab,
      );
      final hostN = hostContainer.read(collabSessionProvider.notifier);
      await hostN.hostMatrix();
      await pumpEventQueue();
      final link = hostContainer.read(collabSessionProvider).inviteLink!;

      // The guest opened the same .md independently, so its slide id differs.
      final guestDeckN = deckWith(oneSlide('start'));
      final guestTab = tabFor(guestDeckN);
      final guestContainer = containerFor(
        account: account('@guest:hs.example', 'guestdev'),
        client: await login(hs, 'guest'),
        deckN: guestDeckN,
        tab: guestTab,
      );
      final guestN = guestContainer.read(collabSessionProvider.notifier);
      await guestN.joinMatrix(link);
      await pumpEventQueue();
      // Not yet active: the baseline is still in flight.
      expect(
        guestContainer.read(collabSessionProvider).phase,
        CollabPhase.connecting,
      );

      // Host learns the guest and sends the key-share; the guest then fetches the
      // device keys, the key-share and the baseline, and opens its session.
      await hostN.debugMatrixSyncNow();
      await guestN.debugMatrixSyncNow();
      await pumpEventQueue();

      final guestState = guestContainer.read(collabSessionProvider);
      expect(guestState.phase, CollabPhase.active);
      expect(guestState.role, CollabRole.guest);
      // The guest adopted the authority's slide-id space (§5.5).
      expect(guestTab.collabSession!.deck.slides.single.id, hostSlide.id);

      await hostN.leave();
      await guestN.leave();
    });

    test('a malformed invite fails with bad-invite', () async {
      final hs = FakeHomeserver()
        ..addUser('guest', 'pw', userId: '@guest:hs.example');
      final deckN = deckWith(oneSlide('a'));
      final tab = tabFor(deckN);
      final container = containerFor(
        account: account('@guest:hs.example', 'guestdev'),
        client: await login(hs, 'guest'),
        deckN: deckN,
        tab: tab,
      );

      await container.read(collabSessionProvider.notifier).joinMatrix('nope');
      await pumpEventQueue();

      final state = container.read(collabSessionProvider);
      expect(state.phase, CollabPhase.failed);
      expect(state.error, 'bad-invite');
    });

    test(
      'hosting without a configured account fails with no-matrix-account',
      () async {
        final deckN = deckWith(oneSlide('a'));
        final tab = tabFor(deckN);
        final container = containerFor(
          account: null,
          client: null,
          deckN: deckN,
          tab: tab,
        );

        await container.read(collabSessionProvider.notifier).hostMatrix();

        expect(
          container.read(collabSessionProvider).error,
          'no-matrix-account',
        );
      },
    );
  });
}
