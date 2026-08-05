import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
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
      deckNotifier: notifier,
      editorNotifier: EditorNotifier(),
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
        deckNotifier: notifier,
        editorNotifier: EditorNotifier(),
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
}
