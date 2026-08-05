import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/openkat/openkat_installation.dart';
import 'package:ocideck/widgets/dialogs/settings/openkat_integration_panel.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('lege serverstaat toont toevoegen-CTA', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: OpenKatIntegrationBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Vanuit een map'), findsOneWidget);
    expect(find.text('Vanuit een OpenKAT-server'), findsOneWidget);
    expect(find.text('Nog geen OpenKAT-server aangesloten.'), findsOneWidget);
    expect(find.text('Server toevoegen…'), findsOneWidget);
  });

  testWidgets('installatiekaart toont naam en host', (tester) async {
    final installation = OpenKatInstallation.create(
      name: 'Productie',
      baseUrl: 'https://openkat.voorbeeld.nl',
    );
    SharedPreferences.setMockInitialValues({
      'openkatIntegrationEnabled': true,
      'openkatInstallations':
          '[{"id":"${installation.id}","name":"Productie","baseUrl":"https://openkat.voorbeeld.nl","trustedInternal":false,"lastStatus":"unchecked"}]',
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: OpenKatIntegrationBody()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Productie'), findsOneWidget);
    expect(find.text('openkat.voorbeeld.nl'), findsOneWidget);
    expect(find.text('Rapportage van server…'), findsOneWidget);
    expect(find.text('Server toevoegen…'), findsOneWidget);
  });
}
