import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Twee gedeelde handelingen uit `lib/widgets/shell/shell_actions.dart` die
/// allebei op nul uitgevoerde regels stonden: `presentDeck` (de knop, het
/// 'alleen afspelen'-scherm en het commandopalet komen er alle drie op uit) en
/// `requestCloseTab` (het kruisje op een tabblad en de middenklik).
///
/// Wat ze gemeen hebben: ze filteren of ze beschermen, en in beide gevallen is
/// de fout onzichtbaar tot hij duur is. Een dia die het publiek niet had mogen
/// bereiken staat op het scherm van de zaal; een tabblad dat zonder vragen
/// sluit neemt het werk van een middag mee.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));

  late ProviderContainer container;

  Future<TabInfo> pumpShell(WidgetTester tester, Deck deck) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(deck);
    await tester.pumpAndSettle();
    return tab;
  }

  /// Tikt op de presenteerknop en pompt tot [until] waar is.
  ///
  /// Binnen [WidgetTester.runAsync], want het openen begint met een échte
  /// vraag aan het platform: hoeveel schermen zijn er? Die vraag komt in de
  /// nep-async-zone nooit terug, en dan opent de presentatie niet — een test
  /// die dat niet doet ziet hier altijd "geen presentatie", ook als hij wél
  /// zou openen.
  Future<void> present(
    WidgetTester tester, {
    bool Function()? until,
    String reason = 'de presentatie kwam niet op',
  }) async {
    final done =
        until ?? () => find.byType(FullscreenPresenter).evaluate().isNotEmpty;
    var reached = false;
    await tester.runAsync(() async {
      await tester.tap(appBarIcon(Icons.play_circle_outline));
      for (var i = 0; i < 100; i++) {
        if (done()) {
          reached = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      reached = reached || done();
      // Staart: de overgang moet nog uitgeanimeerd worden voordat er iets
      // aan te wijzen valt.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    });
    await tester.pump();
    expect(reached, isTrue, reason: reason);
  }

  /// De presentatie zoals hij nu op het scherm staat.
  FullscreenPresenter presenter(WidgetTester tester) =>
      tester.widget<FullscreenPresenter>(find.byType(FullscreenPresenter));

  Deck deckOf(List<Slide> slides, {TlpLevel tlp = TlpLevel.none}) =>
      Deck(title: 'Testrapport', tlp: tlp, slides: slides);

  Slide bullets(String title, {bool skipped = false, TlpLevel? tlp}) =>
      Slide.create(SlideType.bullets).copyWith(
        title: title,
        bullets: const ['een', 'twee'],
        skipped: skipped,
        tlp: tlp,
      );

  // ── Presenteren ───────────────────────────────────────────────────────────

  testWidgets('presenteren begint bij de dia waar de editor staat', (
    tester,
  ) async {
    final tab = await pumpShell(
      tester,
      deckOf([bullets('Eerste'), bullets('Tweede'), bullets('Derde')]),
    );
    // De editor is per tabblad; de keuze moet naar díe notifier.
    tab.editorNotifier.select(2);
    await tester.pumpAndSettle();

    await present(tester);

    // Niet vanaf het begin: wie op presenteren drukt terwijl hij aan dia drie
    // werkt, wil dia drie zien.
    expect(presenter(tester).initialIndex, 2);
    expect(find.text('Derde'), findsWidgets);
  });

  testWidgets('een overgeslagen dia haalt de presentatie niet, en de selectie '
      'schuift mee', (tester) async {
    // De tweede dia is overgeslagen. Staat de editor daarop, dan is er geen
    // overeenkomstige dia in de presentatie — de startindex moet dan naar de
    // eerstvolgende zichtbare schuiven en niet naar de verkeerde dia wijzen.
    final tab = await pumpShell(
      tester,
      deckOf([
        bullets('Eerste'),
        bullets('Overgeslagen', skipped: true),
        bullets('Derde'),
      ]),
    );
    tab.editorNotifier.select(1);
    await tester.pumpAndSettle();

    await present(tester);

    final shown = presenter(tester);
    expect(shown.slides.map((s) => s.title), ['Eerste', 'Derde']);
    // De selectie stond op de overgeslagen dia; die bestaat in de presentatie
    // niet, dus schuift de start naar de eerstvolgende zichtbare — index 1,
    // niet index 1 van het oorspronkelijke deck.
    expect(shown.initialIndex, 1);
    expect(find.text('Overgeslagen'), findsNothing);
  });

  testWidgets('een dia met een strengere TLP dan de presentatie blijft weg', (
    tester,
  ) async {
    // Achterhouden is iets anders dan overslaan: het volgt uit een
    // classificatie, niet uit een keuze per dia. De zaal mag hem niet zien.
    await pumpShell(
      tester,
      deckOf([
        bullets('Openbaar'),
        bullets('Vertrouwelijk', tlp: TlpLevel.red),
      ], tlp: TlpLevel.green),
    );

    await present(tester);

    expect(find.byType(FullscreenPresenter), findsOneWidget);
    expect(find.text('Vertrouwelijk'), findsNothing);
    expect(find.text('Openbaar'), findsWidgets);
  });

  testWidgets('een deck zonder zichtbare dia\'s meldt de juiste reden', (
    tester,
  ) async {
    await pumpShell(
      tester,
      deckOf([bullets('Een', skipped: true), bullets('Twee', skipped: true)]),
    );

    await present(
      tester,
      until: () => find
          .text('Alle slides zijn overgeslagen — niets om te tonen.')
          .evaluate()
          .isNotEmpty,
      reason: 'een lege presentatie bleef stil',
    );

    expect(
      find.byType(FullscreenPresenter),
      findsNothing,
      reason: 'een lege presentatie hoort niet te openen',
    );
  });

  testWidgets(
    'is TLP de oorzaak, dan zegt de melding dát — niet "overgeslagen"',
    (tester) async {
      // De melding wees vroeger naar de verkeerde knop: "Alles tonen" haalt een
      // achtergehouden dia niet terug.
      await pumpShell(
        tester,
        deckOf([
          bullets('Een', tlp: TlpLevel.red),
          bullets('Twee', tlp: TlpLevel.amber),
        ], tlp: TlpLevel.clear),
      );

      await present(
        tester,
        until: () => find
            .text(
              'Alle slides zijn achtergehouden door hun TLP-classificatie — '
              'niets om te tonen.',
            )
            .evaluate()
            .isNotEmpty,
        reason: 'de TLP-reden werd niet gemeld',
      );

      expect(find.byType(FullscreenPresenter), findsNothing);
    },
  );

  testWidgets('een ingeschakelde slotdia wordt achteraan geplakt', (
    tester,
  ) async {
    // De slotdia hoort bij het stijlprofiel uit de instellingen, niet bij het
    // deck: `loadDeck` vervangt het profiel van een geladen deck door het
    // actieve. Hem op het deck zetten zou hier dus stilzwijgend niets doen.
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'themeProfile': jsonEncode(
        const ThemeProfile(
          closingSlideEnabled: true,
          closingSlideMarkdown: '# Tot ziens',
        ).toJson(),
      ),
    });
    await pumpShell(tester, deckOf([bullets('Eerste')]));

    await present(tester);

    // De slotdia is geen deck-dia: hij bestaat alleen in wat er gepresenteerd
    // wordt, en hoort achteraan.
    final shown = presenter(tester);
    expect(shown.slides, hasLength(2));
    expect(shown.slides.last.type, SlideType.freeMarkdown);
    expect(shown.slides.last.customMarkdown, contains('Tot ziens'));
  });

  // ── Tabblad sluiten ───────────────────────────────────────────────────────

  /// Maakt het tabblad vuil door een echte bewerking te doen.
  void dirty(TabInfo tab) {
    final deck = tab.deckNotifier.currentState.deck!;
    tab.deckNotifier.updateSlide(
      0,
      deck.slides.first.copyWith(title: 'Gewijzigd'),
    );
  }

  Finder tabClose() => find.byIcon(Icons.close);

  testWidgets('een tabblad met wijzigingen vraagt eerst', (tester) async {
    final tab = await pumpShell(tester, deckOf([bullets('Eerste')]));
    dirty(tab);
    await tester.pumpAndSettle();

    await tester.tap(tabClose().first);
    await tester.pumpAndSettle();

    expect(find.text('Niet-opgeslagen wijzigingen'), findsOneWidget);
    expect(
      find.textContaining('Sla de presentatie op voordat het tabblad sluit.'),
      findsOneWidget,
    );
  });

  testWidgets('annuleren houdt het tabblad én het werk', (tester) async {
    final tab = await pumpShell(tester, deckOf([bullets('Eerste')]));
    dirty(tab);
    await tester.pumpAndSettle();

    await tester.tap(tabClose().first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(
      container
          .read(tabsProvider)
          .current
          ?.deckNotifier
          .currentState
          .deck
          ?.slides
          .first
          .title,
      'Gewijzigd',
      reason: 'annuleren mag niets weggooien',
    );
    expect(container.read(tabsProvider).current?.isDirty, isTrue);
  });

  testWidgets('"Niet opslaan" sluit het tabblad wél', (tester) async {
    final tab = await pumpShell(tester, deckOf([bullets('Eerste')]));
    dirty(tab);
    await tester.pumpAndSettle();

    await tester.tap(tabClose().first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Niet opslaan'));
    await tester.pumpAndSettle();

    // Eén tabblad: sluiten laat het welkomstscherm achter in plaats van de
    // laatste tab weg te halen.
    expect(container.read(tabsProvider).current?.isOpen, isFalse);
  });

  testWidgets('een tabblad zonder wijzigingen sluit zonder vragen', (
    tester,
  ) async {
    await pumpShell(tester, deckOf([bullets('Eerste')]));

    await tester.tap(tabClose().first);
    await tester.pumpAndSettle();

    expect(find.text('Niet-opgeslagen wijzigingen'), findsNothing);
    expect(container.read(tabsProvider).current?.isOpen, isFalse);
  });
}
