import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Regressie voor de dispose-vloed bij het sluiten van een tabblad dat *niet*
/// het laatste is:
///
///   Bad state: Tried to use EditorNotifier after `dispose` was called.
///   Bad state: Tried to use DeckNotifier after `dispose` was called.
///
/// gevolgd door render-tree-corruptie (_RenderLayoutBuilder mutated, inactive
/// element). Oorzaak: de per-tab [ProviderScope]s leven in een [IndexedStack],
/// die elk kind in een verse *ongesleutelde* [Visibility] verpakt. Sluit je een
/// tabblad in het midden, dan matcht Flutter de wrappers op positie en herbouwt
/// het de scopes van alle tabbladen erná. Zo'n nieuwe scope adopteert dezelfde
/// nog-levende per-tab notifier die de oude scope net gaat disposen — twee
/// eigenaren, twee disposes. Erger nog dan de crash: de notifier van een
/// buur-tabblad wordt gedisposed terwijl dat tabblad gewoon open is.
///
/// De fix is een stabiele [GlobalKey] per tabblad (`_tabScopeKeys` in
/// tab_bar.dart), die Flutter de bestaande scope laat verplaatsen in plaats van
/// herbouwen. Deze test faalt zonder die sleutel en slaagt ermee.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Deck deckNamed(String t) => Deck(
    title: t,
    slides: [Slide.create(SlideType.title).copyWith(title: t)],
  );

  /// Bouwt de app met [deckTabs] tabbladen die elk een echt deck dragen, zodat
  /// in elk tab-scope zowel de [DeckNotifier] als de [EditorNotifier] is
  /// geïnitialiseerd (en dus door de scope gedisposed wordt).
  Future<ProviderContainer> buildAppWithTabs(
    WidgetTester tester,
    int deckTabs,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tabs = container.read(tabsProvider.notifier);
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(deckNamed('T0'));
    await tester.pump();
    for (var i = 1; i < deckTabs; i++) {
      tabs.newEmptyTab();
      await tester.pumpAndSettle();
      container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .loadDeck(deckNamed('T$i'));
      await tester.pumpAndSettle();
    }
    expect(container.read(tabsProvider).tabs.length, deckTabs);
    return container;
  }

  /// De notifiers van de tabbladen die na het sluiten blijven bestaan.
  List<DeckNotifier> survivors(ProviderContainer c) => [
    for (final tab in c.read(tabsProvider).tabs) tab.deckNotifier,
  ];

  testWidgets('closing an active middle tab keeps the neighbours alive', (
    tester,
  ) async {
    final container = await buildAppWithTabs(tester, 4);
    final tabs = container.read(tabsProvider.notifier);
    tabs.selectTab(1);
    await tester.pumpAndSettle();

    tabs.closeTab(1);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(tabsProvider).tabs.length, 3);
    // De kern van de regressie: de notifiers van de overgebleven tabbladen
    // mogen niet zijn meegesleurd in de dispose van het gesloten tabblad.
    for (final n in survivors(container)) {
      expect(n.mounted, isTrue, reason: 'survivor deck notifier gedisposed');
      expect(n.currentState.isOpen, isTrue, reason: 'survivor deck kwijt');
    }
  });

  testWidgets('closing the first tab while a later tab is active', (
    tester,
  ) async {
    final container = await buildAppWithTabs(tester, 4);
    final tabs = container.read(tabsProvider.notifier);
    tabs.selectTab(3);
    await tester.pumpAndSettle();

    tabs.closeTab(0);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(container.read(tabsProvider).tabs.length, 3);
    for (final n in survivors(container)) {
      expect(n.mounted, isTrue);
      expect(n.currentState.isOpen, isTrue);
    }
  });

  testWidgets('closing the last tab still disposes only that tab (baseline)', (
    tester,
  ) async {
    final container = await buildAppWithTabs(tester, 3);
    final tabs = container.read(tabsProvider.notifier);
    final closing = container.read(tabsProvider).tabs[2].deckNotifier;
    final survivorNotifiers = [
      container.read(tabsProvider).tabs[0].deckNotifier,
      container.read(tabsProvider).tabs[1].deckNotifier,
    ];

    tabs.closeTab(2);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(closing.mounted, isFalse, reason: 'gesloten tabblad moet weg');
    for (final n in survivorNotifiers) {
      expect(n.mounted, isTrue);
    }
  });
}
