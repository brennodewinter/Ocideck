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

Future<void> _goToStep1(WidgetTester tester) async {
  await tester.enterText(find.byType(TextField).first, 'Productie');
  await tester.enterText(find.byType(TextField).at(1), 'https://openkat.example');
  await tester.tap(find.text('Volgende'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('stap 0 valideert lege naam', (tester) async {
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

  testWidgets('stap 0 valideert ongeldige URL', (tester) async {
    await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Prod');
    await tester.enterText(find.byType(TextField).at(1), 'niet-een-url');
    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();

    expect(find.textContaining('https://'), findsOneWidget);
  });

  testWidgets('stap 1 vereist token bij nieuwe installatie', (tester) async {
    await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
    await tester.pumpAndSettle();
    await _goToStep1(tester);

    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();

    expect(
      find.text('Plak een toegangstoken om verder te gaan.'),
      findsOneWidget,
    );
  });

  testWidgets('terug van stap 1 naar stap 0', (tester) async {
    await tester.pumpWidget(_app(const OpenKatInstallationWizard()));
    await tester.pumpAndSettle();
    await _goToStep1(tester);

    await tester.tap(find.text('Terug'));
    await tester.pumpAndSettle();
    expect(find.text('Weergavenaam'), findsOneWidget);
  });

  testWidgets('bewerken doorloopt stappen zonder auto-test', (tester) async {
    final existing = OpenKatInstallation.create(
      name: 'Acceptatie',
      baseUrl: 'https://ok.example',
      trustedInternal: true,
    );
    final secrets = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
    await secrets.writeOpenKatToken(existing.id, 'tok');

    await tester.pumpWidget(
      _appWithSecrets(secrets, OpenKatInstallationWizard(existing: existing)),
    );
    await tester.pumpAndSettle();

    expect(find.text('OpenKAT-server bewerken'), findsOneWidget);
    expect(find.text('Verbinding met: ok.example'), findsOneWidget);

    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();
    expect(find.text('Laat leeg om het opgeslagen token te behouden'), findsOneWidget);

    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();

    expect(find.text('Verbinding testen'), findsOneWidget);
    expect(find.text('Terug'), findsOneWidget);
  });

  testWidgets('bewerken zonder opgeslagen token blokkeert stap 2', (tester) async {
    final existing = OpenKatInstallation.create(
      name: 'Leeg',
      baseUrl: 'https://leeg.example',
    );

    await tester.pumpWidget(
      _app(OpenKatInstallationWizard(existing: existing)),
    );
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
}
