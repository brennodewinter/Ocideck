@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/git_cli_io.dart';
import 'package:ocideck/services/git/native_git_mirror_api.dart';
import 'package:ocideck/services/git/native_git_mirror_io.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

// Het native git-pad door de TabsNotifier: openen uit de clone en opslaan als
// echte commit, tegen een bare origin op schijf. Bewijst de bedrading boven op
// de mirror-mechaniek (die native_git_mirror_test.dart al dekt).

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const deckDir = 'decks/kwartaalcijfers';
  const validDeck = '''
---
marp: true
theme: ocideck
---

# Kwartaalcijfers
''';

  late Directory temp;
  late String bare;
  late GitRepoConfig config;
  late NativeGitMirror mirror;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('ngm_notifier');
    Directory('${temp.path}/x').createSync(recursive: true);
    bare = '${temp.path}/x/origin.git';
    await _rawGit(['init', '--bare', '--initial-branch=main', bare], temp.path);
    final seed = '${temp.path}/seed';
    await _rawGit(['clone', bare, seed], temp.path);
    File('$seed/$deckDir/deck.md')
      ..parent.createSync(recursive: true)
      ..writeAsStringSync(validDeck);
    await _rawGit(['add', '-A'], seed);
    await _rawGit(['commit', '-m', 'init'], seed);
    await _rawGit(['push', 'origin', 'main'], seed);

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

  test('opent uit de clone met de clone-HEAD als basis', () async {
    final (container, tabs) = build();
    final result = await tabs.openDeckFromGitNative(
      mirror,
      FakeForge(FakeRepo(branches: {}, files: {})),
      config: config,
      deckDir: deckDir,
      branch: 'main',
    );
    expect(result, OpenResult.opened);
    final origin = container.read(tabsProvider).current!.gitOrigin!;
    expect(origin.deckDir, deckDir);
    expect(origin.baseSha, isNotEmpty); // de clone-HEAD
  });

  test(
    'opslaan landt op een werkbranch op de origin, niet op main (D3)',
    () async {
      final (container, tabs) = build();
      await tabs.openDeckFromGitNative(
        mirror,
        FakeForge(FakeRepo(branches: {}, files: {})),
        config: config,
        deckDir: deckDir,
        branch: 'main',
      );

      // Bewerk het deck en sla native op.
      container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .loadDeck(
            Deck(
              title: 'Kwartaalcijfers',
              slides: [
                Slide.create(
                  SlideType.title,
                ).copyWith(title: 'Nieuwe kwartaaltitel'),
              ],
            ),
          );
      final result = await tabs.saveToGitNative(
        mirror,
        config: config,
        deckDir: deckDir,
        branch: 'main',
        message: 'bewerkt',
        now: DateTime(2026, 7, 18),
      );
      expect(result.status, GitSaveStatus.committed);
      // Het tabblad volgt de concept-branch.
      expect(
        container.read(tabsProvider).current!.gitOrigin!.branch,
        'decks/kwartaalcijfers/2026-07-18',
      );

      // Verse clone van origin: de bewerking staat op de werkbranch, niet op main.
      final verify = '${temp.path}/verify';
      await _rawGit(['clone', bare, verify], temp.path);
      final onMain = File('$verify/$deckDir/deck.md').readAsStringSync();
      expect(
        onMain,
        contains('# Kwartaalcijfers'),
      ); // de oorspronkelijke inhoud
      expect(
        onMain,
        isNot(contains('Nieuwe kwartaaltitel')),
        reason: 'main is niet aangeraakt',
      );
      await _rawGit(['checkout', 'decks/kwartaalcijfers/2026-07-18'], verify);
      expect(
        File('$verify/$deckDir/deck.md').readAsStringSync(),
        contains('Nieuwe kwartaaltitel'),
      );
    },
  );
}
