import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/git_forge.dart';
import 'package:ocideck/services/git/gitea_forge.dart';

import 'git_forge_fake.dart';

/// The contract every [GitForge] must honour, stated once and run against every
/// implementation. Per §12 this is Phase 0's actual deliverable: it de-risks the
/// interface before a second implementation exists, and the same idea returns in
/// Phase 3, where `NativeGitMirror` must satisfy the `DeckMirror` contract that
/// `DraftMirror` already does.
///
/// Anything asserted here is behaviour a *caller* may rely on regardless of
/// which forge is behind it. Provider-specific details (URL shapes, auth header
/// spelling, JSON quirks) belong in that adapter's own test, not here.
void runGitForgeContract(String name, GitForge Function(FakeRepo) build) {
  group('$name honours the GitForge contract', () {
    late FakeRepo repo;
    late GitForge forge;

    setUp(() {
      repo = FakeRepo.sample();
      forge = build(repo);
    });

    group('headSha', () {
      test('returns the commit a branch points at', () async {
        expect(await forge.headSha('main'), 'commit-main');
      });

      test('resolves a slash-bearing work branch (D3)', () async {
        expect(
          await forge.headSha('decks/kwartaalcijfers/2026-07-16'),
          'commit-work',
        );
      });

      test('reports notFound for an unknown branch', () async {
        await expectLater(
          forge.headSha('geen-branch'),
          throwsA(
            isA<GitForgeException>().having(
              (e) => e.kind,
              'kind',
              GitForgeError.notFound,
            ),
          ),
        );
      });

      test('refuses a malformed ref rather than asking the server', () async {
        for (final ref in ['', '  ', '-force', 'a..b']) {
          await expectLater(
            forge.headSha(ref),
            throwsA(
              isA<GitForgeException>().having(
                (e) => e.kind,
                'kind',
                GitForgeError.malformed,
              ),
            ),
            reason: ref,
          );
        }
      });
    });

    group('listTree', () {
      test('lists one level of the repo root', () async {
        final entries = await forge.listTree('main', '');
        expect(entries.map((e) => e.path), ['assets', 'decks', 'themes']);
        expect(entries.map((e) => e.type), everyElement(RepoEntryType.dir));
      });

      test('lists a deck directory, files and subdirs alike', () async {
        final entries = await forge.listTree('main', 'decks/kwartaalcijfers');
        expect(entries.map((e) => e.path), [
          'decks/kwartaalcijfers/deck.md',
          'decks/kwartaalcijfers/deck.notes',
          'decks/kwartaalcijfers/sub',
        ]);
        expect(
          entries.firstWhere((e) => e.name == 'deck.md').type,
          RepoEntryType.file,
        );
        expect(
          entries.firstWhere((e) => e.name == 'sub').type,
          RepoEntryType.dir,
        );
      });

      test('reports the size of a blob', () async {
        final entries = await forge.listTree('main', 'decks/jaarplan');
        final deck = entries.firstWhere((e) => e.name == 'deck.md');
        expect(deck.size, repo.files['decks/jaarplan/deck.md']!.length);
      });

      test('recursive reaches nested paths', () async {
        final entries = await forge.listTree(
          'main',
          'decks/kwartaalcijfers',
          recursive: true,
        );
        expect(
          entries.map((e) => e.path),
          contains('decks/kwartaalcijfers/sub/nested.md'),
        );
      });

      test('recursive stays inside the requested directory', () async {
        final entries = await forge.listTree(
          'main',
          'decks/kwartaalcijfers',
          recursive: true,
        );
        expect(
          entries.map((e) => e.path),
          everyElement(startsWith('decks/kwartaalcijfers/')),
        );
      });

      test('an empty path means the whole repo', () async {
        final entries = await forge.listTree('main', '', recursive: true);
        expect(entries.map((e) => e.path), contains('assets/3f9a1c8e.png'));
        expect(entries.map((e) => e.path), contains('decks/jaarplan/deck.md'));
      });

      test('a directory with no match yields nothing, not an error', () async {
        expect(await forge.listTree('main', 'decks/bestaat-niet'), isEmpty);
      });

      test('refuses a path that escapes the repo', () async {
        for (final path in ['../etc', 'decks/../../outside', '/absolute']) {
          await expectLater(
            forge.listTree('main', path),
            throwsA(
              isA<GitForgeException>().having(
                (e) => e.kind,
                'kind',
                GitForgeError.malformed,
              ),
            ),
            reason: path,
          );
        }
      });

      test('every returned path is safe by construction', () async {
        final entries = await forge.listTree('main', '', recursive: true);
        expect(entries, isNotEmpty);
        for (final entry in entries) {
          expect(
            GitRepoLayout.isSafeRepoPath(entry.path),
            isTrue,
            reason: entry.path,
          );
        }
      });
    });

    group('readBlob', () {
      test('returns the bytes verbatim, binary included', () async {
        final bytes = await forge.readBlob('main', 'assets/3f9a1c8e.png');
        expect(bytes, repo.files['assets/3f9a1c8e.png']);
      });

      test('round-trips utf-8 text', () async {
        final bytes = await forge.readBlob(
          'main',
          'decks/kwartaalcijfers/deck.md',
        );
        expect(utf8.decode(bytes), '# Kwartaalcijfers');
      });

      test('reports notFound for a missing blob', () async {
        await expectLater(
          forge.readBlob('main', 'decks/kwartaalcijfers/bestaat-niet.md'),
          throwsA(
            isA<GitForgeException>().having(
              (e) => e.kind,
              'kind',
              GitForgeError.notFound,
            ),
          ),
        );
      });

      test('refuses a path that escapes the repo', () async {
        await expectLater(
          forge.readBlob('main', '../../etc/passwd'),
          throwsA(
            isA<GitForgeException>().having(
              (e) => e.kind,
              'kind',
              GitForgeError.malformed,
            ),
          ),
        );
      });
    });
  });
}

void main() {
  // The reference: no transport, no JSON — the plainest statement of the rules.
  runGitForgeContract('FakeForge', FakeForge.new);

  // The real adapter, over a transport that speaks Gitea's JSON shapes against
  // the same in-memory repo. This is what makes the suite worth having: if
  // GiteaForge's parsing drifts from the reference, these fail.
  runGitForgeContract(
    'GiteaForge',
    (repo) => GiteaForge(
      config: const GitRepoConfig(
        baseUrl: 'https://git.example.org',
        owner: 'librekat',
        repo: 'decks',
      ),
      token: 'pat123',
      transport: FakeGiteaTransport(repo),
    ),
  );
}
