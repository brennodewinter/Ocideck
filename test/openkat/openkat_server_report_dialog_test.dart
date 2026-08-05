import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/state/openkat_provider.dart';
import 'package:ocideck/state/secret_store_provider.dart';
import 'package:ocideck/widgets/dialogs/openkat_server_report_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

Widget _app(
  Widget child, {
  SecretStore? secrets,
  List<OpenKatInstallation>? installations,
}) {
  return ProviderScope(
    overrides: [
      if (secrets != null) secretStoreProvider.overrideWithValue(secrets),
      if (installations != null)
        openKatInstallationsProvider.overrideWithValue(installations),
    ],
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

String _installationsJson(List<OpenKatInstallation> items) {
  final parts = items.map((i) {
    return '{"id":"${i.id}","name":"${i.name}","baseUrl":"${i.baseUrl}",'
        '"trustedInternal":${i.trustedInternal},"lastStatus":"unchecked"}';
  });
  return '[${parts.join(',')}]';
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

  group('OpenKatServerReportDialog.show', () {
    testWidgets('opent dialoog', (tester) async {
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => FilledButton(
              onPressed: () => OpenKatServerReportDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Rapportage van OpenKAT-server'), findsOneWidget);
      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();
    });
  });

  group('stap 0 — server kiezen', () {
    testWidgets('zonder installaties toont toevoegen-CTA', (tester) async {
      await tester.pumpWidget(_app(const OpenKatServerReportDialog()));
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
        'openkatInstallations': _installationsJson([a, b]),
      });

      await tester.pumpWidget(
        _app(
          const OpenKatServerReportDialog(),
          secrets: secrets,
          installations: [a, b],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Prod'), findsOneWidget);
      expect(find.text('Acc'), findsOneWidget);
      expect(find.text('prod.example'), findsOneWidget);
      expect(find.text('acc.example'), findsOneWidget);
    });

    testWidgets('selectie en Volgende zonder token toont fout', (tester) async {
      final a = OpenKatInstallation.create(
        name: 'Prod',
        baseUrl: 'https://prod.example',
      );
      final b = OpenKatInstallation.create(
        name: 'Acc',
        baseUrl: 'https://acc.example',
      );

      await tester.pumpWidget(
        _app(
          const OpenKatServerReportDialog(),
          secrets: secrets,
          installations: [a, b],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Prod'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(find.textContaining('geen toegangstoken'), findsOneWidget);
    });

    testWidgets('Volgende zonder selectie blijft op stap 0', (tester) async {
      final a = OpenKatInstallation.create(
        name: 'Prod',
        baseUrl: 'https://prod.example',
      );
      final b = OpenKatInstallation.create(
        name: 'Acc',
        baseUrl: 'https://acc.example',
      );

      await tester.pumpWidget(
        _app(
          const OpenKatServerReportDialog(),
          secrets: secrets,
          installations: [a, b],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(find.text('Prod'), findsOneWidget);
      expect(find.text('Acc'), findsOneWidget);
    });
  });

  group('stap 1 — organisaties', () {
    testWidgets('enkele installatie slaat serverstap over', (tester) async {
      final inst = OpenKatInstallation.create(
        name: 'Prod',
        baseUrl: 'https://prod.example',
      );

      await tester.pumpWidget(
        _app(
          const OpenKatServerReportDialog(),
          secrets: secrets,
          installations: [inst],
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('Server: Prod'), findsOneWidget);
      expect(find.text('prod.example'), findsWidgets);
      await tester.pumpAndSettle();
      expect(find.textContaining('geen toegangstoken'), findsOneWidget);
    });

    testWidgets('Annuleren bij enkele installatie sluit dialoog', (tester) async {
      final inst = OpenKatInstallation.create(
        name: 'Prod',
        baseUrl: 'https://prod.example',
      );

      await tester.pumpWidget(
        _app(
          const OpenKatServerReportDialog(),
          secrets: secrets,
          installations: [inst],
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(find.text('Annuleren'));
      await tester.pumpAndSettle();

      expect(find.text('Rapportage van OpenKAT-server'), findsNothing);
    });

    testWidgets('Terug vanaf org-stap na tokenfout', (tester) async {
      final a = OpenKatInstallation.create(
        name: 'Prod',
        baseUrl: 'https://prod.example',
      );
      final b = OpenKatInstallation.create(
        name: 'Acc',
        baseUrl: 'https://acc.example',
      );

      await tester.pumpWidget(
        _app(
          const OpenKatServerReportDialog(),
          secrets: secrets,
          installations: [a, b],
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Prod'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Volgende'));
      await tester.pumpAndSettle();

      expect(find.textContaining('geen toegangstoken'), findsOneWidget);

      await tester.tap(find.text('Terug'));
      await tester.pumpAndSettle();

      expect(find.text('Prod'), findsOneWidget);
      expect(find.text('Acc'), findsOneWidget);
    });
  });
}
