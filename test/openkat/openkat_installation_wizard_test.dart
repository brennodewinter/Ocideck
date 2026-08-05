import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/secret_store_provider.dart';
import 'package:ocideck/widgets/dialogs/openkat_installation_wizard.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Widget _appWithSecrets(SecretStore secrets, Widget child) {
  return ProviderScope(
    overrides: [secretStoreProvider.overrideWithValue(secrets)],
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    ),
  );
}

Future<void> _settleOpenKat(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Future<void> _fillStep0(
  WidgetTester tester, {
  String name = 'Productie',
  String url = 'https://openkat.example',
}) async {
  await tester.enterText(find.byType(TextField).first, name);
  await tester.enterText(find.byType(TextField).at(1), url);
}

Future<void> _goToStep1(WidgetTester tester) async {
  await _fillStep0(tester);
  await tester.tap(find.text('Volgende'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SecretStore secrets;

  setUp(() async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
    secrets = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
  });

  group('OpenKatInstallationWizard.show', () {
    testWidgets('opent dialoog en sluit met Annuleren', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => OpenKatInstallationWizard.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('OpenKAT-server toevoegen'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();

      expect(find.text('OpenKAT-server toevoegen'), findsNothing);
    });
  });

  group('stap 0 — naam en adres', () {
    testWidgets('valideert lege naam', (tester) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      expect(find.text('OpenKAT-server toevoegen'), findsOneWidget);
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(
        find.text('Vul een weergavenaam in, bijvoorbeeld Productie.'),
        findsOneWidget,
      );
    });

    testWidgets('valideert leeg adres', (tester) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Productie');
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Vul een adres in, bijvoorbeeld https://openkat.voorbeeld.nl',
        ),
        findsOneWidget,
      );
    });

    testWidgets('valideert ongeldige URL', (tester) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Productie');
      await tester.enterText(find.byType(TextField).at(1), 'geen-url');
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Dit adres is niet geldig. Controleer of u een volledige URL heeft ingevuld.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('valideert HTTP zonder Eigen netwerk', (tester) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'LAN');
      await tester.enterText(
        find.byType(TextField).at(1),
        'http://openkat.lan',
      );
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(
        find.text(
          'Het adres moet met https:// beginnen, of zet Eigen netwerk aan voor HTTP op het eigen netwerk.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('toont host-preview bij geldig adres', (tester) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).at(1),
        'https://openkat.voorbeeld.nl',
      );
      await tester.pumpAndSettle();

      expect(find.text('Verbinding met: openkat.voorbeeld.nl'), findsOneWidget);
    });

    testWidgets('Eigen netwerk schakelaar wist veldfout', (tester) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'LAN');
      await tester.enterText(
        find.byType(TextField).at(1),
        'http://openkat.lan',
      );
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();
      const errorText =
          'Het adres moet met https:// beginnen, of zet Eigen netwerk aan voor HTTP op het eigen netwerk.';
      expect(find.text(errorText), findsOneWidget);

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(find.text(errorText), findsNothing);
    });
  });

  group('stap 1 — token', () {
    testWidgets('zonder token bij nieuwe installatie', (tester) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      await _goToStep1(tester);
      expect(find.text('Toegangstoken'), findsOneWidget);

      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(
        find.text('Plak een toegangstoken om verder te gaan.'),
        findsOneWidget,
      );
    });

    testWidgets('terug naar stap 0', (tester) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      await _goToStep1(tester);
      await tester.tap(find.text('Terug'));
      await tester.pumpAndSettle();

      expect(find.text('Weergavenaam'), findsOneWidget);
      expect(find.text('Productie'), findsOneWidget);
    });
  });

  group('stap 2 — test', () {
    testWidgets('bewerken met opgeslagen token bereikt teststap', (
      tester,
    ) async {
      final existing = OpenKatInstallation.create(
        name: 'Acceptatie',
        baseUrl: 'https://ok.example',
        trustedInternal: true,
      );
      await secrets.writeOpenKatToken(existing.id, 'tok');

      await tester.pumpWidget(
        _appWithSecrets(secrets, OpenKatInstallationWizard(existing: existing)),
      );
      await _settleOpenKat(tester);
      await tester.pumpAndSettle();

      expect(find.text('OpenKAT-server bewerken'), findsOneWidget);
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      // Token leeg laten — opgeslagen token volstaat bij bewerken.
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(find.text('Verbinding testen'), findsOneWidget);
      expect(
        find.text(
          'Test de verbinding voordat u opslaat, zodat u weet dat naam, adres en token kloppen.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('bewerken zonder opgeslagen token vereist invoer', (
      tester,
    ) async {
      final existing = OpenKatInstallation.create(
        name: 'Acceptatie',
        baseUrl: 'https://ok.example',
      );

      await tester.pumpWidget(
        _appWithSecrets(secrets, OpenKatInstallationWizard(existing: existing)),
      );
      await _settleOpenKat(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(
        find.text('Plak een toegangstoken om verder te gaan.'),
        findsOneWidget,
      );
    });

    testWidgets('terug vanaf teststap wist teststatus', (tester) async {
      final existing = OpenKatInstallation.create(
        name: 'Acceptatie',
        baseUrl: 'https://ok.example',
      );
      await secrets.writeOpenKatToken(existing.id, 'tok');

      await tester.pumpWidget(
        _appWithSecrets(secrets, OpenKatInstallationWizard(existing: existing)),
      );
      await _settleOpenKat(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Terug'));
      await tester.pumpAndSettle();

      expect(find.text('Toegangstoken'), findsOneWidget);
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(find.text('Verbinding testen'), findsOneWidget);
    });

    testWidgets('nieuwe installatie start automatische test op stap 2', (
      tester,
    ) async {
      await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
      await tester.pumpAndSettle();

      await _goToStep1(tester);
      await tester.enterText(find.byType(TextField).first, 'secret');
      await tester.tap(find.text('Volgende'));
      // Geen pumpAndSettle: auto-test houdt spinner actief.
      await tester.pump();
      expect(find.text('Verbinding wordt getest…'), findsOneWidget);
    });

    testWidgets('handmatige test toont spinner', (tester) async {
      final existing = OpenKatInstallation.create(
        name: 'Acceptatie',
        baseUrl: 'https://ok.example',
      );
      await secrets.writeOpenKatToken(existing.id, 'tok');

      await tester.pumpWidget(
        _appWithSecrets(secrets, OpenKatInstallationWizard(existing: existing)),
      );
      await _settleOpenKat(tester);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Verbinding testen'));
      await tester.pump();
      expect(find.text('Verbinding wordt getest…'), findsOneWidget);
    });
  });

  group('bewerken', () {
    testWidgets('toont bestaande waarden', (tester) async {
      final existing = OpenKatInstallation.create(
        name: 'Acceptatie',
        baseUrl: 'https://ok.example',
        trustedInternal: true,
      );
      await secrets.writeOpenKatToken(existing.id, 'tok');

      await tester.pumpWidget(
        _appWithSecrets(secrets, OpenKatInstallationWizard(existing: existing)),
      );
      await _settleOpenKat(tester);
      await tester.pumpAndSettle();

      expect(find.text('OpenKAT-server bewerken'), findsOneWidget);
      expect(find.text('Acceptatie'), findsOneWidget);
      expect(find.text('Verbinding met: ok.example'), findsOneWidget);

      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();
      expect(find.text('Toegangstoken'), findsOneWidget);
    });
  });
}
