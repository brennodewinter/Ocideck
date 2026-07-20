import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/git/outbox.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Widget-coverage tests for the bottom status bar (`_DeckStatusBar` and its
/// chips). The bar is private and only assembled inside the main editor layout,
/// so — like app_shell_actions_test.dart — these drive the real [OciDeckApp]
/// with a loaded deck and assert on the rendered status labels/badges. Uses
/// Dutch (nl) so t()/d() return their literal source strings.
void main() {
  const l10n = AppLocalizations(Locale('nl'));

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    // Past the consent gate so the shell renders the editor, not the consent
    // screen.
    SharedPreferences.setMockInitialValues({'app_consent_accepted': true});
  });

  Deck sampleDeck({
    TlpLevel tlp = TlpLevel.none,
    bool finalized = false,
    List<String> titles = const ['Rapport', 'Bevindingen'],
  }) => Deck(
    title: 'Testrapport',
    tlp: tlp,
    finalized: finalized,
    slides: [
      for (final t in titles)
        Slide.create(SlideType.bullets).copyWith(title: t),
    ],
  );

  // Pumps the whole app, opens [deck] in the current tab, and returns that tab.
  Future<TabInfo> pumpShell(
    WidgetTester tester, {
    Deck? deck,
    String? remoteOrigin,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(deck ?? sampleDeck(), remoteOrigin: remoteOrigin);
    await tester.pumpAndSettle();
    return tab;
  }

  testWidgets('werk dat op verbinding wacht staat in de balk', (tester) async {
    // Offline opgeslagen werk is niet weg, maar staat ook nergens waar een
    // ander erbij kan. Tot nu toe zag je dat alleen als je er zelf naar vroeg.
    const repo = GitRepoConfig(
      baseUrl: 'https://git.voorbeeld.nl',
      owner: 'librekat',
      repo: 'decks',
    );
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'storageConnections': jsonEncode([
        {'id': 'g', 'name': 'Werk', 'kind': 'git', 'config': repo.toJson()},
      ]),
    });
    await Outbox(scope: repo.storageSlug).enqueue(
      const PendingCommit(
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
        message: 'werk',
        baseSha: 'abc123',
      ),
    );

    await pumpShell(tester);
    expect(find.textContaining(l10n.d('wacht op verbinding')), findsOneWidget);
  });

  testWidgets('zonder wachtend werk zwijgt de balk erover', (tester) async {
    // Een balk die altijd iets meldt, wordt niet meer gelezen.
    await pumpShell(tester);
    expect(find.textContaining(l10n.d('wacht op verbinding')), findsNothing);
  });

  testWidgets('a freshly loaded deck shows the "saved" state and slide count', (
    tester,
  ) async {
    await pumpShell(tester);

    // Green "saved" chip (not dirty), plus the slide-count item.
    expect(find.text(l10n.t('saved')), findsWidgets);
    expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
    // The export-readiness chip is always present in some state.
    expect(find.byIcon(Icons.description_outlined), findsWidgets);
  });

  testWidgets(
    'an edit flips the save chip to "unsaved" and shows a skip badge',
    (tester) async {
      final tab = await pumpShell(tester);

      // Skipping a slide is a mutation: the deck becomes dirty and the skip
      // count appears next to the slide total.
      tab.deckNotifier.toggleSkip(0);
      await tester.pumpAndSettle();

      expect(find.text(l10n.t('unsaved')), findsWidgets);
      expect(find.byIcon(Icons.radio_button_checked), findsWidgets);
      expect(find.textContaining(l10n.t('skipped')), findsWidgets);
    },
  );

  testWidgets('a classified deck renders the TLP badge', (tester) async {
    await pumpShell(tester, deck: sampleDeck(tlp: TlpLevel.amber));

    // The official marking shows in the status bar (and the app-bar chip).
    expect(find.text('TLP:AMBER'), findsWidgets);
    expect(find.byIcon(Icons.shield_outlined), findsWidgets);
  });

  testWidgets(
    'a deck opened from a URL shows the remote-origin privacy badge',
    (tester) async {
      await pumpShell(tester, remoteOrigin: 'https://decks.example.org/q4.md');

      expect(find.text('Extern'), findsOneWidget);
    },
  );

  testWidgets('sealing a deck shows the intact integrity badge', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    tab.deckNotifier.finalizeAndSeal();
    await tester.pumpAndSettle();

    expect(find.text('Integriteit intact'), findsOneWidget);
    expect(find.byIcon(Icons.verified_user), findsOneWidget);
  });

  testWidgets('a finalized deck whose content no longer matches shows the '
      'modified badge', (tester) async {
    // Loaded as finalized but without a valid seal for the (restyled) content,
    // so the integrity check reports it as changed after finalising.
    await pumpShell(tester, deck: sampleDeck(finalized: true));

    expect(find.text('Gewijzigd na afronden'), findsOneWidget);
    expect(find.byIcon(Icons.gpp_bad), findsOneWidget);
  });
}
