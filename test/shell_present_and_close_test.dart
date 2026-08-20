import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:path/path.dart' as p;
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
/// Eén frame op de nep-klok.
const _frame = Duration(milliseconds: 16);

/// Hoeveel pomp-stappen de nep-klok vooruitzetten; daarna pompen we frames
/// zonder de klok te verzetten. Zie de gelijknamige uitleg in
/// `shell_s3_actions_test.dart`: zo hangt het budget aan het aantal stappen en
/// niet aan de klok, en verdwijnt een melding niet door het wachten zelf.
const _clockSteps = 100;

/// Cijfer-toetsen voor het nummer-springen in de presenter (zie
/// `jumpToSlideNumber`).
const Map<String, LogicalKeyboardKey> _digitKeys = {
  '0': LogicalKeyboardKey.digit0,
  '1': LogicalKeyboardKey.digit1,
  '2': LogicalKeyboardKey.digit2,
  '3': LogicalKeyboardKey.digit3,
  '4': LogicalKeyboardKey.digit4,
  '5': LogicalKeyboardKey.digit5,
  '6': LogicalKeyboardKey.digit6,
  '7': LogicalKeyboardKey.digit7,
  '8': LogicalKeyboardKey.digit8,
  '9': LogicalKeyboardKey.digit9,
};

