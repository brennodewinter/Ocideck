// The Matrix account UI (PR-3b of the #977 vertical slice): the form state, the
// panel with its whoami-driven "test" button, and the collaboration tab in the
// settings dialog. The account-setup approach is deliberate (2026-08-01): the
// app never touches a password — the user pastes a homeserver and an access
// token, and the test button confirms it via whoami and fills in the user id and
// device id (the latter matters for correctness, SELF_ENCRYPTED_RELAY.md §4.3).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/matrix_client.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/matrix_settings.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings/matrix_form.dart';
import 'package:ocideck/widgets/dialogs/settings/matrix_panel.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'collab/fake_homeserver.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('MatrixForm', () {
    test('config fills a missing https scheme and trims', () {
      final form = MatrixForm();
      addTearDown(form.dispose);
      form.homeserver.text = ' matrix.example.org ';
      form.userId.text = ' @u:matrix.example.org ';
      form.deviceId.text = ' DEV1 ';
      expect(form.config.homeserverUrl, 'https://matrix.example.org');
      expect(form.config.userId, '@u:matrix.example.org');
      expect(form.config.deviceId, 'DEV1');
    });

    test('adoptFrom round-trips an account into the fields', () {
      final form = MatrixForm();
      addTearDown(form.dispose);
      form.adoptFrom(
        const MatrixServer(
          homeserverUrl: 'https://hs.example',
          userId: '@u:hs.example',
          deviceId: 'DEV2',
          trustedInternal: true,
        ),
      );
      expect(form.homeserver.text, 'https://hs.example');
      expect(form.userId.text, '@u:hs.example');
      expect(form.deviceId.text, 'DEV2');
      expect(form.trusted, isTrue);
    });

    test('the keychain identity is homeserver|user-id', () {
      expect(
        MatrixForm.identityOf('https://hs.example', '@u:hs.example'),
        'https://hs.example|@u:hs.example',
      );
    });

    test('saveSecret writes the token to the keychain', () async {
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({});
      final notifier = SettingsNotifier(
        secretStore: SecretStore(
          storage: const FlutterSecureStorage(),
          canStore: true,
        ),
      );
      addTearDown(notifier.dispose);
      final form = MatrixForm();
      addTearDown(form.dispose);
      form.homeserver.text = 'https://hs.example';
      form.userId.text = '@u:hs.example';
      form.token.field.text = 'secret-token';

      form.saveSecret(notifier);
      await pumpEventQueue();

      expect(await notifier.matrixToken(form.config), 'secret-token');
    });
  });

  group('MatrixPanel', () {
    late MatrixForm form;
    setUp(() => form = MatrixForm());
    tearDown(() => form.dispose());

    Future<void> show(
      WidgetTester tester, {
      MatrixTestClientBuilder? buildTestClient,
    }) async {
      await tester.binding.setSurfaceSize(const Size(800, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: MatrixPanel(
                form: form,
                canStore: true,
                buildTestClient: buildTestClient,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('renders the account fields', (tester) async {
      await show(tester);
      expect(find.text('Homeserver'), findsOneWidget);
      expect(find.text('Access-token'), findsOneWidget);
      expect(find.text('Gebruikers-id'), findsOneWidget);
      expect(find.text('Apparaat-id'), findsOneWidget);
    });

    testWidgets('an empty homeserver is refused before any network call', (
      tester,
    ) async {
      await show(tester);
      await tester.tap(find.text('Verbinding testen'));
      await tester.pumpAndSettle();
      expect(find.text('Vul een geldige homeserver-URL in'), findsOneWidget);
      expect(form.testOk, isFalse);
    });

    testWidgets('a homeserver without a token is refused', (tester) async {
      await show(tester);
      form.homeserver.text = 'https://hs.example';
      await tester.tap(find.text('Verbinding testen'));
      await tester.pumpAndSettle();
      expect(find.text('Vul een access-token in'), findsOneWidget);
      expect(form.testOk, isFalse);
    });

    testWidgets('a valid token fills the user id and device id via whoami', (
      tester,
    ) async {
      final hs = FakeHomeserver()
        ..addUser('alice', 'pw', userId: '@alice:hs.example');
      final probe = MatrixClient(
        transport: hs,
        homeserver: Uri.parse('https://hs.example'),
      );
      final session = await probe.login(user: 'alice', password: 'pw');

      await show(
        tester,
        buildTestClient: (account, token) => MatrixClient(
          transport: hs,
          homeserver: account.origin!,
          accessToken: token,
        ),
      );
      form.homeserver.text = 'https://hs.example';
      form.token.field.text = session.accessToken;

      await tester.tap(find.text('Verbinding testen'));
      await tester.pumpAndSettle();

      expect(form.testOk, isTrue);
      expect(form.userId.text, '@alice:hs.example');
      expect(form.deviceId.text, session.deviceId);
      expect(find.textContaining('Verbinding gelukt'), findsOneWidget);
    });

    testWidgets('a rejected token shows an auth error', (tester) async {
      final hs = FakeHomeserver();
      await show(
        tester,
        buildTestClient: (account, token) => MatrixClient(
          transport: hs,
          homeserver: account.origin!,
          accessToken: token,
        ),
      );
      form.homeserver.text = 'https://hs.example';
      form.token.field.text = 'bogus';

      await tester.tap(find.text('Verbinding testen'));
      await tester.pumpAndSettle();

      expect(form.testOk, isFalse);
      expect(
        find.textContaining('access-token wordt geweigerd'),
        findsOneWidget,
      );
    });
  });

  group('the collaboration tab in the settings dialog', () {
    testWidgets('opens the Matrix account panel', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.binding.setSurfaceSize(const Size(1500, 1100));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ref.watch(settingsProvider);
                  return ElevatedButton(
                    onPressed: () => SettingsDialog.show(
                      context,
                      initialSection: SettingsSection.collaboration,
                    ),
                    child: const Text('open'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(SettingsDialog), findsOneWidget);
      expect(find.byType(MatrixPanel), findsOneWidget);
      expect(find.text('Homeserver'), findsOneWidget);
    });
  });
}
