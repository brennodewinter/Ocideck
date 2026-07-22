import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/command_palette.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het vangnet uit AI_ASSIST §6.4: "Wis AI-alt-teksten"
/// (`lib/widgets/shell/ai_actions.dart`). Eén handeling die een hele
/// bulk-AI-ronde terugdraait, en daarom niet zonder bevestiging mag gebeuren —
/// en al helemaal niet méér mag wissen dan de AI zelf schreef.
///
/// Dit bestand rijdt de échte shell: palet → menu-item → dialoog → deck. Het
/// waarom van die omweg is dat de handeling drie dingen aan elkaar knoopt die
/// los van elkaar allemaal groen kunnen zijn: de telling in het palet, de
/// telling in de bevestiging, en wat er daarna werkelijk in het deck staat.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  /// Drie alt-teksten: twee door de AI geschreven en nog niet nagekeken, één
  /// met de hand. De handmatige is het hele punt — hij is het verschil tussen
  /// "wist het AI-werk" en "wist alles".
  Deck deckWithAiAltTexts() => Deck(
    title: 'Beeldrapport',
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Beeldrapport'),
      Slide.create(SlideType.image).copyWith(
        title: 'Netwerkschema',
        imagePath: 'net.png',
        imageAltText: 'Door de AI beschreven schema',
        aiAssistedFields: const ['imageAltText'],
      ),
      Slide.create(SlideType.twoImages).copyWith(
        title: 'Voor en na',
        imagePath: 'voor.png',
        imagePath2: 'na.png',
        imageAltText: 'Met de hand beschreven situatie',
        imageAltText2: 'Door de AI beschreven situatie',
        aiAssistedFields: const ['imageAltText2'],
      ),
    ],
  );

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));
  Finder menuItemIcon(IconData icon) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.byIcon(icon),
  );

  /// Pompt de app, laadt [deck] en geeft het tabblad terug zodat de test op de
  /// tab-eigen deck-notifier kan asserteren.
  Future<TabInfo> pumpShell(WidgetTester tester, Deck deck) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(deck);
    await tester.pumpAndSettle();
    return tab;
  }

  /// Opent het commandopalet en filtert op de wis-actie.
  Future<void> openWipeCommand(WidgetTester tester) async {
    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.keyboard_command_key));
    await tester.pumpAndSettle();
    // Bewust binnen het palet gezocht: de shell heeft zelf ook een zoekveld.
    await tester.enterText(
      find.descendant(
        of: find.byType(CommandPalette),
        matching: find.byType(TextField),
      ),
      'AI-alt',
    );
    await tester.pumpAndSettle();
  }

  List<String> altTextsOf(TabInfo tab) => [
    for (final s in tab.deckNotifier.currentState.deck!.slides) ...[
      s.imageAltText,
      s.imageAltText2,
    ],
  ];

  testWidgets('de bevestiging noemt hoeveel alt-teksten eraan gaan', (
    tester,
  ) async {
    await pumpShell(tester, deckWithAiAltTexts());
    await openWipeCommand(tester);
    await tester.tap(find.text('Wis AI-alt-teksten'));
    await tester.pumpAndSettle();

    expect(find.text('AI-alt-teksten wissen'), findsOneWidget);
    // Twéé, niet drie: de handmatige alt-tekst telt niet mee. Zonder dat getal
    // is de bevestiging een blinde vraag — je weet niet of je een tikfout of
    // een halve dag werk weggooit.
    expect(find.textContaining('(aantal: 2)'), findsOneWidget);
  });

  testWidgets('annuleren laat elke alt-tekst staan', (tester) async {
    final tab = await pumpShell(tester, deckWithAiAltTexts());
    final before = altTextsOf(tab);

    await openWipeCommand(tester);
    await tester.tap(find.text('Wis AI-alt-teksten'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(altTextsOf(tab), before);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('wissen haalt alleen de AI-alt-teksten weg en meldt het aantal', (
    tester,
  ) async {
    final tab = await pumpShell(tester, deckWithAiAltTexts());

    await openWipeCommand(tester);
    await tester.tap(find.text('Wis AI-alt-teksten'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Wissen'));
    await tester.pumpAndSettle();

    final slides = tab.deckNotifier.currentState.deck!.slides;
    expect(slides[1].imageAltText, isEmpty);
    expect(slides[2].imageAltText2, isEmpty);
    // Het handwerk blijft — dát is waar het vangnet zijn grens heeft.
    expect(slides[2].imageAltText, 'Met de hand beschreven situatie');
    // En de herkomstmarkering gaat mee weg: een leeg veld dat nog als
    // "AI-geschreven" geldt, zou de volgende ronde opnieuw meetellen.
    expect(slides[1].aiAssistedFields, isNot(contains('imageAltText')));
    expect(slides[2].aiAssistedFields, isNot(contains('imageAltText2')));

    expect(find.text('2 AI-alt-teksten gewist.'), findsOneWidget);
  });

  testWidgets('het wissen is één ongedaan-stap', (tester) async {
    // Onomkeerbaar zou de actie onbruikbaar maken: hij bestaat juist voor het
    // geval dat een bulkronde de verkeerde kant op ging.
    final tab = await pumpShell(tester, deckWithAiAltTexts());
    final before = altTextsOf(tab);

    await openWipeCommand(tester);
    await tester.tap(find.text('Wis AI-alt-teksten'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Wissen'));
    await tester.pumpAndSettle();
    expect(altTextsOf(tab), isNot(before));

    tab.deckNotifier.undo();
    await tester.pumpAndSettle();
    expect(altTextsOf(tab), before);
  });

  testWidgets('zonder AI-alt-teksten is de actie niet uit te voeren', (
    tester,
  ) async {
    // Het commando staat er wel (zodat het vindbaar blijft), maar grijs: er is
    // niets te wissen, en dan hoort er ook geen bevestiging te openen.
    await pumpShell(
      tester,
      Deck(
        title: 'Zonder AI',
        slides: [
          Slide.create(SlideType.image).copyWith(
            title: 'Handwerk',
            imagePath: 'net.png',
            imageAltText: 'Met de hand beschreven',
          ),
        ],
      ),
    );
    await openWipeCommand(tester);

    await tester.tap(find.text('Wis AI-alt-teksten'));
    await tester.pumpAndSettle();
    expect(find.text('AI-alt-teksten wissen'), findsNothing);
  });
}
