import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/markdown_kind.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/state/privacy_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
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

    // Open een documenttabblad (wordt de tweede tab, na het welkomstscherm).
    tabs.newDocument();
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
  });
}
