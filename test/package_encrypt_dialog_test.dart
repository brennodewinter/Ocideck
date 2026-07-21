import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/utils/password_generator.dart';
import 'package:ocideck/utils/password_strength.dart';
import 'package:ocideck/widgets/dialogs/package_encrypt_dialog.dart';

/// De keuze die vóór een pakket-export gemaakt wordt: versleutelen of niet, en
/// zo ja waarmee. Wat de dialoog teruggeeft bepaalt of het `.ocideck` met
/// AES-256 dichtgaat, dus de belofte in [PackageEncryptChoice] — "password is
/// niet-null en niet-leeg als encrypt waar is" — moet hier hard staan.
///
/// De wachtwoorden in deze test zijn wegwerpwaarden; er is geen echte
/// inloggegeven mee gemoeid.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  Finder exportButton() =>
      find.widgetWithText(ElevatedButton, 'Exporteren').first;

  // Opent de dialoog vanaf een knop en houdt de uitkomst vast, zodat een test
  // kan toetsen wát er teruggegeven wordt en niet alleen dát er iets sluit.
  Future<PackageEncryptChoice?> openAndChoose(
    WidgetTester tester, {
    required Future<void> Function(WidgetTester) interact,
  }) async {
    PackageEncryptChoice? result;
    var done = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                result = await PackageEncryptDialog.show(context);
                done = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await interact(tester);
    await tester.pumpAndSettle();
    expect(done, isTrue, reason: 'de dialoog hoorde te sluiten');
    return result;
  }

  Future<void> enableEncryption(WidgetTester tester) async {
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
  }

  testWidgets('versleutelen staat uit, en dan is er niets in te vullen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackageEncryptDialog())),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
    expect(find.byType(TextField), findsNothing);
    // Zonder versleuteling is er geen wachtwoord nodig, dus exporteren mag.
    expect(tester.widget<ElevatedButton>(exportButton()).onPressed, isNotNull);
  });

  testWidgets('zonder versleuteling komt er geen wachtwoord mee terug', (
    tester,
  ) async {
    final choice = await openAndChoose(
      tester,
      interact: (tester) async => tester.tap(exportButton()),
    );

    expect(choice, isNotNull);
    expect(choice!.encrypt, isFalse);
    expect(choice.password, isNull);
  });

  testWidgets('met versleuteling blokkeert een leeg wachtwoord de export', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackageEncryptDialog())),
    );
    await tester.pumpAndSettle();
    await enableEncryption(tester);

    expect(find.byType(TextField), findsOneWidget);
    // Een leeg wachtwoord zou een pakket opleveren dat niemand kan openen.
    expect(tester.widget<ElevatedButton>(exportButton()).onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'wegwerp-zin-1');
    await tester.pumpAndSettle();
    expect(tester.widget<ElevatedButton>(exportButton()).onPressed, isNotNull);
  });

  testWidgets('het getypte wachtwoord komt terug bij de aanroeper', (
    tester,
  ) async {
    final choice = await openAndChoose(
      tester,
      interact: (tester) async {
        await enableEncryption(tester);
        await tester.enterText(find.byType(TextField), 'wegwerp-zin-2');
        await tester.pumpAndSettle();
        await tester.tap(exportButton());
      },
    );

    expect(choice!.encrypt, isTrue);
    expect(choice.password, 'wegwerp-zin-2');
  });

  testWidgets('enter in het wachtwoordveld exporteert net zo goed', (
    tester,
  ) async {
    final choice = await openAndChoose(
      tester,
      interact: (tester) async {
        await enableEncryption(tester);
        await tester.enterText(find.byType(TextField), 'wegwerp-zin-3');
        await tester.pumpAndSettle();
        await tester.testTextInput.receiveAction(TextInputAction.done);
      },
    );

    expect(choice!.password, 'wegwerp-zin-3');
  });

  testWidgets('annuleren geeft niets terug, ook niet stiekem een keuze', (
    tester,
  ) async {
    final choice = await openAndChoose(
      tester,
      interact: (tester) async {
        await enableEncryption(tester);
        await tester.enterText(find.byType(TextField), 'wegwerp-zin-4');
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      },
    );

    expect(choice, isNull);
  });

  testWidgets('escape annuleert ook, ondanks de niet-wegklikbare barrière', (
    tester,
  ) async {
    final choice = await openAndChoose(
      tester,
      interact: (tester) async {
        // Met versleuteling aan staat de focus in het wachtwoordveld, binnen de
        // CallbackShortcuts van de dialoog.
        await enableEncryption(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      },
    );

    expect(choice, isNull);
  });

  testWidgets('de generator levert de gekozen lengte en toont hem meteen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackageEncryptDialog())),
    );
    await tester.pumpAndSettle();
    await enableEncryption(tester);

    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().obscureText, isTrue);

    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Genereer sterk wachtwoord'),
    );
    await tester.pumpAndSettle();

    expect(field().controller!.text.length, shortPasswordLength);
    // Net gegenereerd: verborgen houden zou het onmogelijk maken om het over
    // te nemen en door te geven.
    expect(field().obscureText, isFalse);

    // De lange stand levert de andere gedocumenteerde lengte.
    await tester.tap(find.text('256'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(OutlinedButton, 'Genereer sterk wachtwoord'),
    );
    await tester.pumpAndSettle();
    expect(field().controller!.text.length, longPasswordLength);
  });

  testWidgets('kopiëren kan pas als er iets te kopiëren is', (tester) async {
    final copied = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied.add((call.arguments as Map)['text'] as String);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackageEncryptDialog())),
    );
    await tester.pumpAndSettle();
    await enableEncryption(tester);

    IconButton copyButton() => tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.copy),
        matching: find.byType(IconButton),
      ),
    );
    expect(copyButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'wegwerp-zin-5');
    await tester.pumpAndSettle();
    expect(copyButton().onPressed, isNotNull);

    await tester.tap(find.byIcon(Icons.copy));
    await tester.pumpAndSettle();

    expect(copied, ['wegwerp-zin-5']);
    expect(find.text('Wachtwoord gekopieerd naar klembord.'), findsOneWidget);
  });

  testWidgets('de sterktemeter volgt de schatting, niet de lengte alleen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackageEncryptDialog())),
    );
    await tester.pumpAndSettle();
    await enableEncryption(tester);

    // Leeg: geen balk, wel de tip die uitlegt wat wél helpt.
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.text(
        'Tip: een lange wachtwoordzin is veiliger dan een kort wachtwoord met symbolen.',
      ),
      findsOneWidget,
    );

    const labels = {
      PasswordStrength.veryWeak: 'Zeer zwak',
      PasswordStrength.weak: 'Zwak',
      PasswordStrength.fair: 'Redelijk',
      PasswordStrength.strong: 'Sterk',
      PasswordStrength.veryStrong: 'Zeer sterk',
    };
    // Elke categorie krijgt zijn eigen woord; het label moet de schatting van
    // password_strength.dart volgen en niet een eigen regeltje in de dialoog.
    for (final password in const [
      'aaa',
      'aaaaaaaa',
      'Wachtwoord12',
      'Wachtwoord12!xY',
      'een-hele-lange-wachtwoordzin-met-veel-entropie-erin-1234',
    ]) {
      await tester.enterText(find.byType(TextField), password);
      await tester.pumpAndSettle();

      final result = estimatePasswordStrength(password);
      expect(
        find.text(labels[result.category]!),
        findsOneWidget,
        reason: '"$password" hoort ${labels[result.category]} te heten',
      );
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        result.fraction,
      );
      // De aansporing hoort alleen bij een zwakke keuze; anders is het ruis.
      expect(
        find.text('Maak het langer voor betere bescherming.'),
        result.isWeak ? findsOneWidget : findsNothing,
        reason: '"$password" (${result.category.name})',
      );
    }
  });

  testWidgets('de waarschuwing over een kwijt wachtwoord staat er alleen als '
      'er iets te verliezen is', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackageEncryptDialog())),
    );
    await tester.pumpAndSettle();

    const warning =
        'Bewaar dit wachtwoord goed: raak je het kwijt, dan is dit pakket niet '
        'meer te openen.';
    expect(find.text(warning), findsNothing);

    await enableEncryption(tester);
    expect(find.text(warning), findsOneWidget);
  });

  testWidgets('het wachtwoord kan getoond en weer verborgen worden', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: PackageEncryptDialog())),
    );
    await tester.pumpAndSettle();
    await enableEncryption(tester);

    TextField field() => tester.widget<TextField>(find.byType(TextField));
    expect(field().obscureText, isTrue);

    await tester.tap(find.byTooltip('Wachtwoord tonen'));
    await tester.pumpAndSettle();
    expect(field().obscureText, isFalse);

    await tester.tap(find.byTooltip('Wachtwoord verbergen'));
    await tester.pumpAndSettle();
    expect(field().obscureText, isTrue);
  });
}
