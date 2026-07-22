import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/hex_color_dialog.dart';

/// De eigen-kleurkiezer is de enige plek waar een gebruiker een kleur intikt in
/// plaats van hem aan te wijzen. Alles hangt daar aan één regel: wat telt als
/// kleur. Laat die regel iets half door, dan landt er onzin in het themaprofiel
/// en tekent elke dia daarna met een kleur die niemand koos.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('normalize', () {
    test('vult het hekje aan en maakt er hoofdletters van', () {
      expect(HexColorDialog.normalize('33ff33'), '#33FF33');
      expect(HexColorDialog.normalize('#33ff33'), '#33FF33');
      expect(HexColorDialog.normalize('  #33FF33  '), '#33FF33');
    });

    test('een halve of te lange waarde is geen kleur', () {
      expect(HexColorDialog.normalize('#33FF'), isNull);
      expect(HexColorDialog.normalize('33FF3'), isNull);
      expect(HexColorDialog.normalize('#33FF333'), isNull);
      expect(HexColorDialog.normalize(''), isNull);
      // Drieletterig hex bestaat in CSS maar niet hier: het profiel bewaart
      // altijd zes tekens, en half doorlaten geeft later een kapotte kleur.
      expect(HexColorDialog.normalize('#3F3'), isNull);
    });

    test('iets dat geen hex is wordt geweigerd', () {
      expect(HexColorDialog.normalize('groen'), isNull);
      expect(HexColorDialog.normalize('#GGGGGG'), isNull);
    });
  });

  /// Opent het venster en houdt vast wat het teruggaf.
  Future<List<String?>> open(WidgetTester tester, String initial) async {
    final gekozen = <String?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async =>
                  gekozen.add(await HexColorDialog.show(context, initial)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(HexColorDialog), findsOneWidget);
    return gekozen;
  }

  Finder toepassen() => find.widgetWithText(FilledButton, 'Toepassen');

  bool toepassenAan(WidgetTester tester) =>
      tester.widget<FilledButton>(toepassen()).onPressed != null;

  testWidgets('Toepassen blijft uit tot er een hele kleur staat', (
    tester,
  ) async {
    await open(tester, '#33FF33');
    expect(toepassenAan(tester), isTrue);

    await tester.enterText(find.byType(TextField), '#33FF');
    await tester.pumpAndSettle();
    expect(
      toepassenAan(tester),
      isFalse,
      reason: 'een halve kleur mag niet toe te passen zijn',
    );

    await tester.enterText(find.byType(TextField), '#33FF33');
    await tester.pumpAndSettle();
    expect(toepassenAan(tester), isTrue);
  });

  testWidgets('Toepassen geeft de genormaliseerde kleur terug', (tester) async {
    final gekozen = await open(tester, '#000000');
    await tester.enterText(find.byType(TextField), 'a1b2c3');
    await tester.pumpAndSettle();

    await tester.tap(toepassen());
    await tester.pumpAndSettle();

    expect(gekozen, ['#A1B2C3']);
  });

  testWidgets('Enter in het veld past een geldige kleur toe', (tester) async {
    final gekozen = await open(tester, '#000000');
    await tester.enterText(find.byType(TextField), '#ABCDEF');
    await tester.pumpAndSettle();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(gekozen, ['#ABCDEF']);
    expect(find.byType(HexColorDialog), findsNothing);
  });

  testWidgets('Enter op een halve kleur sluit het venster niet', (
    tester,
  ) async {
    final gekozen = await open(tester, '#000000');
    await tester.enterText(find.byType(TextField), '#AB');
    await tester.pumpAndSettle();

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.byType(HexColorDialog), findsOneWidget);
    expect(gekozen, isEmpty);
  });

  testWidgets('Annuleren levert niets op', (tester) async {
    final gekozen = await open(tester, '#33FF33');
    await tester.enterText(find.byType(TextField), '#ABCDEF');
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(gekozen, [null], reason: 'annuleren mag geen kleur doorgeven');
  });

  /// De kleur van het voorbeeldvlak links van het invoerveld.
  Color? preview(WidgetTester tester) {
    final container = tester.widget<Container>(
      find
          .descendant(
            of: find.byType(HexColorDialog),
            matching: find.byType(Container),
          )
          .first,
    );
    return (container.decoration! as BoxDecoration).color;
  }

  testWidgets('het voorbeeldvlak volgt wat er staat', (tester) async {
    await open(tester, '#33FF33');
    expect(preview(tester), const Color(0xFF33FF33));

    await tester.enterText(find.byType(TextField), '#0000FF');
    await tester.pumpAndSettle();
    expect(preview(tester), const Color(0xFF0000FF));

    // Onaf getikt: wit, niet de vorige kleur — anders suggereert het vlak dat
    // er een kleur klaarstaat terwijl Toepassen uit staat.
    await tester.enterText(find.byType(TextField), '#00');
    await tester.pumpAndSettle();
    expect(preview(tester), const Color(0xFFFFFFFF));
  });

  testWidgets('het veld weigert tekens die geen hex zijn', (tester) async {
    await open(tester, '');
    final veld = find.byType(TextField);

    await tester.enterText(veld, 'zz#12qq34gg56');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(veld).controller!.text, '#123456');

    // En het stopt bij zeven tekens: '#' plus zes.
    await tester.enterText(veld, '#1234567890');
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(veld).controller!.text, '#123456');
  });
}
