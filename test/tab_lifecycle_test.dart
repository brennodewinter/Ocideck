import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
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
}
