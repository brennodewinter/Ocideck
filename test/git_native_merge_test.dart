@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_cli_io.dart';
import 'package:ocideck/services/git/native_git_mirror_api.dart';
import 'package:ocideck/services/git/native_git_mirror_io.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

// Samenvoegen op het native pad (§8.6), tegen een échte bare origin op schijf.
// De push wordt geweigerd omdat iemand anders de werkbranch verzette; daarna
// hoort er samengevoegd te worden in plaats van de commit lokaal te laten
// stranden. Wat de merge zelf beslist ligt vast in git_deck_merge_test.dart —
// hier gaat het om de git-kant: fetch, merge-base, merge-commit, push.

Future<void> _rawGit(List<String> args, String cwd) async {
  final r = await Process.run(
    'git',
    [
      '-c',
      'user.name=Test',
      '-c',
      'user.email=t@example.org',
      '-c',
      'commit.gpgsign=false',
      ...args,
    ],
    workingDirectory: cwd,
    environment: {
      'GIT_TERMINAL_PROMPT': '0',
      'GIT_CONFIG_NOSYSTEM': '1',
      'GIT_CONFIG_GLOBAL': '/dev/null',
    },
  );
  if (r.exitCode != 0) throw StateError('git ${args.join(' ')} → ${r.stderr}');
}