/// Genoeg tekst om een bevindingssectie over meerdere render-pagina's te
/// dwingen (dezelfde maat als `finding_pagination_test.dart`).
String _lorem(int n) => List.filled(n, 'lorem ipsum dolor sit amet').join(' ');

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
      for (var i = 0; i < 400; i++) {
        if (done()) {
          reached = true;
          break;
        }
        await tester.pump(i < _clockSteps ? _frame : Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      reached = reached || done();
      // Staart: de overgang moet nog uitgeanimeerd worden voordat er iets
      // aan te wijzen valt.
      for (var i = 0; i < 20; i++) {
        await tester.pump(_frame);
      }
    });
    await tester.pump();
    expect(reached, isTrue, reason: reason);
  }

  /// De presentatie zoals hij nu op het scherm staat.
  FullscreenPresenter presenter(WidgetTester tester) =>
      tester.widget<FullscreenPresenter>(find.byType(FullscreenPresenter));

  /// Verlaat de presentatie met Escape en pompt tot de route weg is.
  ///
  /// Net als [present] binnen [WidgetTester.runAsync]: het afsluiten wacht op
  /// een écht platformverzoek (fullscreen uit via window_manager), dat in de
  /// nep-async-zone nooit terugkomt — dan popt de route niet en blijft de
  /// presenter staan.
  Future<void> exitPresenter(WidgetTester tester) async {
    var gone = false;
    await tester.runAsync(() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      for (var i = 0; i < 200; i++) {
        if (find.byType(FullscreenPresenter).evaluate().isEmpty) {
          gone = true;
          break;
        }
        await tester.pump(i < _clockSteps ? _frame : Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      // Staart: de terug-overgang moet nog uitgeanimeerd worden.
      for (var i = 0; i < 20; i++) {
        await tester.pump(_frame);
      }
    });
    await tester.pump();
    gone = gone || find.byType(FullscreenPresenter).evaluate().isEmpty;
    expect(gone, isTrue, reason: 'de presentatie sloot niet na Escape');
  }

  /// Stuurt de cijfers van [number] (1-gebaseerd slidenummer) plus Enter, zodat
  /// de presenter met [_goTo] direct naar die render-dia springt — los van
  /// eventuele interne paginering, anders dan de pijltjes.
  Future<void> jumpToSlideNumber(WidgetTester tester, int number) async {
    for (final ch in '$number'.split('')) {
      await tester.sendKeyEvent(_digitKeys[ch]!);
      await tester.pump();
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
  }

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

  testWidgets('de startknop presenteert vanaf de dia waar je stond (#846)', (
    tester,
  ) async {
    // #846 draait de #607-keuze terug: wie op dia drie werkt en op afspelen
    // drukt, wil daar beginnen — de verwachting is de zichtbare dia, niet altijd
    // het begin. Wie een ándere dia wil, kiest "presenteer vanaf hier" in het
    // diamenu (zie present_from_slide_test.dart); "alleen afspelen" begint wél
    // bij dia 1.
    final tab = await pumpShell(
      tester,
      deckOf([bullets('Eerste'), bullets('Tweede'), bullets('Derde')]),
    );
    tab.editorNotifier.select(2);
    await tester.pumpAndSettle();

    await present(tester);

    expect(presenter(tester).initialIndex, 2);
    expect(find.text('Derde'), findsWidgets);
  });

  testWidgets('na Escape volgt de editor de dia waar je stopte (#1111)', (
    tester,
  ) async {
    // Start op dia 1, blader naar dia 3, verlaat met Escape: de editor hoort dan
    // op dia 3 te staan (waar je stopte), niet terug op de startdia.
    final tab = await pumpShell(
      tester,
      deckOf([bullets('Eerste'), bullets('Tweede'), bullets('Derde')]),
    );
    tab.editorNotifier.select(0);
    await tester.pumpAndSettle();

    await present(tester);
    expect(presenter(tester).initialIndex, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Derde'), findsWidgets);

    await exitPresenter(tester);

    expect(find.byType(FullscreenPresenter), findsNothing);
    expect(
      tab.editorNotifier.currentState.selectedIndex,
      2,
      reason:
          'de editor hoort op de dia te staan waar je stopte, niet op de '
          'startdia',
    );
  });

  testWidgets('na Escape kiest de editor de bron-dia, niet de render-index '
      '(#1111)', (tester) async {
    // Een overgeslagen dia zit wél in het deck maar niet in de presentatie: de
    // render-index loopt dus niet gelijk met de bron-index. De editor moet op de
    // bron-dia belanden (id-mapping), niet op de rauwe render-positie — anders
    // sprong hij hier naar de overgeslagen dia (bron 1) i.p.v. 'Derde' (bron 2).
    final tab = await pumpShell(
      tester,
      deckOf([
        bullets('Eerste'),
        bullets('Overgeslagen', skipped: true),
        bullets('Derde'),
      ]),
    );
    tab.editorNotifier.select(0);
    await tester.pumpAndSettle();

    await present(tester);
    // Gepresenteerd: [Eerste (bron 0), Derde (bron 2)] — render-index 1 = 'Derde'.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(find.text('Derde'), findsWidgets);

    await exitPresenter(tester);

    expect(
      tab.editorNotifier.currentState.selectedIndex,
      2,
      reason:
          'render-index 1 ≠ bron-index 2: de id-mapping hoort naar de '
          'bron-dia te wijzen, niet naar de overgeslagen dia',
    );
  });

  testWidgets('een uitgeklapte bevinding mapt na Escape terug op zijn bron-dia '
      '(#1111)', (tester) async {
    // Een lange bevinding presenteert als meerdere render-pagina's mét hetzelfde
    // bron-dia-id. Stop je op de tweede pagina, dan hoort de editor op de éne
    // bron-bevinding (bron 1) te staan, niet op de render-index van die pagina.
    final finding = Slide.create(SlideType.finding).copyWith(
      customMarkdown: FindingSpec(
        heading: 'F-01 · Testbevinding',
        description: _lorem(24),
        confirmation: _lorem(24),
        impact: _lorem(24),
        recommendation: _lorem(24),
      ).toMarkdown(),
    );
    final tab = await pumpShell(
      tester,
      deckOf([bullets('Intro'), finding, bullets('Slot')]),
    );
    tab.editorNotifier.select(0);
    await tester.pumpAndSettle();

    await present(tester);

    final shown = presenter(tester);
    final findingId = tab.deckNotifier.currentState.deck!.slides[1].id;
    final pageIndices = [
      for (var i = 0; i < shown.slides.length; i++)
        if (shown.slides[i].id == findingId) i,
    ];
    expect(
      pageIndices.length,
      greaterThan(1),
      reason:
          'de bevinding moet over meerdere render-pagina\'s uitklappen, '
          'anders toetst dit de id-mapping niet',
    );

    // Spring naar de tweede render-pagina van de bevinding (1-gebaseerd nummer).
    await jumpToSlideNumber(tester, pageIndices[1] + 1);

    await exitPresenter(tester);

    expect(
      tab.editorNotifier.currentState.selectedIndex,
      1,
      reason:
          'elke bevinding-pagina mapt terug op de éne bron-bevinding via '
          'het id, niet via de render-index',
    );
  });

  testWidgets(
    'presenteren verwijdert een zichtbare snackbar vóór de overgang',
    (tester) async {
      await pumpShell(tester, deckOf([bullets('Eerste')]));
      final shellContext = tester.element(find.byType(AppShell));
      ScaffoldMessenger.of(shellContext).showSnackBar(
        const SnackBar(
          duration: Duration(seconds: 8),
          content: Text('Rapport gemaakt.'),
        ),
      );
      await tester.pump();
      expect(find.text('Rapport gemaakt.'), findsOneWidget);

      await present(tester);

      expect(find.byType(FullscreenPresenter), findsOneWidget);
      expect(find.text('Rapport gemaakt.'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('een overgeslagen dia haalt de presentatie niet', (tester) async {
    // De tweede dia is overgeslagen: die hoort niet in de presentatie. En de
    // selectie staat er precies op — sinds #846 begint de knop bij de dia waar
    // je stond, maar een overgeslagen dia bestaat niet in de zaal, dus de start
    // schuift door naar de eerstvolgende zichtbare ('Derde', zaalindex 1).
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

  // ── Documenttabblad sluiten (#1614) ──────────────────────────────────────

  /// Opent de shell en voegt een vuil documenttabblad toe met [path] als
  /// bestandspad. Opslaan gaat rechtstreeks naar dat pad — de route die voor
  /// #1614 een StateError gooide omdat requestCloseTab tab.deckNotifier
  /// aanriep op een documenttabblad.
  Future<TabInfo> pumpDirtyDocumentShell(
    WidgetTester tester,
    String path,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );

    // Open een documenttabblad en laad een document met bestandspad erin.
    container.read(tabsProvider.notifier).newDocument();
    await tester.pumpAndSettle();
    final tab = container.read(tabsProvider).current!;
    tab.documentNotifier!.loadDocument(
      MarkdownDocument.parse('# Oorspronkelijk\n'),
      filePath: path,
    );
    // Maak vuil: een bewerking die de bron verandert.
    tab.documentNotifier!.edit('# Gewijzigd\n');
    await tester.pumpAndSettle();
    return tab;
  }

  testWidgets(
    'een vuil documenttabblad noemt "document", niet "presentatie" (#1614)',
    (tester) async {
      final temp = Directory.systemTemp.createTempSync('doc_label');
      addTearDown(() => temp.deleteSync(recursive: true));
      final path = p.join(temp.path, 'memo.md');
      File(path).writeAsStringSync('# Oorspronkelijk\n');

      final tab = await pumpDirtyDocumentShell(tester, path);
      expect(tab.isDirty, isTrue, reason: 'het tabblad moet vuil zijn');

      // Het documenttabblad is het tweede (na het welkomstscherm), dus het
      // laatste sluitknopje in de tabbalk.
      await tester.tap(tabClose().last);
      await tester.pumpAndSettle();

      // De sluitbevestiging-dialoog verschijnt.
      expect(
        find.text('Niet-opgeslagen wijzigingen'),
        findsOneWidget,
        reason: 'de sluitbevestiging-dialoog moet verschijnen',
      );
      // De melding noemt de soort: "document", niet "presentatie".
      expect(
        find.textContaining('Sla het document op voordat het tabblad sluit.'),
        findsOneWidget,
      );
      expect(
        find.textContaining('Sla de presentatie op voordat het tabblad sluit.'),
        findsNothing,
      );
    },
  );

  testWidgets('een vuil documenttabblad slaat op zonder StateError (#1614)', (
    tester,
  ) async {
    final temp = Directory.systemTemp.createTempSync('doc_save');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = p.join(temp.path, 'memo.md');
    File(path).writeAsStringSync('# Oorspronkelijk\n');

    final tab = await pumpDirtyDocumentShell(tester, path);
    expect(tab.kind, MarkdownKind.document);
    expect(tab.documentNotifier, isNotNull);
    expect(tab.isDirty, isTrue);

    await tester.tap(tabClose().last);
    await tester.pumpAndSettle();

    // Kies "Opslaan en sluiten" — voor #1614 gooide dit een StateError
    // omdat requestCloseTab tab.deckNotifier aanriep op een documenttabblad
    // (tab.deckNotifier is null voor een document). Die exception is
    // synchroon, dus hij is al gevangen vóór de async save-keten.
    await tester.tap(find.text('Opslaan en sluiten'));
    await tester.pumpAndSettle();

    // Geen StateError: de fix routeert via saveTabWithDestination.
    expect(tester.takeException(), isNull);
  });
}
