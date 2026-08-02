import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck_template.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/state/procesverbetering_provider.dart';
import 'package:ocideck/widgets/dialogs/new_deck_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pompt een minimale app met een "open"-knop en opent de dialoog. De
/// uiteindelijke uitkomst landt in [_Harness.choice] zodra de dialoog sluit.
class _Harness {
  _Harness({
    this.reveal = false,
    this.revealProcesverbetering = false,
    this.languageCode,
    this.brightness = Brightness.light,
    this.textScaler = TextScaler.noScaling,
  });

  /// Whether the Informatieveiligheid module is revealed (gates MIAUW-only
  /// templates). Off by default, matching a fresh install.
  final bool reveal;
  final bool revealProcesverbetering;
  final String? languageCode;
  final Brightness brightness;
  final TextScaler textScaler;
  NewDeckChoice? choice;

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          infoSafetyRevealProvider.overrideWithValue(reveal),
          procesverbeteringRevealProvider.overrideWithValue(
            revealProcesverbetering,
          ),
        ],
        child: MaterialApp(
          locale: languageCode == null ? null : Locale(languageCode!),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
          theme: ThemeData.light(),
          darkTheme: ThemeData.dark(),
          themeMode: brightness == Brightness.dark
              ? ThemeMode.dark
              : ThemeMode.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: textScaler),
            child: child!,
          ),
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

