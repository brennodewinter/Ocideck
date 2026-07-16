import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';

void main() {
  group('GitRepoConfig', () {
    const config = GitRepoConfig(
      baseUrl: 'https://git.example.org',
      owner: 'librekat',
      repo: 'decks',
    );

    test('defaults to gitea on main, untrusted', () {
      expect(config.provider, GitProvider.gitea);
      expect(config.defaultBranch, 'main');
      expect(config.trustedInternal, isFalse);
    });

    test('is only configured with baseUrl, owner and repo', () {
      expect(config.isConfigured, isTrue);
      expect(config.copyWith(owner: '  ').isConfigured, isFalse);
      expect(config.copyWith(repo: '').isConfigured, isFalse);
      expect(config.copyWith(baseUrl: '   ').isConfigured, isFalse);
    });

    test('origin drops any path and keeps a non-default port', () {
      expect(
        const GitRepoConfig(
          baseUrl: 'https://git.example.org:3000/some/path',
          owner: 'o',
          repo: 'r',
        ).origin.toString(),
        'https://git.example.org:3000',
      );
    });

    test('origin is null for an unparseable base url', () {
      expect(
        const GitRepoConfig(baseUrl: 'not a url', owner: 'o', repo: 'r').origin,
        isNull,
      );
    });

    test('round-trips through json', () {
      const rich = GitRepoConfig(
        baseUrl: 'https://gitlab.example.org',
        owner: 'group/sub',
        repo: 'decks',
        provider: GitProvider.gitlab,
        defaultBranch: 'trunk',
        trustedInternal: true,
      );
      expect(GitRepoConfig.fromJson(rich.toJson()), rich);
    });

    test('carries no token: json holds only non-secret fields', () {
      expect(config.toJson().keys, <String>{
        'baseUrl',
        'owner',
        'repo',
        'provider',
        'defaultBranch',
        'trustedInternal',
      });
    });

    test('falls back to gitea rather than throwing on an unknown provider', () {
      expect(
        GitRepoConfig.fromJson({
          'baseUrl': 'https://x',
          'owner': 'o',
          'repo': 'r',
          'provider': 'bitbucket',
        }).provider,
        GitProvider.gitea,
      );
    });

    test('falls back to main on a blank stored default branch', () {
      expect(
        GitRepoConfig.fromJson({
          'baseUrl': 'https://x',
          'owner': 'o',
          'repo': 'r',
          'defaultBranch': '   ',
        }).defaultBranch,
        'main',
      );
    });

    test('equality ignores surrounding whitespace', () {
      expect(config.copyWith(owner: ' librekat '), config);
    });
  });

  group('GitRepoLayout deck names', () {
    test('accepts ordinary names', () {
      for (final name in ['kwartaalcijfers', 'jaarplan-2026', 'a_b.c', 'X1']) {
        expect(GitRepoLayout.isValidDeckName(name), isTrue, reason: name);
      }
    });

    test('rejects traversal, refname traps and empties', () {
      for (final name in [
        '',
        '   ',
        '..',
        'a..b',
        '../etc',
        'a/b',
        '.hidden',
        'trailing.',
        'deck.lock',
        'with space',
        'q?mark',
        'star*',
        'tilde~1',
        'caret^',
        'colon:x',
        'brack[et',
        'at{brace',
      ]) {
        expect(GitRepoLayout.isValidDeckName(name), isFalse, reason: name);
      }
    });

    test('deckDir builds the layout path and refuses a bad name', () {
      expect(GitRepoLayout.deckDir('kwartaalcijfers'), 'decks/kwartaalcijfers');
      expect(GitRepoLayout.deckDir('../escape'), isNull);
    });

    test('deckNameOf inverts deckDir', () {
      expect(
        GitRepoLayout.deckNameOf('decks/kwartaalcijfers'),
        'kwartaalcijfers',
      );
      expect(GitRepoLayout.deckNameOf('decks/a/b'), isNull);
      expect(GitRepoLayout.deckNameOf('assets/x'), isNull);
      expect(GitRepoLayout.deckNameOf('kwartaalcijfers'), isNull);
    });
  });

  group('GitRepoLayout release tags (D9)', () {
    test('namespaces the tag under the deck', () {
      expect(
        GitRepoLayout.releaseTag('kwartaalcijfers', 'v1.0'),
        'decks/kwartaalcijfers/v1.0',
      );
    });

    test('two versions of one deck are distinct refs', () {
      expect(
        GitRepoLayout.releaseTag('jaarplan', 'v1.0'),
        isNot(GitRepoLayout.releaseTag('jaarplan', 'v2.0')),
      );
    });

    test('the same version in two decks is unambiguous', () {
      expect(
        GitRepoLayout.releaseTag('a', 'v1.0'),
        isNot(GitRepoLayout.releaseTag('b', 'v1.0')),
      );
    });

    test('rejects versions that are not vN, or that break refname rules', () {
      for (final v in [
        '',
        '1.0', // no v
        'version1',
        'v', // no digit
        'v1..0',
        'v1.',
        'v1.lock',
        'v1 0',
      ]) {
        expect(GitRepoLayout.releaseTag('deck', v), isNull, reason: v);
      }
    });

    test('rejects a bad deck name before it can reach a ref', () {
      expect(GitRepoLayout.releaseTag('../evil', 'v1.0'), isNull);
    });
  });

  group('GitRepoLayout work branches (D3)', () {
    test('generates a dated branch under the deck', () {
      expect(
        GitRepoLayout.workBranch('kwartaalcijfers', DateTime(2026, 7, 16)),
        'decks/kwartaalcijfers/2026-07-16',
      );
    });

    test('zero-pads so branches sort chronologically', () {
      expect(
        GitRepoLayout.workBranch('d', DateTime(2026, 1, 2)),
        'decks/d/2026-01-02',
      );
    });

    test('refuses a bad deck name', () {
      expect(GitRepoLayout.workBranch('..', DateTime(2026, 7, 16)), isNull);
    });
  });

  group('GitRepoLayout.isSafeRepoPath', () {
    test('accepts paths inside the layout', () {
      for (final path in [
        'decks/kwartaalcijfers/deck.md',
        'assets/3f9a1c8e.png',
        'themes/librekat.css',
      ]) {
        expect(GitRepoLayout.isSafeRepoPath(path), isTrue, reason: path);
      }
    });

    test('accepts a space: a valid git path, and no traversal risk', () {
      // Deliberately allowed. This guard enforces containment, not our naming
      // convention — a repo may legitimately hold `assets/my image.png`, and
      // paths reach git as argv elements without a shell (§10.2).
      expect(GitRepoLayout.isSafeRepoPath('assets/my image.png'), isTrue);
    });

    test('rejects the zip-slip equivalents for a git tree', () {
      for (final path in [
        '',
        '   ',
        '/etc/passwd',
        '../outside',
        'decks/../../outside',
        'decks/../..',
        r'decks\windows',
        '.',
      ]) {
        expect(GitRepoLayout.isSafeRepoPath(path), isFalse, reason: path);
      }
    });

    test('rejects control bytes, including an embedded NUL', () {
      for (final path in ['decks/a\u0000b', 'decks/a\nb', 'decks/a\tb']) {
        expect(GitRepoLayout.isSafeRepoPath(path), isFalse, reason: path);
      }
    });

    test('a traversal that normalises back inside is still accepted', () {
      // decks/a/../b normalises to decks/b — inside the repo, so allowed.
      expect(GitRepoLayout.isSafeRepoPath('decks/a/../b'), isTrue);
    });
  });

  group('GitOrigin', () {
    const config = GitRepoConfig(
      baseUrl: 'https://git.example.org',
      owner: 'librekat',
      repo: 'decks',
    );
    const origin = GitOrigin(
      config: config,
      branch: 'main',
      deckDir: 'decks/kwartaalcijfers',
      baseSha: 'abc123',
    );

    test('derives the deck name from the layout', () {
      expect(origin.deckName, 'kwartaalcijfers');
      expect(origin.copyWith(deckDir: 'elders/deck').deckName, isNull);
    });

    test('matchesRepo detects a repo switch', () {
      expect(origin.matchesRepo(config), isTrue);
      expect(origin.matchesRepo(config.copyWith(repo: 'andere')), isFalse);
      expect(
        origin.matchesRepo(config.copyWith(baseUrl: 'https://elders.example')),
        isFalse,
      );
    });

    test('copyWith advances baseSha without touching the rest', () {
      final moved = origin.copyWith(baseSha: 'def456');
      expect(moved.baseSha, 'def456');
      expect(moved.deckDir, origin.deckDir);
      expect(moved.branch, origin.branch);
      expect(moved.config, origin.config);
    });
  });
}
