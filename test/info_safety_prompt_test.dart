import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Discovery prompt: opening a deck that carries Informatieveiligheid slide
/// types while the module is off must offer a one-time "enable the module"
/// snackbar (PENTEST_MIAUW §6). The slides still render regardless — the prompt
/// is pure discovery (MODUS-REGEL). It fires exactly once, at the OPEN, and
/// never again on an edit (which builds a fresh Deck via copyWith but never
/// touches the open path).
void main() {
  const promptText =
      'Deze presentatie bevat onderdelen van de Informatieveiligheidsmodule. '
      'Zet de module aan om ze te bewerken.';

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    // Past the consent gate so the shell renders instead of the consent screen.
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  /// A deck with a security (finding) slide, serialised the way a real file on
  /// disk would be — so it travels the genuine open path
  /// ([TabsNotifier.openDeckFromBytes] → `_placeDeckInTab`), not a direct
  /// `loadDeck`.
  Uint8List findingDeckBytes() {
    final deck = Deck(
      title: 'Pentestrapport',
      slides: [
        Slide.create(SlideType.title).copyWith(title: 'Pentestrapport'),
        Slide.create(
          SlideType.finding,
        ).copyWith(title: 'SQL-injectie', findingId: 'F-01'),
      ],
    );
    final markdown = MarkdownService().generateDeck(deck);
    return Uint8List.fromList(utf8.encode(markdown));
  }

  Uint8List plainDeckBytes() {
    final deck = Deck(
      title: 'Gewone presentatie',
      slides: [
        Slide.create(SlideType.title).copyWith(title: 'Gewone presentatie'),
        Slide.create(SlideType.bullets).copyWith(bullets: const ['Een']),
      ],
    );
    return Uint8List.fromList(
      utf8.encode(MarkdownService().generateDeck(deck)),
    );
  }

  // Pumps the whole app (module off by default) and returns its
  // ProviderContainer + tabs notifier. The module state is
  // warmed up during pumpAndSettle (AppShell.initState reads it), so by the
  // time a deck opens its `loading` flag has cleared.
  Future<(ProviderContainer, TabsNotifier)> pumpShell(
    WidgetTester tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    // Sanity: the module is genuinely off (not merely still loading), so a
    // fired prompt is a real "module off" prompt, not a loading artefact.
    final sec = container.read(infoSafetyProvider);
    expect(sec.loading, isFalse);
    expect(sec.enabled, isFalse);
    return (container, container.read(tabsProvider.notifier));
  }

  testWidgets('opening a security deck while the module is off shows the '
      'enable prompt', (tester) async {
    final (_, tabs) = await pumpShell(tester);

    final result = await tabs.openDeckFromBytes(
      findingDeckBytes(),
      'rapport.md',
    );
    await tester.pumpAndSettle();

    expect(result, OpenResult.opened);
    expect(find.text(promptText), findsOneWidget);
    expect(find.text('Inschakelen'), findsOneWidget);
  });

  testWidgets('a deck without security slides shows no prompt', (tester) async {
    final (_, tabs) = await pumpShell(tester);

    final result = await tabs.openDeckFromBytes(plainDeckBytes(), 'gewoon.md');
    await tester.pumpAndSettle();

    expect(result, OpenResult.opened);
    expect(find.text('Inschakelen'), findsNothing);
  });

  testWidgets('tapping "Inschakelen" turns the module on', (tester) async {
    final (container, tabs) = await pumpShell(tester);

    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Inschakelen'));
    await tester.pumpAndSettle();

    expect(container.read(infoSafetyProvider).enabled, isTrue);
  });

  testWidgets('a security deck opened while the module is on shows no prompt', (
    tester,
  ) async {
    final (container, tabs) = await pumpShell(tester);
    // Turn the module on before opening — the discovery is already done.
    await container.read(infoSafetyProvider.notifier).enable();
    await tester.pumpAndSettle();
    expect(container.read(infoSafetyProvider).enabled, isTrue);

    final result = await tabs.openDeckFromBytes(
      findingDeckBytes(),
      'rapport.md',
    );
    await tester.pumpAndSettle();

    expect(result, OpenResult.opened);
    expect(find.text('Inschakelen'), findsNothing);
  });

  testWidgets('editing the deck after opening does not re-prompt', (
    tester,
  ) async {
    final (container, tabs) = await pumpShell(tester);

    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();
    expect(find.text('Inschakelen'), findsOneWidget);

    // Clear the open-time snackbar so any re-prompt would be visible on its own.
    final messenger = ScaffoldMessenger.of(
      tester.element(find.byType(AppShell)),
    );
    messenger.clearSnackBars();
    await tester.pumpAndSettle();
    expect(find.text('Inschakelen'), findsNothing);

    // An edit builds a new Deck instance (copyWith) but never travels the open
    // path — so the one-shot signal stays silent.
    final tab = container.read(tabsProvider).current!;
    final first = tab.deckNotifier.currentState.deck!.slides.first;
    tab.deckNotifier.updateSlide(0, first.copyWith(title: 'Gewijzigd'));
    await tester.pumpAndSettle();

    expect(find.text('Inschakelen'), findsNothing);
  });
}
