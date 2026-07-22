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

/// Het vangnet uit AI_ASSIST §6.4: alle nog niet-nagekeken AI-alt-teksten in
/// één keer wissen (`widgets/shell/ai_actions.dart`). De rekenkern staat in
/// `deck_provider_ai.dart` en is daar getoetst; hier gaat het om wat de shell
/// eromheen belooft — dat er eerst gevraagd wordt, dat de vraag het aantal
/// noemt, dat annuleren écht niets aanraakt, en dat de handeling in één keer
/// terug te draaien is.
///
/// Dat laatste is de reden dat dit niet met een losse notifier te toetsen is:
/// het is een wis-actie over het hele deck, en zonder ongedaan maken is een
/// misklik onherstelbaar.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Slide image({required String alt, required bool ai}) =>
      Slide.create(SlideType.image).copyWith(
        imagePath: 'a.png',
        imageAltText: alt,
        aiAssistedFields: ai ? const ['imageAltText'] : const [],
      );

  /// Twee AI-concepten en één met de hand geschreven alt-tekst.
  Deck deckWithAiAltTexts() => Deck(
    title: 'Testrapport',
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
      image(alt: 'AI-concept een', ai: true),
      image(alt: 'Met de hand', ai: false),
      image(alt: 'AI-concept twee', ai: true),
    ],
  );

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));
  Finder menuItemIcon(IconData icon) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.byIcon(icon),
  );

  /// Pompt de app met [deck] geladen en opent het opdrachtenpalet.
  Future<TabInfo> openPalette(WidgetTester tester, Deck deck) async {
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

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.keyboard_command_key));
    await tester.pumpAndSettle();
    return tab;
  }

  /// Filtert het palet tot alleen het wis-commando overblijft.
  Future<void> filterToCommand(WidgetTester tester) async {
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

  Finder command() => find.descendant(
    of: find.byType(CommandPalette),
    matching: find.text('Wis AI-alt-teksten'),
  );

  /// De alt-teksten van het deck, in diavolgorde.
  List<String> altTexts(TabInfo tab) => [
    for (final s in tab.deckNotifier.currentState.deck!.slides)
      if (s.type == SlideType.image) s.imageAltText,
  ];

  testWidgets('wissen vraagt eerst, en noemt hoeveel het er zijn', (
    tester,
  ) async {
    final tab = await openPalette(tester, deckWithAiAltTexts());
    await filterToCommand(tester);
    await tester.tap(command());
    await tester.pumpAndSettle();

    // Er is nog niets gewist; er staat een vraag.
    expect(find.text('AI-alt-teksten wissen'), findsOneWidget);
    expect(
      find.textContaining('aantal: 2'),
      findsOneWidget,
      reason: 'de vraag moet zeggen hoeveel er verdwijnen',
    );
    expect(altTexts(tab), ['AI-concept een', 'Met de hand', 'AI-concept twee']);
  });

  testWidgets('annuleren laat elke alt-tekst staan', (tester) async {
    final tab = await openPalette(tester, deckWithAiAltTexts());
    await filterToCommand(tester);
    await tester.tap(command());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(altTexts(tab), ['AI-concept een', 'Met de hand', 'AI-concept twee']);
    expect(find.byType(SnackBar), findsNothing, reason: 'niets gebeurd');
  });

  testWidgets('bevestigen wist alleen de AI-teksten en meldt het aantal', (
    tester,
  ) async {
    final tab = await openPalette(tester, deckWithAiAltTexts());
    await filterToCommand(tester);
    await tester.tap(command());
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Wissen'));
    await tester.pumpAndSettle();

    // De handgeschreven tekst blijft; de twee markeringen verdwijnen mee.
    expect(altTexts(tab), ['', 'Met de hand', '']);
    expect(
      tab.deckNotifier.currentState.deck!.slides[1].aiAssistedFields,
      isEmpty,
    );
    expect(find.text('2 AI-alt-teksten gewist.'), findsOneWidget);
  });

  testWidgets('het wissen is in één keer ongedaan te maken', (tester) async {
    final tab = await openPalette(tester, deckWithAiAltTexts());
    await filterToCommand(tester);
    await tester.tap(command());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Wissen'));
    await tester.pumpAndSettle();
    expect(altTexts(tab), ['', 'Met de hand', '']);

    tab.deckNotifier.undo();
    await tester.pumpAndSettle();

    expect(
      altTexts(tab),
      ['AI-concept een', 'Met de hand', 'AI-concept twee'],
      reason: 'een misklik op een wis-actie moet terug te draaien zijn',
    );
  });

  testWidgets('zonder AI-alt-teksten is het commando niet aan te klikken', (
    tester,
  ) async {
    await openPalette(
      tester,
      Deck(
        title: 'Testrapport',
        slides: [
          Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
          image(alt: 'Met de hand', ai: false),
        ],
      ),
    );
    await filterToCommand(tester);

    expect(command(), findsOneWidget);
    await tester.tap(command());
    await tester.pumpAndSettle();

    // Uitgeschakeld: geen vraag, en het palet blijft gewoon open staan.
    expect(find.text('AI-alt-teksten wissen'), findsNothing);
    expect(find.byType(CommandPalette), findsOneWidget);
  });
}
