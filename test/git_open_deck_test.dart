import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'git_forge_fake.dart';

/// Het git-openpad (§9.2) moet dezelfde fail-closed poort hebben als elk ander
/// bytes-open: een forge is niet vertrouwder dan WebDAV (P5). Deze suite legt
/// dat vast, plus dat het tabblad de herkomst én de baseSha draagt.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const config = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'librekat',
    repo: 'decks',
  );

  const validDeck = '''
---
marp: true
theme: ocideck
---

# Kwartaalcijfers

---

## Tweede slide

- punt één
''';

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  FakeRepo repoWith(String deckMarkdown) => FakeRepo(
    branches: {'main': 'commit-main'},
    files: {
      'decks/kwartaalcijfers/deck.md': bytes(deckMarkdown),
      'assets/3f9a1c8e.png': Uint8List.fromList([0x89, 0x50, 0x4e, 0x47]),
    },
  );

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

  group('openDeckFromGit', () {
    test('opens a deck and records where it came from', () async {
      final (container, tabs) = build();
      final forge = FakeForge(repoWith(validDeck));

      final result = await tabs.openDeckFromGit(
        forge,
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
      );

      expect(result, OpenResult.opened);
      final tab = container.read(tabsProvider).current!;
      expect(tab.deckNotifier.currentState.isOpen, isTrue);

      final origin = tab.gitOrigin!;
      expect(origin.config, config);
      expect(origin.branch, 'main');
      expect(origin.deckDir, 'decks/kwartaalcijfers');
      expect(origin.deckName, 'kwartaalcijfers');
    });

    test('carries the baseSha the content was read against', () async {
      final (container, tabs) = build();

      await tabs.openDeckFromGit(
        FakeForge(repoWith(validDeck)),
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
      );

      // This is what versioning adds over WebdavOrigin: a later commit can be
      // refused as a non-fast-forward instead of silently overwriting someone.
      expect(
        container.read(tabsProvider).current!.gitOrigin!.baseSha,
        'commit-main',
      );
    });

    test('leaves no filePath: read-only, nothing landed on disk', () async {
      final (container, tabs) = build();

      await tabs.openDeckFromGit(
        FakeForge(repoWith(validDeck)),
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
      );

      expect(
        container
            .read(tabsProvider)
            .current!
            .deckNotifier
            .currentState
            .filePath,
        isNull,
      );
    });
  });

  group('openDeckFromGit passes the import gate (P5)', () {
    test('blocks unsafe markdown coming from a forge', () async {
      final (container, tabs) = build();
      // A forge is untrusted input, exactly like a URL import.
      final hostile = validDeck.replaceFirst(
        '# Kwartaalcijfers',
        '# Kwartaalcijfers\n\n<script>fetch("https://evil.example")</script>',
      );

      final result = await tabs.openDeckFromGit(
        FakeForge(repoWith(hostile)),
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
      );

      expect(result, OpenResult.blocked);
      expect(container.read(tabsProvider).current!.gitOrigin, isNull);
      expect(container.read(importSecurityAlarmProvider), isNotNull);
    });

    test('the alarm names the repo and deck, not a bare filename', () async {
      final (container, tabs) = build();
      final hostile = validDeck.replaceFirst(
        '# Kwartaalcijfers',
        '<script>alert(1)</script>',
      );

      await tabs.openDeckFromGit(
        FakeForge(repoWith(hostile)),
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
      );

      final alarm = container.read(importSecurityAlarmProvider)!;
      expect(alarm.path, contains('librekat/decks'));
      expect(alarm.path, contains('kwartaalcijfers'));
    });

    test('refuses a non-presentation without blaming security', () async {
      final (container, tabs) = build();

      final result = await tabs.openDeckFromGit(
        FakeForge(repoWith('gewoon wat tekst, geen marp-frontmatter')),
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        branch: 'main',
      );

      expect(result, OpenResult.notAPresentation);
      expect(container.read(importSecurityAlarmProvider), isNull);
    });
  });

  group('openDeckFromGit input guards', () {
    test('refuses a dir that is not a deck under the layout', () async {
      final (_, tabs) = build();
      final forge = FakeForge(repoWith(validDeck));

      for (final dir in [
        'assets',
        'decks/a/b',
        '../escape',
        'kwartaalcijfers',
      ]) {
        await expectLater(
          tabs.openDeckFromGit(
            forge,
            config: config,
            deckDir: dir,
            branch: 'main',
          ),
          throwsA(
            isA<GitForgeException>().having(
              (e) => e.kind,
              'kind',
              GitForgeError.malformed,
            ),
          ),
          reason: dir,
        );
      }
    });

    test('surfaces a missing deck.md as notFound', () async {
      final (_, tabs) = build();
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {'decks/leeg/other.txt': bytes('x')},
        ),
      );

      await expectLater(
        tabs.openDeckFromGit(
          forge,
          config: config,
          deckDir: 'decks/leeg',
          branch: 'main',
        ),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.notFound,
          ),
        ),
      );
    });

    test('surfaces an unknown branch as notFound', () async {
      final (_, tabs) = build();

      await expectLater(
        tabs.openDeckFromGit(
          FakeForge(repoWith(validDeck)),
          config: config,
          deckDir: 'decks/kwartaalcijfers',
          branch: 'bestaat-niet',
        ),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.notFound,
          ),
        ),
      );
    });
  });

  group('listDecks', () {
    test('lists the deck directories on a branch', () async {
      final decks = await FakeForge(FakeRepo.sample()).listDecks('main');

      expect(decks, {
        'jaarplan': 'decks/jaarplan',
        'kwartaalcijfers': 'decks/kwartaalcijfers',
      });
    });

    test('ignores anything that is not a valid deck directory', () async {
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {
            'decks/geldig/deck.md': bytes('x'),
            // A stray file directly under decks/ is not a deck.
            'decks/README.md': bytes('x'),
            'decks/.verborgen/deck.md': bytes('x'),
          },
        ),
      );

      expect((await forge.listDecks('main')).keys, ['geldig']);
    });
  });
}
