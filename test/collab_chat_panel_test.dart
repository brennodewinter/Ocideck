// The session chat panel (PR-3f of the #977 slice). One test pumps it idle (the
// empty state and the send path), the other stands up a real host session over
// the fake homeserver and confirms a sent message renders in the panel.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/l10n/app_localizations.dart';
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
import 'package:ocideck/widgets/panels/collab_chat_panel.dart';

import 'collab/fake_homeserver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets('shows the empty state and clears the field on send', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: SizedBox(width: 320, child: CollabChatPanel())),
        ),
      ),
    );
    expect(find.textContaining('Nog geen berichten'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'hoi');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();
    // The root session is idle, so the send is a no-op — but the field clears.
    expect(find.text('hoi'), findsNothing);
  });

  testWidgets('renders a message sent in a live session', (tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    final secrets = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
    final hs = FakeHomeserver()
      ..addUser('host', 'pw', userId: '@host:hs.example');
    final client = MatrixClient(
      transport: hs,
      homeserver: Uri.parse('https://hs.example'),
    );
    await client.login(user: 'host', password: 'pw');

    final md = MarkdownService();
    final deckN = DeckNotifier(
      md,
      FileService(md, ImageService(), () => const ThemeProfile()),
    )..loadDeck(Deck(title: 'd', slides: [Slide.create(SlideType.bullets)]));
    final tab = TabInfo(
      id: 1,
      recoveryId: 'r',
      deckNotifier: deckN,
      editorNotifier: EditorNotifier(),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          matrixAccountProvider.overrideWithValue(
            const MatrixServer(
              homeserverUrl: 'https://hs.example',
              userId: '@host:hs.example',
              deviceId: 'hostdev',
            ),
          ),
          matrixClientProvider.overrideWith((ref) async => client),
          secretStoreProvider.overrideWithValue(secrets),
          deckProvider.overrideWith((ref) => deckN),
          collabSessionProvider.overrideWith(
            (ref) => CollabSessionNotifier(ref, tab),
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: SizedBox(width: 320, child: CollabChatPanel())),
        ),
      ),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(CollabChatPanel)),
    );
    final notifier = container.read(collabSessionProvider.notifier);
    // Always end the session, so the launch's periodic sync timer is cancelled
    // even if an expectation below throws.
    addTearDown(() async => notifier.leave());

    await notifier.hostMatrix();
    // Let _finishMatrix settle (host is active at once) so the chat is wired.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(container.read(collabSessionProvider).isActive, isTrue);

    await notifier.sendChatMessage('welkom allemaal');
    await tester.pump();

    expect(find.text('welkom allemaal'), findsOneWidget);
  });
}
