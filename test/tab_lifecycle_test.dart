import 'package:flutter/widgets.dart' show debugOnRebuildDirtyWidget;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/document_deck_bridge.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/privacy_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/slides/slide_thumbnail.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  // Guards the real memory concern: the heavy DeckNotifier (full deck + an
  // 80-deep undo history) must be released when its tab closes, while the
  // surviving tab's notifier must stay alive (no double dispose).
  testWidgets('closing a tab disposes its deck notifier, not the others', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tabs = container.read(tabsProvider.notifier);

    // Open a real deck in the first tab, then add a second tab.
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          Deck(
            title: 'First',
            slides: [Slide.create(SlideType.title).copyWith(title: 'First')],
          ),
        );
    await tester.pump();
    tabs.newEmptyTab();
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs.length, 2);

    final survivor = container.read(tabsProvider).tabs[0].deckNotifier;
    final closing = container.read(tabsProvider).tabs[1].deckNotifier;

    tabs.closeTab(1);
    await tester.pumpAndSettle();

    expect(container.read(tabsProvider).tabs.length, 1);
    expect(closing.mounted, isFalse, reason: 'closed deck must be disposed');
    expect(survivor.mounted, isTrue, reason: 'surviving deck must stay alive');
  });

  // Regression: while a tab (or the window) is closing, Riverpod can dispose
  // the tab's DeckNotifier one rebuild before the TabInfo leaves the tab bar.
  // Reading label/isDirty/isOpen then threw "Tried to use DeckNotifier after
  // `dispose` was called" from _AppTabBar.build. The getters must be
  // dispose-safe instead of assuming a live notifier.
  test('TabInfo getters survive a disposed deck notifier', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = DeckNotifier(
      container.read(markdownServiceProvider),
      container.read(fileServiceProvider),
    );
    notifier.newDeck('Test');
    final tab = TabInfo(
      id: 1,
      recoveryId: 'r1',
      content: DeckTabContent(notifier, EditorNotifier()),
    );
    expect(tab.isOpen, isTrue);
    expect(tab.isDirty, isTrue);
    expect(tab.label, 'Test');

    notifier.dispose();

    expect(tab.isOpen, isFalse);
    expect(tab.isDirty, isFalse);
    expect(tab.label, 'Nieuw');
  });

  // Regression voor #1251: het tab-opschrift zonder deck volgt de actieve
  // interfacetaal, niet een hardcoded Nederlands label. De oude code schreef
  // `const AppLocalizations(Locale('nl')).d('Nieuw')` — de `Locale('nl')` is een
  // misleidend handvat, want `d()` leest de statisch gezette taal. Dat heeft
  // de indruk gewekt dat het label in elke taal Nederlands was, terwijl het
  // al meebewoog sinds #576. Deze test bewijst het meebewegen en bewaakt het.
  test(
    'TabInfo.label voor een leeg tab volgt de actieve interfacetaal (#1251)',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = DeckNotifier(
        container.read(markdownServiceProvider),
        container.read(fileServiceProvider),
      );
      notifier.newDeck('Test');
      final tab = TabInfo(
        id: 1,
        recoveryId: 'r1',
        content: DeckTabContent(notifier, EditorNotifier()),
      );
      notifier.dispose();

      AppLocalizations.setActiveLanguageCode('en');
      expect(tab.label, 'New');
      AppLocalizations.setActiveLanguageCode('de');
      expect(tab.label, 'Neu');
      AppLocalizations.setActiveLanguageCode('fy');
      expect(tab.label, 'Nij');

      addTearDown(() => AppLocalizations.setActiveLanguageCode('nl'));
    },
  );

  // Regression: bij het sluiten van een tab kan Riverpod de DeckNotifier al
  // disposen terwijl er nog één rebuild van _TabContent gepland staat. De
  // deckProvider.override levert dan een gedisposede notifier op en de
  // privacyketen (deckProvider → privacyScanProvider →
  // privacyQualityIssuesProvider) gooit "Tried to use DeckNotifier after
  // dispose" vanuit StateNotifier.addListener. c542bf1e fixte TabInfo.label
  // maar niet de providerketen.
  //
  // De race zelf is niet in een widgettest te forceren (pump verwerkt frames
  // sequentieel), maar de gevolgde oplossing wel direct getest: een override
  // die een gedisposede notifier teruggeeft moet de privacyketen niet laten
  // crashen, maar terugvallen op een verse lege notifier. Dit is dezelfde
  // patroon-check als in _tabScope (app_shell.dart).
  testWidgets(
    'privacyketen overleeft een gedisposede DeckNotifier in de override',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = DeckNotifier(
        container.read(markdownServiceProvider),
        container.read(fileServiceProvider),
      );
      notifier.dispose();

      // Zonder de mounted-check in de override gooit StateNotifier.addListener
      // "Tried to use DeckNotifier after dispose". Met de check levert de
      // override een verse lege notifier op en de keten returned leeg.
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: ProviderScope(
            overrides: [
              deckProvider.overrideWith(
                (ref) => notifier.mounted
                    ? notifier
                    : DeckNotifier(
                        ref.read(markdownServiceProvider),
                        ref.read(fileServiceProvider),
                      ),
              ),
              privacyRawScanProvider.overrideWith(computePrivacyRawScan),
              privacyScanProvider.overrideWith(computePrivacyScan),
              privacyQualityIssuesProvider.overrideWith(
                computePrivacyQualityIssues,
              ),
            ],
            child: MaterialApp(
              home: Consumer(
                builder: (context, ref, _) {
                  // Dit is de keten die in _TabContent.build via
                  // warmTabDerivedProviders wordt aangeroepen.
                  ref.watch(privacyQualityIssuesProvider);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Geen crash: de privacyketen heeft een leeg resultaat opgeleverd.
      expect(container.read(privacyQualityIssuesProvider), isEmpty);
    },
  );

  // Regression voor #1636: closeTab(0) op een staat met alleen een
  // documenttabblad gooide StateError omdat _closeTab het laatste tabblad als
  // presentatie behandelde (current.tabs.first.deckNotifier.closeDeck()) en
  // TabInfo.deckNotifier bewust gooit op een documenttabblad.
  testWidgets('closeTab op het enige documenttabblad crasht niet (#1636)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tabs = container.read(tabsProvider.notifier);

    // Open een documenttabblad als tweede tab, na het welkomstscherm. Een
    // extra leeg tabblad eerst, want sinds #3000 vervangt een document een
    // ongeopend Nieuw-tabblad in plaats van ernaast te komen.
    tabs.newEmptyTab();
    await tabs.newDocument();
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs.length, 2);

    // Sluit het eerste (deck-)tabblad via het multi-tab-pad, zodat het
    // documenttabblad als enige overblijft.
    tabs.closeTab(0);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs.length, 1);
    expect(container.read(tabsProvider).current?.kind, MarkdownKind.document);

    // Dit gooide voor de fix: StateError: deckNotifier opgevraagd op een
    // documenttabblad.
    tabs.closeTab(0);
    await tester.pumpAndSettle();

    // Het tabblad blijft staan (als enige), maar is gereset naar leeg.
    expect(container.read(tabsProvider).tabs.length, 1);
    expect(container.read(tabsProvider).current?.isOpen, isFalse);
    expect(container.read(tabsProvider).current?.isDirty, isFalse);
    // #3107: de terugval is hetzelfde Nieuw-scherm als bij een presentatie —
    // het overblijvende tabblad is daarom een ongeopend decktabblad, geen
    // documenttabblad dat op een lege editor stuit.
    expect(
      container.read(tabsProvider).current?.kind,
      MarkdownKind.presentation,
    );
  });

  // #2623: de deck-luisteraar van TabsNotifier zendt alleen uit als een
  // tabfeit verandert — niet bij elke emissie van de deck-stroom. Voor de
  // poort herbouwde elke toetsaanslag in een dia de hele AppShell (en op
  // macOS het native menu).
  testWidgets('tabbladtoestand verandert alleen bij een tabfeit', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    var emissions = 0;
    final sub = container.listen(
      tabsProvider,
      (_, _) => emissions++,
      fireImmediately: false,
    );
    addTearDown(sub.close);

    final deckNotifier = container.read(tabsProvider).current!.deckNotifier;
    deckNotifier.loadDeck(
      Deck(
        title: 'Deck',
        slides: List.generate(
          4,
          (index) =>
              Slide.create(SlideType.title).copyWith(title: 'Dia $index'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SlideThumbnail), findsNWidgets(3));
    final original = debugOnRebuildDirtyWidget;
    var shellBuilds = 0;
    final thumbnailBuilds = <int, int>{};
    debugOnRebuildDirtyWidget = (element, builtBefore) {
      original?.call(element, builtBefore);
      if (element.widget is AppShell) shellBuilds++;
      if (element.widget case SlideThumbnail(:final index)) {
        thumbnailBuilds.update(index, (count) => count + 1, ifAbsent: () => 1);
      }
    };
    addTearDown(() => debugOnRebuildDirtyWidget = original);

    // The first edit may change the dirty indicator. Measure subsequent edits.
    deckNotifier.updateSlide(
      0,
      deckNotifier.currentState.deck!.slides.first.copyWith(title: 'A'),
    );
    await tester.pumpAndSettle();
    final baseline = emissions;
    shellBuilds = 0;
    thumbnailBuilds.clear();

    for (var i = 1; i <= 10; i++) {
      final slide = deckNotifier.currentState.deck!.slides.first;
      deckNotifier.updateSlide(0, slide.copyWith(title: 'a' * i));
      await tester.pump();
    }
    expect(shellBuilds, 0);
    expect(emissions, baseline);
    expect(thumbnailBuilds.keys, [0]);
    expect(thumbnailBuilds[0], inInclusiveRange(1, 10));

    // Een écht tabfeit — de titel van het deck is het tablabel als er geen
    // bestandspad is — moet wél uitzenden.
    deckNotifier.updateMeta(title: 'Hernoemd');
    await tester.pump();
    expect(emissions, greaterThan(baseline));
  });

  // #3107: een leeg bestand biedt een wisselknop tussen document en
  // presentatie. Beide richtingen lopen in hetzelfde tabblad en zijn alleen
  // geldig zolang er niets te verliezen valt.
  testWidgets('een leeg bestand wisselt in hetzelfde tabblad van soort (#3107)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tabs = container.read(tabsProvider.notifier);

    // Ctrl+Shift+N-pad: direct een leeg document, het Nieuw-tabblad vervangend.
    await tabs.newDocument();
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs.length, 1);
    expect(container.read(tabsProvider).current?.kind, MarkdownKind.document);

    // Document → presentatie: zelfde tabblad, kind wisselt, deck is leeg.
    swapEmptyDocumentForDeck(tabs);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs.length, 1);
    expect(
      container.read(tabsProvider).current?.kind,
      MarkdownKind.presentation,
    );
    final deck = container.read(tabsProvider).current!.deckNotifier.state.deck;
    expect(deck, isNotNull);
    expect(DocumentDeckBridge.deckIsEmpty(deck!), isTrue);

    // Presentatie → document: terug naar een leeg document in hetzelfde tabblad.
    swapEmptyDeckForDocument(tabs);
    await tester.pumpAndSettle();
    expect(container.read(tabsProvider).tabs.length, 1);
    final content = container.read(tabsProvider).current!.content;
    expect(content.kind, MarkdownKind.document);
    expect(
      (content as DocumentTabContent).documentNotifier.state.document!.body
          .trim(),
      isEmpty,
    );
  });

  // #3107: de wissel weigert zodra er inhoud is — de knop is dan ook weg,
  // dus dit bewaakt de grens waarbinnen hij aangeboden mag worden.
  testWidgets(
    'de type-wissel doet niets zodra het bestand inhoud heeft (#3107)',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(1600, 1000));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
      await tester.pumpAndSettle();

      final container = ProviderScope.containerOf(
        tester.element(find.byType(AppShell)),
      );
      final tabs = container.read(tabsProvider.notifier);

      // Document mét tekst mag niet wisselen.
      tabs.newDocumentFromMarkdown('Al een zin tekst.');
      await tester.pumpAndSettle();
      swapEmptyDocumentForDeck(tabs);
      await tester.pumpAndSettle();
      expect(container.read(tabsProvider).current?.kind, MarkdownKind.document);

      // Een deck mét titel mag niet wisselen.
      tabs.newEmptyTab();
      await tester.pumpAndSettle();
      tabs.newDeckInCurrentTab('Titel met inhoud');
      await tester.pumpAndSettle();
      swapEmptyDeckForDocument(tabs);
      await tester.pumpAndSettle();
      expect(
        container.read(tabsProvider).current?.kind,
        MarkdownKind.presentation,
      );
    },
  );
}
