import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/secret_store.dart';
import 'package:ocideck/widgets/dialogs/settings/settings_text_field.dart';

/// De invulrijen van een netwerkbron, uit de gedeelde part-scope gehaald met
/// #631. Het zwaartepunt ligt bij [SettingsSecretField], en daarbinnen bij de
/// tak die zónder sleutelhanger draait.
///
/// Die tak is de weigering: geen sleutelhanger betekent dat het veld dicht
/// hoort te zitten mét de reden erbij, in plaats van stilzwijgend iets te
/// bewaren wat elk script op de pagina kan meelezen. Hij was tot nu toe
/// onbereikbaar onder `flutter test` — `kIsWeb` is daar altijd onwaar — en dus
/// stond juist het veiligheidsgedrag als enige onbeproefd. De `canStore`-haak
/// bestaat om dat te repareren.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Future<void> toon(WidgetTester tester, Widget kind) => tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: kind)),
    ),
  );

  group('SettingsTextField', () {
    testWidgets('toont label, hint en pictogram, en tikt in de controller', (
      tester,
    ) async {
      final controller = TextEditingController();
      await toon(
        tester,
        SettingsTextField(
          controller,
          'Server-URL',
          hint: 'https://cloud.example.com',
          icon: Icons.link,
        ),
      );

      expect(find.text('Server-URL'), findsOneWidget);
      expect(find.text('https://cloud.example.com'), findsOneWidget);
      expect(find.byIcon(Icons.link), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'https://eigen.nl');
      expect(controller.text, 'https://eigen.nl');
    });

    testWidgets('zonder pictogram staat er geen prefix', (tester) async {
      await toon(tester, SettingsTextField(TextEditingController(), 'Submap'));

      final veld = tester.widget<TextField>(find.byType(TextField));
      expect(veld.decoration!.prefixIcon, isNull);
      expect(veld.obscureText, isFalse);
    });

    testWidgets('obscure verbergt wat er staat', (tester) async {
      await toon(
        tester,
        SettingsTextField(TextEditingController(), 'Token', obscure: true),
      );

      expect(
        tester.widget<TextField>(find.byType(TextField)).obscureText,
        isTrue,
      );
    });
  });

  group('SettingsSecretField', () {
    testWidgets('met sleutelhanger is het een gewoon verborgen veld', (
      tester,
    ) async {
      expect(platformCanStoreSecrets, isTrue);

      final controller = TextEditingController();
      await toon(tester, SettingsSecretField(controller, 'App-wachtwoord'));

      final veld = tester.widget<TextField>(find.byType(TextField));
      expect(veld.obscureText, isTrue);
      expect(veld.enabled, isNot(false));
      expect(find.byIcon(Icons.key_outlined), findsOneWidget);
      // Geen waarschuwing: er ís hier een sleutelhanger.
      expect(find.byIcon(Icons.lock_outline), findsNothing);

      await tester.enterText(find.byType(TextField), 'geheim');
      expect(controller.text, 'geheim');
    });

    testWidgets('een eigen pictogram wordt doorgegeven', (tester) async {
      await toon(
        tester,
        SettingsSecretField(
          TextEditingController(),
          'API-sleutel',
          icon: Icons.vpn_key_outlined,
        ),
      );

      expect(find.byIcon(Icons.vpn_key_outlined), findsOneWidget);
    });

    testWidgets('zónder sleutelhanger zit het veld dicht, mét de reden erbij', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'stond-er-al');
      await toon(
        tester,
        SettingsSecretField(controller, 'App-wachtwoord', canStore: false),
      );

      final veld = tester.widget<TextField>(find.byType(TextField));
      expect(veld.enabled, isFalse);
      expect(veld.obscureText, isTrue);

      // De reden staat erbij: dit is het verschil tussen "werkt niet" en een
      // uitleg waar de gebruiker iets mee kan.
      expect(find.byIcon(Icons.lock_outline), findsOneWidget);
      expect(
        find.text('In de browser kan dit niet worden bewaard'),
        findsOneWidget,
      );
      expect(find.textContaining('geen sleutelbos'), findsOneWidget);

      // En er komt geen geheim binnen.
      await tester.enterText(find.byType(TextField), 'geheim');
      expect(controller.text, 'stond-er-al');
    });
  });
}
