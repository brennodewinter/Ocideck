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

/// Een uitgebrachte versie (§9.4) open je om te bekíjken, niet om overheen te
/// werken: een tag-ref, dezelfde fail-closed importpoort (P5), en géén
/// [GitOrigin] — anders zou een save de historie kunnen overschrijven. Deze
/// suite legt dat contract vast.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  const config = GitRepoConfig(
    baseUrl: 'https://git.example.org',
    owner: 'librekat',
    repo: 'decks',
  );
  const tag = 'decks/kwartaalcijfers/v1.0';

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
    tags: {tag: 'commit-v1'},
    files: {'decks/kwartaalcijfers/deck.md': bytes(deckMarkdown)},
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

  group('openVersionFromGit', () {
    test('opens a tagged version but leaves no in-place target', () async {
      final (container, tabs) = build();

      final result = await tabs.openVersionFromGit(
        FakeForge(repoWith(validDeck)),
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        tag: tag,
      );

      expect(result, OpenResult.opened);
      final tab = container.read(tabsProvider).current!;
      expect(tab.deckNotifier.currentState.isOpen, isTrue);
      // A snapshot to look at — not a target to save over. No GitOrigin, no
      // filePath, so the save path can never mistake it for its own deck.
      expect(tab.gitOrigin, isNull);
      expect(tab.deckNotifier.currentState.filePath, isNull);
    });

    test('labels the tab with the version parsed from the tag', () async {
      final (container, tabs) = build();

      await tabs.openVersionFromGit(
        FakeForge(repoWith(validDeck)),
        config: config,
        deckDir: 'decks/kwartaalcijfers',
        tag: tag,
      );

      final label = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState
          .remoteOrigin;
      expect(label, contains('kwartaalcijfers'));
      expect(label, contains('v1.0'));
    });

    test(
      'passes the import gate (P5): hostile markdown at the tag is blocked',
      () async {
        final (container, tabs) = build();
        final hostile = validDeck.replaceFirst(
          '# Kwartaalcijfers',
          '<script>fetch("https://evil.example")</script>',
        );

        final result = await tabs.openVersionFromGit(
          FakeForge(repoWith(hostile)),
          config: config,
          deckDir: 'decks/kwartaalcijfers',
          tag: tag,
        );

        expect(result, OpenResult.blocked);
        expect(container.read(importSecurityAlarmProvider), isNotNull);
      },
    );

    test('refuses a dir that is not a deck under the layout', () async {
      final (_, tabs) = build();

      await expectLater(
        tabs.openVersionFromGit(
          FakeForge(repoWith(validDeck)),
          config: config,
          deckDir: 'assets',
          tag: tag,
        ),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
    });

    test('surfaces a missing deck.md at the tag as notFound', () async {
      final (_, tabs) = build();
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          tags: {tag: 'commit-v1'},
          files: {'decks/kwartaalcijfers/other.txt': bytes('x')},
        ),
      );

      await expectLater(
        tabs.openVersionFromGit(
          forge,
          config: config,
          deckDir: 'decks/kwartaalcijfers',
          tag: tag,
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
}
