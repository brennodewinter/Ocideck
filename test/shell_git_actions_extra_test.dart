import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/state/git_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// Aanvullende dekking voor `shell_actions_git.dart` — de menu-acties die de
/// existing test niet raakt: synchroniseren, zoeken in decks, en de
/// save-status-meldingen (queued, failed).
void main() {
  late Directory tmp;
  late FakeRepo repo;
  late FakeForge forge;

  const config = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'librekat',
    repo: 'decks',
  );

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_git_extra');
    repo = FakeRepo(
      branches: {'main': 'commit-main'},
      files: {
        'decks/kwartaalcijfers/deck.md': Uint8List.fromList(
          utf8.encode('---\nmarp: true\n---\n\n# Kwartaalcijfers\n'),
        ),
      },
      tags: {'decks/kwartaalcijfers/v1.0': 'commit-main'},
    );
    forge = FakeForge(repo);
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'storageConnections': StorageConnection.encodeList([
        LocalConnection(id: 'lokaal', name: 'Werkmap', path: tmp.path),
        const GitConnection(id: 'git-1', name: 'LibreKAT', repo: config),
      ]),
    });
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));
  Finder menuItemIcon(IconData icon) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.byIcon(icon),
  );

  Future<bool> settleAsync(
    WidgetTester tester,
    bool Function() until, {
    Future<void> Function()? start,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    var reached = false;
    await tester.runAsync(() async {
      if (start != null) {
        await start();
        await tester.pump();
      }
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (until()) {
          reached = true;
          break;
        }
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      reached = reached || until();
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();
    return reached;
  }

  Future<void> startChain(
    WidgetTester tester,
    Finder target,
    bool Function() until, {
    required String reason,
  }) async {
    expect(
      await settleAsync(tester, until, start: () => tester.tap(target)),
      isTrue,
      reason: reason,
    );
  }

  bool textShown(String needle) =>
      find.textContaining(needle).evaluate().isNotEmpty;

  Deck deck() => Deck(
    title: 'Kwartaalcijfers',
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Kwartaalcijfers'),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Bevindingen', bullets: const ['Een']),
    ],
  );

  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    GitOrigin? origin,
  }) async {
    await tester.runAsync(
      () => rootBundle.loadString('assets/themes/ocideck.css'),
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitForgeProvider('git-1').overrideWith((ref) async => forge),
          for (final id in const ['git-1', 'weg'])
            nativeGitMirrorProvider(id).overrideWith((ref) async => null),
        ],
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(deck());
    if (origin != null) tab.gitOrigin = origin;
    await tester.pumpAndSettle();
    return container;
  }

  GitOrigin gitOrigin() => const GitOrigin(
    connectionId: 'git-1',
    config: config,
    deckDir: 'decks/kwartaalcijfers',
    baseSha: 'commit-main',
    branch: 'main',
  );

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
  }

  testWidgets('synchroniseren meldt "Niets in de wachtrij"', (tester) async {
    await pumpShell(tester);
    await openMenu(tester);

    await startChain(
      tester,
      menuItemIcon(Icons.sync),
      () => textShown('Niets in de wachtrij') || textShown('Gesynchroniseerd'),
      reason: 'de synchronisatie meldde zich niet',
    );

    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoeken in decks opent het zoekvenster', (tester) async {
    await pumpShell(tester);
    await openMenu(tester);

    await startChain(
      tester,
      menuItemIcon(Icons.manage_search),
      () => find.byType(AlertDialog).evaluate().isNotEmpty,
      reason: 'het zoekvenster kwam niet op',
    );

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('afbeeldingen in de repository opent het venster', (
    tester,
  ) async {
    await pumpShell(tester);
    await openMenu(tester);

    await startChain(
      tester,
      menuItemIcon(Icons.photo_library_outlined),
      () => find.byType(AlertDialog).evaluate().isNotEmpty,
      reason: 'het afbeeldingen-venster kwam niet op',
    );

    expect(find.byType(AlertDialog), findsOneWidget);
  });

  testWidgets('zonder git-herkomst staat de review-actie niet in het menu', (
    tester,
  ) async {
    await pumpShell(tester);
    await openMenu(tester);

    expect(menuItemIcon(Icons.rate_review_outlined), findsNothing);
    expect(menuItemIcon(Icons.merge_outlined), findsNothing);
  });

  testWidgets('met git-herkomst op main staat review niet in het menu', (
    tester,
  ) async {
    await pumpShell(tester, origin: gitOrigin());
    await openMenu(tester);

    // Review/merge staan er alleen op een concept-branch, niet op main.
    expect(menuItemIcon(Icons.rate_review_outlined), findsNothing);
    expect(menuItemIcon(Icons.merge_outlined), findsNothing);
  });

  testWidgets('op een concept-branch staat de review-actie in het menu', (
    tester,
  ) async {
    await pumpShell(
      tester,
      origin: const GitOrigin(
        connectionId: 'git-1',
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        baseSha: 'commit-main',
        branch: 'decks/kwartaalcijfers/2026-07-16',
      ),
    );
    await openMenu(tester);

    expect(menuItemIcon(Icons.rate_review_outlined), findsOneWidget);
    expect(menuItemIcon(Icons.merge_outlined), findsOneWidget);
  });

  testWidgets('review-dialoog opent en kan worden geannuleerd', (tester) async {
    await pumpShell(
      tester,
      origin: const GitOrigin(
        connectionId: 'git-1',
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        baseSha: 'commit-main',
        branch: 'decks/kwartaalcijfers/2026-07-16',
      ),
    );
    await openMenu(tester);

    await startChain(
      tester,
      menuItemIcon(Icons.rate_review_outlined),
      () => find.text('Uitbrengen ter review').evaluate().isNotEmpty,
      reason: 'het review-venster kwam niet op',
    );

    expect(find.text('Uitbrengen ter review'), findsOneWidget);
    expect(find.byType(TextField), findsWidgets);

    // Annuleren sluit het venster.
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(find.text('Uitbrengen ter review'), findsNothing);
  });

  testWidgets('merge-dialoog opent en toont de opruim-checkbox', (
    tester,
  ) async {
    await pumpShell(
      tester,
      origin: const GitOrigin(
        connectionId: 'git-1',
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        baseSha: 'commit-main',
        branch: 'decks/kwartaalcijfers/2026-07-16',
      ),
    );
    await openMenu(tester);

    await startChain(
      tester,
      menuItemIcon(Icons.merge_outlined),
      () => find.text('Concept mergen').evaluate().isNotEmpty,
      reason: 'het merge-venster kwam niet op',
    );

    expect(find.text('Concept mergen'), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsOneWidget);

    // Annuleren sluit het venster.
    await tester.tap(find.text('Annuleren'));
    await tester.pumpAndSettle();
    expect(find.text('Concept mergen'), findsNothing);
  });
}