String _deck({required String alfa, required String beta}) =>
    '''
---
marp: true
theme: ocideck
---

## Alfa

- $alfa

---

## Beta

- $beta
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const deckDir = 'decks/kwartaalcijfers';
  const work = 'decks/kwartaalcijfers/2026-07-18';

  late Directory temp;
  late String bare;
  late GitRepoConfig config;
  late NativeGitMirror mirror;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('ngm_merge');
    Directory('${temp.path}/x').createSync(recursive: true);
    bare = '${temp.path}/x/origin.git';
    await _rawGit(['init', '--bare', '--initial-branch=main', bare], temp.path);

    // Seed: main met het deck, plus een werkbranch met dezelfde inhoud — dat is
    // de gemeenschappelijke voorouder van beide kanten.
    final seed = '${temp.path}/seed';
    await _rawGit(['clone', bare, seed], temp.path);
    File('$seed/$deckDir/deck.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(
        _deck(alfa: 'alfa origineel', beta: 'beta origineel'),
      );
    await _rawGit(['add', '-A'], seed);
    await _rawGit(['commit', '-m', 'init'], seed);
    await _rawGit(['push', 'origin', 'main'], seed);
    await _rawGit(['branch', work], seed);
    await _rawGit(['push', 'origin', work], seed);

    config = GitRepoConfig(
      baseUrl: 'file://${temp.path}',
      owner: 'x',
      repo: 'origin',
    );
    mirror = (await createNativeGitMirror(
      git: NativeGitCli(),
      config: config,
      token: '',
      baseDir: '${temp.path}/clone',
    ))!;
  });
  tearDown(() => temp.deleteSync(recursive: true));

  (ProviderContainer, TabsNotifier) build() {
    final container = ProviderContainer(
      overrides: [
        recoveryServiceProvider.overrideWithValue(
          RecoveryService(baseDir: Directory.systemTemp),
        ),
      ],
    );
    addTearDown(container.dispose);
    return (container, container.read(tabsProvider.notifier));
  }

  /// Iemand anders pusht een eigen wijziging naar de werkbranch.
  Future<void> theyPush(String markdown) async {
    final other = '${temp.path}/other${DateTime(2026).microsecond}';
    await _rawGit(['clone', '--branch', work, bare, other], temp.path);
    File('$other/$deckDir/deck.md').writeAsStringSync(markdown);
    await _rawGit(['add', '-A'], other);
    await _rawGit(['commit', '-m', 'hun wijziging'], other);
    await _rawGit(['push', 'origin', work], other);
  }

  /// Open het deck uit de clone en zet ons tabblad op de werkbranch, zodat een
  /// opslag daar landt (en dus botst met wat de ander pushte).
  Future<void> openOnWorkBranch(
    ProviderContainer container,
    TabsNotifier tabs,
  ) async {
    await tabs.openDeckFromGitNative(
      mirror,
      FakeForge(FakeRepo(branches: {}, files: {})),
      config: config,
      deckDir: deckDir,
      branch: 'main',
    );
    final tab = container.read(tabsProvider).current!;
    tab.gitOrigin = GitOrigin(
      config: config,
      branch: work,
      deckDir: deckDir,
      baseSha: tab.gitOrigin!.baseSha,
    );
  }

  /// Bewerk één bullet van het geopende deck.
  void editBeta(ProviderContainer container, String item) {
    final tab = container.read(tabsProvider).current!;
    final deck = tab.deckNotifier.currentState.deck!;
    final slides = [...deck.slides];
    slides[1] = slides[1].copyWith(bullets: [item]);
    tab.deckNotifier.loadDeck(deck.copyWith(slides: slides));
  }

  test('andere slide bewerkt: samengevoegd en gepusht', () async {
    final (container, tabs) = build();
    await openOnWorkBranch(container, tabs);

    // Zij pasten Alfa aan; wij Beta. Niets botst.
    await theyPush(_deck(alfa: 'alfa VAN HEN', beta: 'beta origineel'));
    editBeta(container, 'beta VAN ONS');

    final result = await tabs.saveToGitNative(
      mirror,
      config: config,
      deckDir: deckDir,
      branch: 'main',
      message: 'onze wijziging',
      now: DateTime(2026, 7, 18),
    );

    expect(result.status, GitSaveStatus.merged);
    expect(result.conflicts, isEmpty);

    // Op de origin staat nu één werkbranch met beide bewerkingen erin.
    final verify = '${temp.path}/verify';
    await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
    final landed = File('$verify/$deckDir/deck.md').readAsStringSync();
    expect(landed, contains('alfa VAN HEN'), reason: 'hun werk');
    expect(landed, contains('beta VAN ONS'), reason: 'ons werk');

    // En het is een échte merge-commit: twee ouders, dus de historie van de
    // ander is niet weggegooid maar samengevoegd.
    final parents = await Process.run('git', [
      'rev-list',
      '--parents',
      '-n',
      '1',
      'HEAD',
    ], workingDirectory: verify);
    expect(
      (parents.stdout as String).trim().split(' ').length,
      3,
      reason: 'commit + twee ouders',
    );
  });

  test(
    'dezelfde slide bewerkt: conflict, lokaal gehouden, niets gepusht',
    () async {
      final (container, tabs) = build();
      await openOnWorkBranch(container, tabs);

      // Allebei Beta, anders.
      await theyPush(_deck(alfa: 'alfa origineel', beta: 'beta VAN HEN'));
      editBeta(container, 'beta VAN ONS');

      final result = await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'onze wijziging',
        now: DateTime(2026, 7, 18),
      );

      expect(result.status, GitSaveStatus.conflict);
      expect(result.conflicts, hasLength(1));
      final conflict = result.conflicts.single;
      expect(conflict.ours!.bullets.join(), contains('VAN ONS'));
      expect(conflict.theirs!.bullets.join(), contains('VAN HEN'));

      // Niet gepubliceerd: op de origin staat nog steeds hún versie.
      final verify = '${temp.path}/verify2';
      await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
      final onOrigin = File('$verify/$deckDir/deck.md').readAsStringSync();
      expect(onOrigin, contains('beta VAN HEN'));
      expect(onOrigin, isNot(contains('beta VAN ONS')));

      // Maar hun werk is wél al binnengehaald: het samengevoegde deck staat in het
      // tabblad met onze kant voorop, en de volgende opslag botst niet opnieuw.
      final deck = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .deck!;
      expect(
        deck.slides[conflict.mergedIndex!].bullets.join(),
        contains('VAN ONS'),
      );
    },
  );

  test('na het kiezen landt de opslag alsnog', () async {
    final (container, tabs) = build();
    await openOnWorkBranch(container, tabs);
    await theyPush(_deck(alfa: 'alfa origineel', beta: 'beta VAN HEN'));
    editBeta(container, 'beta VAN ONS');

    // Eerste poging botst.
    final first = await tabs.saveToGitNative(
      mirror,
      config: config,
      deckDir: deckDir,
      branch: 'main',
      message: 'onze wijziging',
      now: DateTime(2026, 7, 18),
    );
    expect(first.status, GitSaveStatus.conflict);

    // De gebruiker kiest (hier: hun kant) en slaat opnieuw op.
    final conflict = first.conflicts.single;
    final tab = container.read(tabsProvider).current!;
    final deck = tab.deckNotifier.currentState.deck!;
    final slides = [...deck.slides];
    slides[conflict.mergedIndex!] = conflict.theirs!;
    tab.deckNotifier.loadDeck(deck.copyWith(slides: slides));

    final second = await tabs.saveToGitNative(
      mirror,
      config: config,
      deckDir: deckDir,
      branch: 'main',
      message: 'keuze gemaakt',
      now: DateTime(2026, 7, 18),
    );

    // De branch bevat hun werk inmiddels, dus dit landt gewoon.
    expect(
      second.status,
      anyOf(GitSaveStatus.committed, GitSaveStatus.merged),
      reason: 'geen tweede botsing op hetzelfde punt',
    );
    final verify = '${temp.path}/verify3';
    await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
    expect(
      File('$verify/$deckDir/deck.md').readAsStringSync(),
      contains('beta VAN HEN'),
    );
  });

  test('de merge laat een geldig deck achter, geen conflictmarkers', () async {
    final (container, tabs) = build();
    await openOnWorkBranch(container, tabs);
    await theyPush(_deck(alfa: 'alfa VAN HEN', beta: 'beta origineel'));
    editBeta(container, 'beta VAN ONS');

    await tabs.saveToGitNative(
      mirror,
      config: config,
      deckDir: deckDir,
      branch: 'main',
      message: 'onze wijziging',
      now: DateTime(2026, 7, 18),
    );

    final verify = '${temp.path}/verify4';
    await _rawGit(['clone', '--branch', work, bare, verify], temp.path);
    final landed = File('$verify/$deckDir/deck.md').readAsStringSync();
    // Dít is waarom de merge per slide gaat en niet per regel: git zou hier
    // markers achterlaten en dan parseert het deck niet meer.
    expect(landed, isNot(contains('<<<<<<<')));
    expect(landed, isNot(contains('>>>>>>>')));
    expect(MarkdownService().parseDeck(landed), isNotNull);
  });
}
