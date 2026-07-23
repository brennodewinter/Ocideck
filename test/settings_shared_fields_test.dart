import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/settings/settings_section_title.dart';
import 'package:ocideck/widgets/dialogs/settings/settings_text_field.dart';

/// De drie bouwstenen die uit de gedeelde `part`-scope van het
/// instellingenvenster zijn gehaald (#631). Ze staan hier los getoetst omdat
/// dát het punt van de verhuizing is: een paneel dat ze gebruikt hoeft het
/// venster niet meer te kennen, en een test hoeft het venster niet te openen.
void main() {
  Future<void> show(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );

  group('SettingsSectionTitle', () {
    testWidgets('registers its anchor under the text it shows', (tester) async {
      final keys = <String, GlobalKey>{};
      await show(
        tester,
        SettingsSectionAnchors(
          keys: keys,
          highlighted: null,
          child: const SettingsSectionTitle('WebDAV-bron'),
        ),
      );

      // De zoekfunctie zoekt op de ongewijzigde tekst, terwijl het scherm
      // hoofdletters toont. Loopt dat uiteen, dan springt een treffer nergens
      // naartoe en merkt niemand het.
      expect(keys.keys, ['WebDAV-bron']);
      expect(keys['WebDAV-bron']!.currentContext, isNotNull);
      expect(find.text('WEBDAV-BRON'), findsOneWidget);
    });

    testWidgets('only the highlighted section gets a border', (tester) async {
      await show(
        tester,
        SettingsSectionAnchors(
          keys: {},
          highlighted: 'S3-bucket',
          child: const Column(
            children: [
              SettingsSectionTitle('S3-bucket'),
              SettingsSectionTitle('Git-repository'),
            ],
          ),
        ),
      );

      final decorated = tester
          .widgetList<AnimatedContainer>(find.byType(AnimatedContainer))
          .where((c) => c.decoration != null);
      expect(decorated, hasLength(1));
    });

    testWidgets('works outside a scope, without an anchor', (tester) async {
      // Een paneel mag ook buiten het venster te tekenen zijn — in een test of
      // een preview is er geen zoekfunctie om een anker aan te hangen.
      await show(tester, const SettingsSectionTitle('Los'));
      expect(find.text('LOS'), findsOneWidget);
    });
  });

  group('SettingsTextField', () {
    testWidgets('shows label and hint, and hides the text when asked', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'geheim');
      addTearDown(controller.dispose);
      await show(
        tester,
        SettingsTextField(
          controller,
          'Wachtwoord',
          hint: 'app-wachtwoord',
          obscure: true,
          icon: Icons.key_outlined,
        ),
      );

      expect(find.text('Wachtwoord'), findsOneWidget);
      expect(find.text('app-wachtwoord'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        true,
      );
      expect(find.byIcon(Icons.key_outlined), findsOneWidget);
    });
  });

  group('SettingsSecretField', () {
    testWidgets('is an obscured field where a keychain exists', (tester) async {
      // Onder `flutter test` is `platformCanStoreSecrets` waar (geen web), dus
      // dit is de desktopkant. De webkant — het uitgegrijsde veld met de reden
      // ernaast — vraagt kIsWeb en is hier structureel niet te bereiken; die
      // staat in settings_keychain_secret_test.dart beschreven.
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await show(tester, SettingsSecretField(controller, 'API-sleutel'));

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.obscureText, true);
      // `enabled` blijft ongezet (en dus null) wanneer het veld gewoon werkt;
      // de webkant zet hem expliciet op false.
      expect(field.enabled, isNot(false));
      expect(find.byIcon(Icons.lock_outline), findsNothing);
    });
  });
}
