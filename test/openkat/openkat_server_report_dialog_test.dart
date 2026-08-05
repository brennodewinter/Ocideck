import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/widgets/dialogs/openkat_server_report_dialog.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

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
      'openkatInstallations':
          '[{"id":"${a.id}","name":"Prod","baseUrl":"https://prod.example","trustedInternal":false,"lastStatus":"unchecked"},'
          '{"id":"${b.id}","name":"Acc","baseUrl":"https://acc.example","trustedInternal":false,"lastStatus":"unchecked"}]',
    });

    await tester.pumpWidget(_app(const OpenKatServerReportDialog()));
    await tester.pumpAndSettle();

    expect(find.text('Prod'), findsOneWidget);
    expect(find.text('Acc'), findsOneWidget);
  });
}
