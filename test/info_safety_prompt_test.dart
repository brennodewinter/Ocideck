import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/info_safety_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/presentation/fullscreen_presenter.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Discovery prompt: opening a deck that carries Informatieveiligheid slide
/// types while the module is off must offer a one-time "enable the module"
/// banner (PENTEST_MIAUW §6). The slides still render regardless — the prompt
/// is pure discovery (MODUS-REGEL). It fires exactly once, at the OPEN, and
/// never again on an edit (which builds a fresh Deck via copyWith but never
/// touches the open path).
///
/// Beyond *when* it fires, the banner has to leave the user three ways out —
/// look first, accept, decline — and it must not outlive the presentation it
/// is talking about.
/// Eén frame op de nep-klok, en hoeveel pomp-stappen we de klok vooruitzetten
/// voordat we frames zonder tijdsverloop pompen. Zie de uitgebreide uitleg in
/// `shell_present_and_close_test.dart`: zo hangt het meldingsbudget aan het
/// aantal stappen en niet aan de klok.
const _frame = Duration(milliseconds: 16);
const _clockSteps = 100;

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

  Finder presentButton() => find.descendant(
    of: find.byType(AppBar),
    matching: find.byIcon(Icons.play_circle_outline),
  );

  /// Start de presentatie door op de presenteerknop te tikken en pomp tot de
  /// fullscreen-route er staat. Binnen [WidgetTester.runAsync] omdat het openen
  /// het platform naar het aantal schermen vraagt — in de nep-async-zone komt
  /// dat antwoord anders nooit terug. Zelfde patroon als
  /// `shell_present_and_close_test.dart`.
  Future<void> present(WidgetTester tester) async {
    bool done() => find.byType(FullscreenPresenter).evaluate().isNotEmpty;
    var reached = false;
    await tester.runAsync(() async {
      await tester.tap(presentButton());
      for (var i = 0; i < 400; i++) {
        if (done()) {
          reached = true;
          break;
        }
        await tester.pump(i < _clockSteps ? _frame : Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      reached = reached || done();
      for (var i = 0; i < 20; i++) {
        await tester.pump(_frame);
      }
    });
    await tester.pump();
    expect(reached, isTrue, reason: 'de presentatie kwam niet op');
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

    // Clear the open-time banner so any re-prompt would be visible on its own.
    final messenger = ScaffoldMessenger.of(
      tester.element(find.byType(AppShell)),
    );
    messenger.clearMaterialBanners();
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

  // ── The three ways out ──────────────────────────────────────────────────────

  Finder closeIcon() => find.descendant(
    of: find.byType(MaterialBanner),
    matching: find.byIcon(Icons.close),
  );

  testWidgets('the banner offers looking, enabling and declining', (
    tester,
  ) async {
    final (_, tabs) = await pumpShell(tester);
    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();

    expect(find.text('Naar de slide'), findsOneWidget);
    expect(find.text('Inschakelen'), findsOneWidget);
    expect(closeIcon(), findsOneWidget);
  });

  testWidgets('"Naar de slide" jumps to the finding and keeps the offer up', (
    tester,
  ) async {
    final (container, tabs) = await pumpShell(tester);
    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();
    final tab = container.read(tabsProvider).current!;
    expect(tab.editorNotifier.state.selectedIndex, 0);

    await tester.tap(find.text('Naar de slide'));
    await tester.pumpAndSettle();

    expect(
      tab.editorNotifier.state.selectedIndex,
      1,
      reason: 'slide 1 is the finding — the slide the message is about',
    );
    expect(
      find.text(promptText),
      findsOneWidget,
      reason: 'you looked in order to decide, so the offer must still stand',
    );
  });

  testWidgets('the ✕ declines without turning the module on', (tester) async {
    final (container, tabs) = await pumpShell(tester);
    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();

    await tester.tap(closeIcon());
    await tester.pumpAndSettle();

    expect(find.text(promptText), findsNothing);
    expect(container.read(infoSafetyProvider).enabled, isFalse);
  });

  // ── Never outliving the presentation it is about ────────────────────────────

  testWidgets('switching to another tab takes the banner away', (tester) async {
    final (container, tabs) = await pumpShell(tester);
    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();
    expect(find.text(promptText), findsOneWidget);

    container.read(tabsProvider.notifier).newDeckInNewTab('Iets anders');
    await tester.pumpAndSettle();

    expect(
      find.text(promptText),
      findsNothing,
      reason: 'the banner spoke about a presentation no longer in view',
    );
  });

  testWidgets('starting the presentation takes the banner away', (
    tester,
  ) async {
    final (_, tabs) = await pumpShell(tester);
    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();
    expect(find.text(promptText), findsOneWidget);

    await present(tester);

    expect(find.byType(FullscreenPresenter), findsOneWidget);
    expect(
      find.text(promptText),
      findsNothing,
      reason: 'een blijvende balk mag niet over het scherm van de zaal hangen',
    );
  });

  testWidgets('closing the presentation takes the banner away', (tester) async {
    final (container, tabs) = await pumpShell(tester);
    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();
    expect(find.text(promptText), findsOneWidget);

    container.read(tabsProvider.notifier).closeTab(0);
    await tester.pumpAndSettle();

    expect(find.text(promptText), findsNothing);
  });

  testWidgets('deleting the last security slide takes the banner away', (
    tester,
  ) async {
    final (container, tabs) = await pumpShell(tester);
    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();
    expect(find.text(promptText), findsOneWidget);

    // Slide 1 is de enige finding. Weg ermee: de bewering van de balk — "deze
    // presentatie bevat module-onderdelen" — is daarmee onwaar geworden.
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.removeSlide(1);
    await tester.pumpAndSettle();

    expect(
      tab.deckNotifier.currentState.deck!.hasSecuritySlides,
      isFalse,
      reason: 'sanity: the finding really is gone',
    );
    expect(find.text(promptText), findsNothing);
  });

  testWidgets('"Naar de slide" follows the finding when slides move', (
    tester,
  ) async {
    final (container, tabs) = await pumpShell(tester);
    await tabs.openDeckFromBytes(findingDeckBytes(), 'rapport.md');
    await tester.pumpAndSettle();
    final tab = container.read(tabsProvider).current!;

    // Haal de titelslide weg: de finding schuift van index 1 naar 0. Een bij
    // het openen onthouden index zou nu de verkeerde slide aanwijzen.
    tab.deckNotifier.removeSlide(0);
    await tester.pumpAndSettle();
    expect(tab.deckNotifier.currentState.deck!.firstSecuritySlideIndex, 0);
    expect(
      find.text(promptText),
      findsOneWidget,
      reason: 'the finding is still there, so the offer still stands',
    );

    await tester.tap(find.text('Naar de slide'));
    await tester.pumpAndSettle();

    expect(tab.editorNotifier.state.selectedIndex, 0);
  });
}