/// Brengt een tegel in de geneste sjabloonlijst in beeld.
///
/// De dialoog scrolt als geheel op een klein venster en de catalogus heeft een
/// eigen scrollpositie. `scrollUntilVisible` kiest dan niet betrouwbaar de
/// binnenste positie en kan op de vaste dialoogknoppen terechtkomen. Deze helper
/// verplaatst eerst de buitenste viewport en loopt daarna uitsluitend door de
/// catalogus, waarna de echte tegel nog steeds gewoon wordt aangetikt.
Future<void> _revealTemplate(WidgetTester tester, Finder target) async {
  final outerScrollable = find
      .descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byType(Scrollable),
      )
      .first;
  final outerPosition = tester.state<ScrollableState>(outerScrollable).position;
  if (outerPosition.hasContentDimensions &&
      outerPosition.pixels < outerPosition.maxScrollExtent) {
    outerPosition.jumpTo(outerPosition.maxScrollExtent);
    await tester.pump();
  }

  final templateScrollable = find
      .descendant(of: find.byType(ListView), matching: find.byType(Scrollable))
      .first;
  final templatePosition = tester
      .state<ScrollableState>(templateScrollable)
      .position;

  for (var attempt = 0; attempt < 200; attempt++) {
    if (target.evaluate().isNotEmpty) {
      await tester.ensureVisible(target);
      await tester.pump();
      return;
    }
    if (!templatePosition.hasContentDimensions ||
        templatePosition.pixels >= templatePosition.maxScrollExtent) {
      break;
    }
    templatePosition.jumpTo(
      (templatePosition.pixels + 60).clamp(
        templatePosition.minScrollExtent,
        templatePosition.maxScrollExtent,
      ),
    );
    await tester.pump();
  }

  fail(
    'Kon sjabloontegel ${target.describeMatch(Plurality.many)} niet bereiken',
  );
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const processTemplateIds = [
    'procesverbetering-dmaic',
    'procesverbetering-dmadv',
    'procesverbetering-kaizen',
    'procesverbetering-a3',
    'procesverbetering-8d',
    'procesverbetering-sipoc',
  ];

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
    await _revealTemplate(tester, find.text('Korte briefing'));
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
    await _revealTemplate(tester, find.text('Projectstart / kick-off'));
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
    // (MIAUW, DMAIC) blijven verborgen tot hun module aanstaat en horen dus
    // niet in deze standaardcatalogus.
    for (final template in sortTemplatesForDisplay(
      deckTemplates.where(
        (t) => !t.requiresInfoSafety && !t.requiresProcesverbetering,
      ),
      (t) => t.title,
    )) {
      await _revealTemplate(tester, find.text(template.title));
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
    // Deze test scrolt in één keer van bovenaan door naar één ver sjabloon
    // (MIAUW, sorteert onder de M). Met de bredere catalogus staat het dieper,
    // dus een royaal scrollbudget zoals de rest van dit bestand (maxScrolls:
    // 200); de standaard 50 reikt niet meer tot onderaan.
    await _revealTemplate(tester, find.text(miauw.title));
    expect(find.text(miauw.title), findsOneWidget);
    expect(
      find.byKey(const ValueKey('templateModuleBadge-miauwReport')),
      findsOneWidget,
    );
    expect(find.text('Informatieveiligheid'), findsWidgets);
  });

  testWidgets('all process templates appear with badges only after reveal', (
    tester,
  ) async {
    final processTemplates = processTemplateIds
        .map((id) => deckTemplates.firstWhere((template) => template.id == id))
        .toList();

    await _Harness().open(tester);
    for (final template in processTemplates) {
      expect(find.text(template.title), findsNothing, reason: template.id);
      expect(
        find.byKey(ValueKey('templateModuleBadge-${template.id}')),
        findsNothing,
        reason: template.id,
      );
    }
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();

    await _Harness(revealProcesverbetering: true).open(tester);
    for (final template in sortTemplatesForDisplay(
      processTemplates,
      (template) => template.title,
    )) {
      await _revealTemplate(tester, find.text(template.title));
      expect(find.text(template.title), findsOneWidget, reason: template.id);
      expect(
        find.byKey(ValueKey('templateModuleBadge-${template.id}')),
        findsOneWidget,
        reason: template.id,
      );
    }
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

  testWidgets('picker stays operable in German at 200% in light and dark', (
    tester,
  ) async {
    for (final brightness in Brightness.values) {
      final harness = _Harness(
        revealProcesverbetering: true,
        languageCode: 'de',
        brightness: brightness,
        textScaler: TextScaler.linear(2),
      );
      await harness.open(tester);
      await tester.enterText(find.byType(TextFormField).first, 'SIPOC intake');
      await tester.enterText(
        find.byKey(const ValueKey('templateSearchField')),
        'SIPOC',
      );
      await tester.pumpAndSettle();

      await _revealTemplate(
        tester,
        find.byKey(
          const ValueKey('templateModuleBadge-procesverbetering-sipoc'),
        ),
      );
      expect(
        find.byKey(
          const ValueKey('templateModuleBadge-procesverbetering-sipoc'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull, reason: brightness.name);
      await tester.tap(find.byType(TextButton).last);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: brightness.name);
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

  testWidgets('a search without matches cannot create the old selection', (
    tester,
  ) async {
    final harness = _Harness();
    await harness.open(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      'Mag niet als leeg deck ontstaan',
    );
    await tester.enterText(searchField, 'xyzzy-bestaat-niet');
    await tester.pumpAndSettle();

    final create = tester.widget<ElevatedButton>(
      find.widgetWithText(ElevatedButton, 'Aanmaken'),
    );
    expect(create.onPressed, isNull);
    expect(harness.choice, isNull);
    expect(find.text('Nieuwe presentatie'), findsOneWidget);
  });

  testWidgets('searching the security badge finds a security template', (
    tester,
  ) async {
    await _Harness(reveal: true).open(tester);
    await tester.enterText(searchField, 'Informatieveiligheid');
    await tester.pumpAndSettle();

    // De MIAUW-titel en -omschrijving bevatten de zoekterm niet. Alleen de
    // modulebadge kan dit sjabloon dus in het resultaat brengen.
    await _revealTemplate(tester, find.text('MIAUW-pentestrapport'));
    expect(find.text('MIAUW-pentestrapport'), findsOneWidget);
    expect(find.text('Leeg deck'), findsNothing);
  });

  testWidgets('searching the improvement badge finds the SIPOC template', (
    tester,
  ) async {
    await _Harness(revealProcesverbetering: true).open(tester);
    await tester.enterText(searchField, 'Procesverbetering');
    await tester.pumpAndSettle();

    // Anders dan de vijf projecttitels noemt SIPOC de module niet in titel of
    // omschrijving. Dit resultaat bewijst daarom dat de badge meedoet.
    await _revealTemplate(tester, find.text('SIPOC-procesoverzicht'));
    expect(find.text('SIPOC-procesoverzicht'), findsOneWidget);
    expect(find.text('Leeg deck'), findsNothing);
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
    // een document per taal. Elke door de UI ondersteunde taal wordt geprobeerd;
    // ontbrekende content valt terug naar het Engels.
    tearDown(() => AppLocalizations.setActiveLanguageCode('nl'));

    // Op de sleutel en niet op de tekst: de melding bestaat in 30 talen, en de
    // vertaling opzoeken zou de test laten meebewegen met wat hij bewaakt.
    final notice = find.byKey(const ValueKey('templateLanguageNotice'));

    testWidgets('meldt de Engelse fallback voor Klingon', (tester) async {
      AppLocalizations.setActiveLanguageCode('tlh');
      final harness = _Harness();
      await harness.open(tester);
      expect(notice, findsOneWidget);
    });

    testWidgets('zwijgt in het Nederlands', (tester) async {
      // Een melding die niets toevoegt leert mensen meldingen overslaan.
      AppLocalizations.setActiveLanguageCode('nl');
      final harness = _Harness();
      await harness.open(tester);
      expect(notice, findsNothing);
    });

    testWidgets('zwijgt in het Engels', (tester) async {
      // Engels heeft zijn eigen inhoudsdocumenten; er valt niets te melden.
      AppLocalizations.setActiveLanguageCode('en');
      final harness = _Harness();
      await harness.open(tester);
      expect(notice, findsNothing);
    });
  });
}
