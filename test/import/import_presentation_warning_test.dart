import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/dialogs/import_presentation_warning_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// De waarschuwing vóór een presentatie-import (#772).
///
/// Wat hier bewaakt wordt is een belofte, geen opmaak: de gebruiker hoort
/// *vooraf* te weten dat de conversie best-effort is. Dus moet de waarschuwing
/// er standaard zijn, moet Annuleren de import écht tegenhouden, en mag "niet
/// meer tonen" alleen blijven hangen als de gebruiker daarna doorgaat — anders
/// zou een afgebroken poging het scherm voorgoed wegnemen.
void main() {
  const dismissedKey = 'presentationImportWarningDismissed';

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({});
  });

  /// Pompt een scherm met één knop die de waarschuwing opent; de uitkomst
  /// wordt in [uitkomst] bewaard zodra de dialoog sluit.
  Future<List<bool>> pump(WidgetTester tester) async {
    final uitkomst = <bool>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  uitkomst.add(await showPresentationImportWarning(context)),
              child: const Text('start'),
            ),
          ),
        ),
      ),
    );
    return uitkomst;
  }

  testWidgets('de waarschuwing noemt best-effort en de aparte map', (
    tester,
  ) async {
    final uitkomst = await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.text('Presentatie importeren'), findsOneWidget);
    expect(find.textContaining('best-effort'), findsOneWidget);
    expect(find.textContaining('aparte map'), findsOneWidget);
    expect(uitkomst, isEmpty, reason: 'de dialoog staat nog open');
  });

  testWidgets('Annuleren houdt de import tegen', (tester) async {
    final uitkomst = await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(uitkomst, [false]);
    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getBool(dismissedKey),
      isNull,
      reason: 'annuleren mag nooit iets onthouden',
    );
  });

  testWidgets('Importeren laat de import door en onthoudt niets', (
    tester,
  ) async {
    final uitkomst = await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importeren'));
    await tester.pumpAndSettle();

    expect(uitkomst, [true]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(dismissedKey), isNull);
  });

  testWidgets('"Niet meer tonen" + Importeren slaat de volgende keer over', (
    tester,
  ) async {
    final uitkomst = await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Niet meer tonen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importeren'));
    await tester.pumpAndSettle();

    expect(uitkomst, [true]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(dismissedKey), isTrue);

    // Tweede ronde: geen dialoog meer, maar wel doorgaan.
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Presentatie importeren'), findsNothing);
    expect(uitkomst, [true, true]);
  });

  testWidgets('"Niet meer tonen" + Annuleren onthoudt niets', (tester) async {
    // Het vinkje is geen losse instelling: wie afhaakt heeft niets bevestigd,
    // en de waarschuwing hoort de volgende keer gewoon terug te komen.
    final uitkomst = await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Niet meer tonen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    expect(uitkomst, [false]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(dismissedKey), isNull);

    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();
    expect(find.text('Presentatie importeren'), findsOneWidget);
  });

  testWidgets('een eerder weggeklikte waarschuwing komt niet terug', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({dismissedKey: true});
    final uitkomst = await pump(tester);
    await tester.tap(find.text('start'));
    await tester.pumpAndSettle();

    expect(find.text('Presentatie importeren'), findsNothing);
    expect(uitkomst, [true]);
  });
}
