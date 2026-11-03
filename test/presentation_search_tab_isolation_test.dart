import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/editors/markdown_find_bar.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('real deck tabs keep their own search term and source identity', (
    tester,
  ) async {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tabs = container.read(tabsProvider.notifier);
    final first = container.read(tabsProvider).current!;
    first.deckNotifier.loadDeck(
      Deck(
        title: 'Eerste',
        slides: [Slide.create(SlideType.title).copyWith(title: 'Eerste')],
      ),
    );
    await tester.pumpAndSettle();
    first.editorNotifier.requestMarkdownFind(showReplace: false);
    await tester.pumpAndSettle();
    Finder query() => find
        .descendant(
          of: find.byType(MarkdownFindBar),
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(query(), 'Eerste');
    await tester.pumpAndSettle();
    final firstDeck = first.deckNotifier.currentState.deck;
    tabs.newEmptyTab();
    await tester.pumpAndSettle();
    final second = container.read(tabsProvider).current!;
    second.deckNotifier.loadDeck(
      Deck(
        title: 'Tweede',
        slides: [Slide.create(SlideType.title).copyWith(title: 'Tweede')],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MarkdownFindBar), findsNothing);
    second.editorNotifier.requestMarkdownFind(showReplace: false);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(query()).controller!.text, isEmpty);
    await tester.enterText(query(), 'Tweede');
    await tester.pumpAndSettle();
    tabs.selectTab(0);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(query()).controller!.text, 'Eerste');
    expect(first.deckNotifier.currentState.deck, same(firstDeck));
    tabs.selectTab(1);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(query()).controller!.text, 'Tweede');
  });
}
