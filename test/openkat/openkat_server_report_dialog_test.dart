import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/secret_store_provider.dart';
import 'package:ocideck/widgets/dialogs/openkat_server_report_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app({
  SecretStore? secrets,
  Widget child = const OpenKatServerReportDialog(),
}) {
  return ProviderScope(
    overrides: secrets == null
        ? const []
        : [secretStoreProvider.overrideWithValue(secrets)],
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

Future<void> _waitForOpenKat(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({});
  });

  testWidgets('zonder installaties toont toevoegen-CTA', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.text('Rapportage van OpenKAT-server'), findsOneWidget);
    expect(find.text('Nog geen OpenKAT-server aangesloten.'), findsOneWidget);
    expect(find.text('Server toevoegen…'), findsOneWidget);
  });

  testWidgets('twee installaties toont radiolijst', (tester) async {
    final a = OpenKatInstallation.create(
      name: 'Prod',
      baseUrl: 'https://prod.example',
    );
    final b = OpenKatInstallation.create(
      name: 'Acc',
      baseUrl: 'https://acc.example',
    );
    SharedPreferences.setMockInitialValues({
      'openkatIntegrationEnabled': true,
      'openkatInstallations':
          '[{"id":"${a.id}","name":"Prod","baseUrl":"https://prod.example","trustedInternal":false,"lastStatus":"unchecked"},'
          '{"id":"${b.id}","name":"Acc","baseUrl":"https://acc.example","trustedInternal":false,"lastStatus":"unchecked"}]',
    });

    await tester.pumpWidget(_app());
    await _waitForOpenKat(tester);
    await tester.pumpAndSettle();

    expect(find.text('Prod'), findsOneWidget);
    expect(find.text('Acc'), findsOneWidget);
  });

  testWidgets('volgende zonder token toont fout', (tester) async {
    final installation = OpenKatInstallation.create(
      name: 'Prod',
      baseUrl: 'https://prod.example',
    );
    SharedPreferences.setMockInitialValues({
      'openkatIntegrationEnabled': true,
      'openkatInstallations':
          '[{"id":"${installation.id}","name":"Prod","baseUrl":"https://prod.example","trustedInternal":false,"lastStatus":"unchecked"}]',
    });

    await tester.pumpWidget(_app());
    await _waitForOpenKat(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(RadioListTile<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volgende'));
    await tester.pumpAndSettle();

    expect(find.textContaining('toegangstoken'), findsOneWidget);
  });

  testWidgets('volgende met token toont netwerkfout', (tester) async {
    final installation = OpenKatInstallation.create(
      name: 'Prod',
      baseUrl: 'https://prod.example',
    );
    final secrets = SecretStore(
      storage: const FlutterSecureStorage(),
      canStore: true,
    );
    await secrets.writeOpenKatToken(installation.id, 'tok');
    SharedPreferences.setMockInitialValues({
      'openkatIntegrationEnabled': true,
      'openkatInstallations':
          '[{"id":"${installation.id}","name":"Prod","baseUrl":"https://prod.example","trustedInternal":false,"lastStatus":"unchecked"}]',
    });

    await tester.pumpWidget(_app(secrets: secrets));
    await _waitForOpenKat(tester);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(RadioListTile<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volgende'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.textContaining('Organisaties'), findsOneWidget);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    expect(find.textContaining('mislukt'), findsOneWidget);
  });

  testWidgets('annuleren sluit de dialoog', (tester) async {
    await tester.pumpWidget(
      _app(
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () => OpenKatServerReportDialog.show(context),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Annuleren'), findsOneWidget);
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(find.text('Rapportage van OpenKAT-server'), findsNothing);
  });
}
