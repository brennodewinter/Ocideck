import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/searchable_language_picker.dart';

/// De doorzoekbare taalkiezer is een compact veld dat een zoekdialoog opent.
///
/// Wat hem bruikbaar maakt, is dat je een taal zowel op naam ("Nederlands") als
/// op code ("gsw") kunt vinden, ook als de naam diacrieten of een ander schrift
/// draagt ("Čeština" via "cestina"). Filtert hij níét, dan scrol je door 32
/// talen; treft een zoekterm niets, dan moet dat blijken uit een lege-staat en
/// niet uit een stille lege lijst. En de keuze zelf moet de code teruggeven —
/// kiest iemand Frans en komt er "fr" uit, dan klopt de interface.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  /// Bouwt de kiezer met [code] als huidige taal en onthoudt elke selectie.
  Future<List<String>> pumpPicker(
    WidgetTester tester, {
    required String code,
  }) async {
    final picked = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SearchableLanguagePicker(
              languageCode: code,
              labelText: 'Taal',
              onLanguageChanged: picked.add,
            ),
          ),
        ),
      ),
    );
    return picked;
  }

  Finder searchField() => find.byType(TextField);

  testWidgets('het veld toont de naam van de huidige taal', (tester) async {
    await pumpPicker(tester, code: 'fr');
    expect(find.text('Français'), findsOneWidget);
    // De dialoog is nog dicht: geen zoekveld in beeld.
    expect(searchField(), findsNothing);
  });

  testWidgets('een onbekende code valt terug op de code zelf', (tester) async {
    await pumpPicker(tester, code: 'xx');
    expect(find.text('xx'), findsOneWidget);
  });

  testWidgets('tikken op het veld opent de zoekdialoog', (tester) async {
    await pumpPicker(tester, code: 'en');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    expect(searchField(), findsOneWidget);
    expect(find.text('Zoek op taal of code'), findsOneWidget);
    // Bij een lege zoekterm draagt de lijst meer talen dan een gefilterde
    // treffer: er staan meerdere rijen (de builder bouwt de zichtbare kop).
    expect(find.byType(ListTile), findsWidgets);
    expect(
      tester.widgetList(find.byType(ListTile)).length,
      greaterThan(1),
    );
    expect(find.text('Geen talen gevonden'), findsNothing);
  });

  testWidgets('typen filtert op weergavenaam', (tester) async {
    await pumpPicker(tester, code: 'en');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await tester.enterText(searchField(), 'neder');
    await tester.pump();

    expect(find.text('Nederlands'), findsOneWidget);
    expect(find.text('Français'), findsNothing);
    expect(find.text('Deutsch'), findsNothing);
  });

  testWidgets('typen filtert op taalcode, ook als de naam die niet bevat', (
    tester,
  ) async {
    await pumpPicker(tester, code: 'en');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    // "gsw" komt niet voor in "Schwiizerdütsch"; alleen de code matcht.
    await tester.enterText(searchField(), 'gsw');
    await tester.pump();

    expect(find.text('Schwiizerdütsch'), findsOneWidget);
    expect(find.text('Nederlands'), findsNothing);
  });

  testWidgets('typen vindt een taal via de diacriet-gevouwen sorteersleutel', (
    tester,
  ) async {
    await pumpPicker(tester, code: 'en');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    // "Čeština" bevat geen kale "cestina"; de sortKey-tak moet dit vinden.
    await tester.enterText(searchField(), 'cestina');
    await tester.pump();

    expect(find.text('Čeština'), findsOneWidget);
    expect(find.text('Nederlands'), findsNothing);
  });

  testWidgets('een zoekterm zonder treffer toont de lege-staat', (
    tester,
  ) async {
    await pumpPicker(tester, code: 'en');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await tester.enterText(searchField(), 'zqxwv');
    await tester.pump();

    expect(find.text('Geen talen gevonden'), findsOneWidget);
    expect(find.byType(ListTile), findsNothing);
  });

  testWidgets('het wisknopje herstelt de volledige lijst', (tester) async {
    await pumpPicker(tester, code: 'en');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await tester.enterText(searchField(), 'neder');
    await tester.pump();
    expect(find.text('Nederlands'), findsOneWidget);
    expect(tester.widgetList(find.byType(ListTile)).length, 1);

    await tester.tap(find.byIcon(Icons.clear));
    await tester.pump();

    // De volledige lijst is terug: meer dan de ene treffer van zo-even, en
    // het zoekveld is leeggemaakt (de wisknop is weer verdwenen).
    expect(tester.widgetList(find.byType(ListTile)).length, greaterThan(1));
    expect(find.byIcon(Icons.clear), findsNothing);
  });

  testWidgets('een taal kiezen sluit de dialoog en meldt de juiste code', (
    tester,
  ) async {
    final picked = await pumpPicker(tester, code: 'en');
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();

    await tester.enterText(searchField(), 'neder');
    await tester.pump();
    await tester.tap(find.text('Nederlands'));
    await tester.pumpAndSettle();

    // Dialoog dicht: geen zoekveld meer, callback met de code van de keuze.
    expect(searchField(), findsNothing);
    expect(picked, ['nl']);
  });
}
