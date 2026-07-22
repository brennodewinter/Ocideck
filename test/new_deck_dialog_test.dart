import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/widgets/dialogs/new_deck_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pompt een minimale app met een "open"-knop en opent de dialoog. De
/// uiteindelijke uitkomst landt in [_Harness.choice] zodra de dialoog sluit.
class _Harness {
  _Harness({this.reveal = false});

  /// Whether the Informatieveiligheid module is revealed (gates MIAUW-only
  /// templates). Off by default, matching a fresh install.
  final bool reveal;
  NewDeckChoice? choice;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [infoSafetyRevealProvider.overrideWithValue(reveal)],
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async =>
                    choice = await NewDeckDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'open'));
    await tester.pumpAndSettle();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('titel + standaardprofiel bij aanmaken', (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.enterText(find.byType(TextFormField), 'Mijn briefing');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(harness.choice, isNotNull);
    expect(harness.choice!.title, 'Mijn briefing');
    // Standaard = het globaal geselecteerde profiel (LibreKAT op een verse
    // installatie).
    expect(harness.choice!.profileName, 'LibreKAT');
  });

  testWidgets('stijlprofiel is in de dialoog te kiezen', (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'Titel');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Standaard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(harness.choice!.profileName, 'Standaard');
  });

  testWidgets('shows the template picker with title field', (tester) async {
    await _Harness().open(tester);
    expect(find.text('Sjabloon'), findsOneWidget);
    // "Leeg deck" staat vastgepind bovenaan, dus altijd in de eerste viewport.
    expect(find.text('Leeg deck'), findsOneWidget);
    // Een niet-bovenaan sjabloon is via scrollen bereikbaar.
    await tester.scrollUntilVisible(
      find.text('Korte briefing'),
      60,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 200,
    );
    expect(find.text('Korte briefing'), findsOneWidget);
    expect(find.byType(TextFormField), findsOneWidget);
  });

  testWidgets('an empty title blocks creation', (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();
    expect(find.text('Vul een titel in'), findsOneWidget);
    expect(find.text('Sjabloon'), findsOneWidget); // dialog still open
    expect(harness.choice, isNull);
  });

  testWidgets('returns the title and the tapped template', (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.enterText(find.byType(TextFormField), '  Kick-off Q3  ');
    await tester.scrollUntilVisible(
      find.text('Projectstart / kick-off'),
      60,
      scrollable: find.byType(Scrollable).last,
      maxScrolls: 200,
    );
    // Volledig in beeld brengen: scrollUntilVisible kan de tegel aan de rand
    // laten staan, waar een tap net naast zou vallen.
    await tester.ensureVisible(find.text('Projectstart / kick-off'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Projectstart / kick-off'));
    await tester.pump();
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();

    expect(harness.choice, isNotNull);
    expect(harness.choice!.title, 'Kick-off Q3');
    expect(harness.choice!.template.id, 'kickoff');
  });

  testWidgets('defaults to the empty deck template', (tester) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.enterText(find.byType(TextFormField), 'Mijn deck');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();

    expect(harness.choice!.template.id, deckTemplates.first.id);
  });

  testWidgets('every template is reachable in the scrollable list', (
    tester,
  ) async {
    await _Harness().open(tester);
    // In weergavevolgorde itereren zodat het scrollen monotoon omlaag gaat —
    // scrollUntilVisible scrolt maar één richting op. Module-only sjablonen
    // (MIAUW) blijven verborgen tot Informatieveiligheid aanstaat en horen dus
    // niet in deze standaardcatalogus.
    for (final template in sortTemplatesForDisplay(
      deckTemplates.where((t) => !t.requiresInfoSafety),
      (t) => t.title,
    )) {
      await tester.scrollUntilVisible(
        find.text(template.title),
        60,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(template.title), findsOneWidget);
    }
  });

  testWidgets('a module-only template is hidden while the module is off', (
    tester,
  ) async {
    final miauw = deckTemplates.firstWhere((t) => t.id == 'miauwReport');

    // Module off (the default) → the MIAUW template is not in the picker.
    await _Harness().open(tester);
    expect(find.text(miauw.title), findsNothing);
  });

  testWidgets('a module-only template appears once the module is revealed', (
    tester,
  ) async {
    final miauw = deckTemplates.firstWhere((t) => t.id == 'miauwReport');

    // Reveal the Informatieveiligheid module → it appears.
    await _Harness(reveal: true).open(tester);
    await tester.scrollUntilVisible(
      find.text(miauw.title),
      60,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text(miauw.title), findsOneWidget);
  });

  testWidgets('every template has a picker icon', (tester) async {
    for (final template in deckTemplates) {
      expect(
        templatePickerIcons.containsKey(template.icon),
        isTrue,
        reason: '${template.id} mist een icoon in templatePickerIcons',
      );
    }
  });

  test('sortTemplatesForDisplay pins the empty deck, then sorts by title', () {
    final sorted = sortTemplatesForDisplay(deckTemplates, (t) => t.title);
    // Volledige catalogus, niets verloren of gedupliceerd.
    expect(
      sorted.map((t) => t.id).toSet(),
      deckTemplates.map((t) => t.id).toSet(),
    );
    expect(sorted, hasLength(deckTemplates.length));
    // "Leeg deck" bovenaan als startpunt-vanaf-nul.
    expect(sorted.first.id, 'empty');
    // De rest alfabetisch op de gevouwen titelsleutel (diacriet-ongevoelig).
    final restTitles = sorted.skip(1).map((t) => t.title).toList();
    final expected = [...restTitles]
      ..sort(
        (a, b) =>
            AppLocalizations.sortKey(a).compareTo(AppLocalizations.sortKey(b)),
      );
    expect(restTitles, expected);
  });

  final searchField = find.byKey(const ValueKey('templateSearchField'));

  testWidgets('searching narrows the list to matching templates', (
    tester,
  ) async {
    await _Harness().open(tester);
    await tester.enterText(searchField, 'quiz');
    await tester.pumpAndSettle();
    expect(find.text('Interactieve quiz'), findsOneWidget);
    expect(find.text('Leeg deck'), findsNothing);
  });

  testWidgets('search matches descriptions too', (tester) async {
    await _Harness().open(tester);
    await tester.enterText(searchField, 'kernboodschap');
    await tester.pumpAndSettle();
    expect(find.text('Voorbespreking communicatie'), findsOneWidget);
    expect(find.text('Rapportage'), findsNothing);
  });

  testWidgets('a search without matches explains itself', (tester) async {
    await _Harness().open(tester);
    await tester.enterText(searchField, 'xyzzy-bestaat-niet');
    await tester.pumpAndSettle();
    expect(find.text('Geen sjablonen gevonden'), findsOneWidget);
  });

  testWidgets('selection follows the filter and lands in the result', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.enterText(searchField, 'BOB');
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'Crisis 12:00');
    await tester.tap(find.text('Aanmaken'));
    await tester.pumpAndSettle();

    expect(harness.choice, isNotNull);
    expect(harness.choice!.template.id, 'bobCrisis');
    expect(harness.choice!.title, 'Crisis 12:00');
  });

  group('taal van de sjablooninhoud', () {
    // Titel en omschrijving lopen door l10n.d(), de dia-inhoud niet: die is
    // deck-inhoud en blijft Nederlands (zie _templateLanguageNotice). Dat mag,
    // maar dan moet de kiezer het zeggen in plaats van het te laten ontdekken.
    tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

    testWidgets('wordt gemeld zodra de interface niet Nederlands is', (
      tester,
    ) async {
      AppLocalizations.setActiveLanguageCode('tr');
      final harness = _Harness();
      await harness.open(tester);
      expect(
        find.textContaining(
          AppLocalizations(
            const Locale('tr'),
          ).d("De voorbeelddia's van een sjabloon staan in het Nederlands."),
        ),
        findsOneWidget,
      );
    });

    testWidgets('zwijgt in het Nederlands', (tester) async {
      // Een melding die niets toevoegt leert mensen meldingen overslaan.
      AppLocalizations.setActiveLanguageCode('nl');
      final harness = _Harness();
      await harness.open(tester);
      expect(
        find.textContaining("De voorbeelddia's van een sjabloon"),
        findsNothing,
      );
    });
  });
}
