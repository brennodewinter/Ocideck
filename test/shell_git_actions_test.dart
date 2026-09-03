import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey, rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/state/git_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// De git-handelingen zoals de shell ze aanstuurt: opslaan naar de repository,
/// de uitgebrachte versies bekijken en er een vastleggen
/// (`widgets/shell/shell_actions_git.dart` plus de vensters in
/// `shell_actions_git_dialogs.dart`).
///
/// Beide bestanden zaten grotendeels op nul: alles hangt achter een menu-item
/// en een forge-aanroep. De forge is hier het in-memory dubbel dat de
/// contracttests ook gebruiken, dus wat de shell "opgeslagen" noemt is
/// narekenbaar in de repo terug te vinden.
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
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_git');
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

  /// Zie `shell_s3_actions_test`: het echte werk vordert alleen binnen
  /// [WidgetTester.runAsync], en de klok mag niet meelopen.
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

  /// Tikt op [target] en wacht tot [until] waar is; de tik valt binnen
  /// runAsync omdat de keten daar begint (zie `shell_s3_actions_test`).
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

  Deck deck({
    String title = 'Kwartaalcijfers',
    bool withVideo = false,
    bool withInk = false,
  }) {
    final slides = [
      Slide.create(SlideType.title).copyWith(title: title),
      if (withVideo)
        Slide.create(SlideType.video).copyWith(videoPath: 'media/film.mp4'),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Bevindingen', bullets: const ['Een']),
    ];
    return Deck(
      title: title,
      slides: slides,
      annotations: withInk
          ? {
              slides.first.id: const [
                InkStroke(
                  tool: InkTool.pen,
                  color: 0xFFFF0000,
                  width: 0.004,
                  points: [Offset(0.1, 0.1), Offset(0.2, 0.2)],
                  id: 's1',
                ),
              ],
            }
          : const {},
    );
  }

  /// Pompt de app met de nep-forge in plaats van de echte, laadt [d] en zet
  /// desgewenst een git-herkomst op het tabblad.
  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    Deck? d,
    GitOrigin? origin,
  }) async {
    // Zie `shell_s3_actions_test`: de asset-cache warm, anders blijft de
    // opslaanketen bij de tweede test in dit proces hangen.
    await tester.runAsync(
      () => rootBundle.loadString('assets/themes/ocideck.css'),
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          gitForgeProvider('git-1').overrideWith((ref) async => forge),
          // Geen lokale kloon onder `flutter test`: dan loopt alles over het
          // REST-pad, precies zoals op web. Ook voor de verbinding die níet
          // bestaat: het menu polst die kloon voordat het weet dat er geen
          // verbinding is, en de echte polsing start een `git`-subproces met
          // een tijdklok die de boom niet overleeft.
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
    tab.deckNotifier.loadDeck(d ?? deck());
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

  group('opslaan naar de repository', () {
    Future<void> startSave(WidgetTester tester) async {
      await openMenu(tester);
      await startChain(
        tester,
        menuItemIcon(Icons.cloud_upload_outlined),
        () => find.text('Opslaan naar git').evaluate().isNotEmpty,
        reason: 'het git-opslaanvenster kwam niet op',
      );
    }

    Finder dialogField(String label) => find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextField, label),
    );

    testWidgets('een commit landt op het pad dat de naam voorschrijft', (
      tester,
    ) async {
      await pumpShell(tester);
      await startSave(tester);

      await tester.enterText(dialogField('Deknaam'), 'kwartaalcijfers');
      await tester.pumpAndSettle();
      await tester.enterText(
        dialogField('Commitboodschap'),
        'cijfers bijgewerkt',
      );
      await tester.pumpAndSettle();

      await startChain(
        tester,
        find.widgetWithText(ElevatedButton, 'Opslaan'),
        () => textShown('Opgeslagen in git:'),
        reason: 'er kwam geen bevestiging van de commit',
      );

      expect(
        repo.files.keys,
        contains('decks/kwartaalcijfers/deck.md'),
        reason: 'het deck hoort in zijn eigen map te landen',
      );
      expect(
        utf8.decode(repo.files['decks/kwartaalcijfers/deck.md']!),
        contains('Kwartaalcijfers'),
      );
      expect(find.textContaining('decks/kwartaalcijfers'), findsOneWidget);
    });

    testWidgets('annuleren in het opslaanvenster commit niets', (tester) async {
      await pumpShell(tester);
      final voor = Map.of(repo.files);
      await startSave(tester);

      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextButton, 'Annuleren'),
        ),
      );
      await tester.pumpAndSettle();

      expect(repo.files.keys, voor.keys);
      expect(find.textContaining('Opgeslagen in git:'), findsNothing);
    });

    // #1948: annuleren van de git-opslaan-dialoog moet `false` teruggeven
    // aan de afsluitlus, anders wist die de herstelkopie en sluit hij de
    // app terwijl het werk nergens staat.
    testWidgets(
      'Opslaan via Cmd+S met git-herkomst annuleert zonder succesmelding (#1948)',
      (tester) async {
        await pumpShell(tester, origin: gitOrigin());
        final container = ProviderScope.containerOf(
          tester.element(find.byType(AppShell)),
        );
        container.read(tabsProvider).current!.deckNotifier.markDirty();
        await tester.pumpAndSettle();

        // Cmd+S roept saveTabWithDestination aan, dat via _saveToOrigin bij
        // _saveToGit uitkomt — dezelfde keten als de afsluitlus gebruikt.
        const cmdS = SingleActivator(LogicalKeyboardKey.keyS, meta: true);
        final shellShortcuts = tester
            .widgetList<CallbackShortcuts>(find.byType(CallbackShortcuts))
            .firstWhere((s) => s.bindings.containsKey(cmdS));
        shellShortcuts.bindings[cmdS]!();
        await tester.pumpAndSettle();

        // Het git-opslaan-dialoog verschijnt — annuleer het.
        expect(find.text('Deknaam'), findsOneWidget);
        await tester.tap(
          find.descendant(
            of: find.byType(AlertDialog),
            matching: find.widgetWithText(TextButton, 'Annuleren'),
          ),
        );
        await tester.pumpAndSettle();

        // Geen succesmelding: het werk is niet opgeslagen, en de afsluitlus
        // mag dit niet als "bewaard" tellen.
        expect(find.textContaining('Opgeslagen in git:'), findsNothing);
      },
    );

    testWidgets('ook met video en tekeningen komt er geen tussenvraag', (
      tester,
    ) async {
      // Tot #541 deel 2 stond hier een blokkerende "Niet alles gaat mee naar
      // git"-waarschuwing. Sinds media, grafiekdata, notities én de tekenlaag
      // meereizen is er niets meer om te melden, en is de dialoog opgeheven —
      // een waarschuwing zonder ware regels leert alleen wegklikken.
      await pumpShell(tester, d: deck(withVideo: true, withInk: true));
      await startSave(tester);

      expect(find.text('Niet alles gaat mee naar git'), findsNothing);
      expect(find.text('Opslaan naar git'), findsOneWidget);
    });
  });

  group('versies', () {
    testWidgets('de uitgebrachte versies van dit deck staan er', (
      tester,
    ) async {
      await pumpShell(tester, origin: gitOrigin());
      await openMenu(tester);

      await startChain(
        tester,
        menuItemIcon(Icons.label_outline),
        () => textShown('Versies: kwartaalcijfers'),
        reason: 'de versielijst kwam niet op',
      );

      // De tag heet `decks/<naam>/v1.0`; in de lijst staat alleen de versie —
      // de mapnaam ervoor is repo-boekhouding, geen informatie voor de lezer.
      expect(find.text('v1.0'), findsOneWidget);
      expect(
        find.textContaining('decks/kwartaalcijfers/v1.0'),
        findsNothing,
        reason: 'de mapnaam vóór de versie is repo-boekhouding',
      );
    });

    testWidgets('een versie vastleggen zet een tag in de repo', (tester) async {
      await pumpShell(tester, origin: gitOrigin());
      await openMenu(tester);

      await startChain(
        tester,
        menuItemIcon(Icons.bookmark_add_outlined),
        () => find.text('Versie vastleggen').evaluate().isNotEmpty,
        reason: 'het versievenster kwam niet op',
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextField, 'Versie'),
        ),
        'v2.0',
      );
      await tester.pumpAndSettle();

      await startChain(
        tester,
        find.widgetWithText(ElevatedButton, 'Vastleggen'),
        () => textShown('Versie vastgelegd:') || textShown('mislukt'),
        reason: 'het vastleggen kwam niet af',
      );

      expect(
        repo.tags.keys,
        contains('decks/kwartaalcijfers/v2.0'),
        reason:
            'de tag draagt de decknaam, zodat twee decks elkaar niet '
            'overschrijven',
      );
      expect(find.textContaining('Versie vastgelegd:'), findsOneWidget);
    });

    testWidgets('een versie zonder v ervoor wordt geweigerd', (tester) async {
      await pumpShell(tester, origin: gitOrigin());
      await openMenu(tester);

      await startChain(
        tester,
        menuItemIcon(Icons.bookmark_add_outlined),
        () => find.text('Versie vastleggen').evaluate().isNotEmpty,
        reason: 'het versievenster kwam niet op',
      );

      await tester.enterText(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.widgetWithText(TextField, 'Versie'),
        ),
        '2.0',
      );
      await tester.pumpAndSettle();

      // Het venster laat dit niet eens door: de knop blijft uit.
      final knop = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Vastleggen'),
      );
      expect(
        knop.onPressed,
        isNull,
        reason: 'een versie zonder v is geen versie',
      );
      expect(repo.tags.keys, isNot(contains('decks/kwartaalcijfers/2.0')));
    });

    testWidgets('zonder git-herkomst staan de versies niet in het menu', (
      tester,
    ) async {
      await pumpShell(tester);
      await openMenu(tester);

      expect(menuItemIcon(Icons.label_outline), findsNothing);
      expect(menuItemIcon(Icons.bookmark_add_outlined), findsNothing);
    });
  });

  testWidgets('een verdwenen git-verbinding zegt dat, in plaats van niets', (
    tester,
  ) async {
    final container = await pumpShell(
      tester,
      origin: const GitOrigin(
        connectionId: 'weg',
        config: GitRepoConfig(
          baseUrl: 'https://elders.example',
          owner: 'x',
          repo: 'y',
        ),
        deckDir: 'decks/kwartaalcijfers',
        baseSha: 'commit-elders',
        branch: 'main',
      ),
    );
    expect(container.read(tabsProvider).current!.gitOrigin, isNotNull);

    await openMenu(tester);
    await startChain(
      tester,
      menuItemIcon(Icons.label_outline),
      () => textShown('De git-verbinding van dit deck bestaat niet meer'),
      reason: 'de app zweeg over de verdwenen verbinding',
    );

    expect(
      find.textContaining('De git-verbinding van dit deck bestaat niet meer'),
      findsOneWidget,
    );

    // De melding draagt een eigen timer; laat hem aflopen zodat de boom schoon
    // wordt afgebroken in plaats van met een openstaande timer.
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  });
}
