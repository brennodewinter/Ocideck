import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/asset_pool.dart';
import 'package:ocideck/services/git/git_forge.dart';

import 'git_forge_fake.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

/// The hash the pool must agree with — computed here independently, so the test
/// pins the actual algorithm rather than whatever the pool happens to do.
String _sha(Uint8List b) => sha256.convert(b).toString();

/// Counts reads, so "fetch once" is an assertion rather than a hope.
class _CountingForge extends FakeForge {
  _CountingForge(super.repo);

  int blobReads = 0;
  int treeListings = 0;

  @override
  Future<Uint8List> readBlob(String ref, String path) {
    blobReads++;
    return super.readBlob(ref, path);
  }

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) {
    treeListings++;
    return super.listTree(ref, path, recursive: recursive);
  }
}

void main() {
  final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a]);
  final pngRef = GitRepoLayout.assetRef(_sha(png), 'png')!;

  setUp(AssetPool.clearCache);
  tearDown(AssetPool.clearCache);

  FakeRepo repoWithPool() => FakeRepo(
    branches: {'main': 'commit-main'},
    files: {
      GitRepoLayout.assetPathOf(pngRef)!: png,
      'decks/kwartaalcijfers/deck.md': _bytes('# Deck'),
    },
  );

  group('AssetPool.refFor', () {
    test('names the asset after the sha-256 of its bytes', () async {
      expect(await AssetPool.refFor(png, name: 'foto.png'), pngRef);
    });

    test(
      'identical bytes yield one reference, whatever the file was called',
      () async {
        // This is the dedup goal (P4) in one assertion: the same picture added
        // twice under different names cannot end up in the pool twice.
        final a = await AssetPool.refFor(png, name: 'kwartaal.png');
        final b = await AssetPool.refFor(png, name: 'heel-andere-naam.png');
        expect(a, b);
      },
    );

    test('different bytes yield different references', () async {
      final other = Uint8List.fromList([...png, 0x00]);
      expect(
        await AssetPool.refFor(png, name: 'a.png'),
        isNot(await AssetPool.refFor(other, name: 'a.png')),
      );
    });

    test('the extension follows the name, the hash does not', () async {
      final a = await AssetPool.refFor(png, name: 'x.png');
      final b = await AssetPool.refFor(png, name: 'x.webp');
      expect(a, endsWith('.png'));
      expect(b, endsWith('.webp'));
      // Same bytes, so the same hash: only the extension differs.
      expect(a!.replaceAll('.png', ''), b!.replaceAll('.webp', ''));
    });

    test('is null without a usable extension', () async {
      for (final name in ['', '   ', 'zonder-extensie', 'trailing.']) {
        expect(await AssetPool.refFor(png, name: name), isNull, reason: name);
      }
    });
  });

  group('AssetPool.extensionOf', () {
    test('lowercases and drops the dot', () {
      expect(AssetPool.extensionOf('Foto.PNG'), 'png');
      expect(AssetPool.extensionOf('a/b/c.JpEg'), 'jpeg');
    });

    test('is null when there is none', () {
      expect(AssetPool.extensionOf('README'), isNull);
      expect(AssetPool.extensionOf('.'), isNull);
    });
  });

  group('AssetPool.resolve', () {
    test('reads the blob behind a reference', () async {
      final pool = AssetPool(forge: FakeForge(repoWithPool()), branch: 'main');
      expect(await pool.resolve(pngRef), png);
    });

    test('fetches once, then serves from cache', () async {
      final forge = _CountingForge(repoWithPool());
      final pool = AssetPool(forge: forge, branch: 'main');

      await pool.resolve(pngRef);
      await pool.resolve(pngRef);
      await pool.resolve(pngRef);

      expect(forge.blobReads, 1);
    });

    test('a second pool shares the cache: one blob, one fetch, ever', () async {
      // Content-addressed, so the cache is safe to share across pools and
      // cannot go stale — the key *is* the content.
      final forge = _CountingForge(repoWithPool());
      await AssetPool(forge: forge, branch: 'main').resolve(pngRef);
      await AssetPool(forge: forge, branch: 'main').resolve(pngRef);

      expect(forge.blobReads, 1);
    });

    test('the cache is bounded: evicting an entry re-fetches it', () async {
      // A static cache without a cap would grow without limit over a long
      // session with many different assets. The LRU cap keeps it bounded.
      // Use 2-byte values to avoid Uint8List's 0-255 masking.
      Uint8List bytesFor(int i) => Uint8List.fromList([i >> 8, i & 0xFF]);
      final forge = _CountingForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {
            for (var i = 0; i < 300; i++)
              GitRepoLayout.assetPathOf(
                GitRepoLayout.assetRef(_sha(bytesFor(i)), 'png')!,
              )!: bytesFor(
                i,
              ),
          },
        ),
      );
      final pool = AssetPool(forge: forge, branch: 'main');

      // Vul de cache met 300 verschillende assets — meer dan de cap.
      for (var i = 0; i < 300; i++) {
        final ref = GitRepoLayout.assetRef(_sha(bytesFor(i)), 'png')!;
        await pool.resolve(ref);
      }

      // De eerste asset (i=0) is geëvicteerd door de LRU-cap. Een nieuwe
      // resolve moet hem opnieuw ophalen: blobReads stijgt.
      final readsBefore = forge.blobReads;
      final ref0 = GitRepoLayout.assetRef(_sha(bytesFor(0)), 'png')!;
      await pool.resolve(ref0);
      expect(
        forge.blobReads,
        greaterThan(readsBefore),
        reason: 'evicted entry must be re-fetched',
      );
    });

    test('refuses a reference that climbs out of the pool', () async {
      final forge = _CountingForge(repoWithPool());
      final pool = AssetPool(forge: forge, branch: 'main');

      await expectLater(
        pool.resolve('repo:assets/../decks/kwartaalcijfers/deck.md'),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
      expect(forge.blobReads, 0, reason: 'must not reach the forge at all');
    });

    test('refuses a non-repo reference', () async {
      final pool = AssetPool(forge: FakeForge(repoWithPool()), branch: 'main');
      for (final ref in ['mem:abc', 'images/foto.png', '']) {
        await expectLater(
          pool.resolve(ref),
          throwsA(isA<GitForgeException>()),
          reason: ref,
        );
      }
    });

    test('refuses a blob whose bytes do not match its hash', () async {
      // A forge is untrusted (P5), so a hash-named path proves nothing until we
      // check it. Without this, a hostile repo could serve anything under a
      // hash — and because the cache is shared across repos, an honest repo
      // would then read the poisoned bytes.
      final lying = FakeRepo(
        branches: {'main': 'c'},
        files: {GitRepoLayout.assetPathOf(pngRef)!: _bytes('heel iets anders')},
      );
      final pool = AssetPool(forge: FakeForge(lying), branch: 'main');

      await expectLater(
        pool.resolve(pngRef),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.kind,
            'kind',
            GitForgeError.malformed,
          ),
        ),
      );
    });

    test(
      'a rejected blob is not cached, so it cannot poison a later read',
      () async {
        final lying = FakeRepo(
          branches: {'main': 'c'},
          files: {GitRepoLayout.assetPathOf(pngRef)!: _bytes('vergif')},
        );
        await expectLater(
          AssetPool(forge: FakeForge(lying), branch: 'main').resolve(pngRef),
          throwsA(isA<GitForgeException>()),
        );

        // Same reference, now from an honest repo: it must read the real bytes.
        final honest = AssetPool(
          forge: FakeForge(repoWithPool()),
          branch: 'main',
        );
        expect(await honest.resolve(pngRef), png);
      },
    );

    test('surfaces a missing blob as notFound', () async {
      final pool = AssetPool(forge: FakeForge(repoWithPool()), branch: 'main');
      final absent = GitRepoLayout.assetRef(_sha(_bytes('elders')), 'png')!;

      await expectLater(
        pool.resolve(absent),
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

  group('AssetPool.existing', () {
    test('reports which references the repo already carries', () async {
      final pool = AssetPool(forge: FakeForge(repoWithPool()), branch: 'main');
      final absent = GitRepoLayout.assetRef(_sha(_bytes('nieuw')), 'png')!;

      expect(await pool.existing([pngRef, absent]), {pngRef});
    });

    test('asks the tree once, not once per reference', () async {
      final forge = _CountingForge(repoWithPool());
      final pool = AssetPool(forge: forge, branch: 'main');
      final refs = [
        pngRef,
        for (var i = 0; i < 20; i++)
          GitRepoLayout.assetRef(_sha(_bytes('n$i')), 'png')!,
      ];

      await pool.existing(refs);
      expect(forge.treeListings, 1);
    });

    test('skips a reference that is not a valid asset', () async {
      final pool = AssetPool(forge: FakeForge(repoWithPool()), branch: 'main');
      expect(
        await pool.existing(['mem:abc', 'repo:assets/../decks/x', pngRef]),
        {pngRef},
      );
    });

    test('an empty ask touches nothing', () async {
      final forge = _CountingForge(repoWithPool());
      expect(
        await AssetPool(forge: forge, branch: 'main').existing([]),
        isEmpty,
      );
      expect(forge.treeListings, 0);
    });

    test('an empty pool reports nothing present', () async {
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {'decks/a/deck.md': _bytes('x')},
        ),
      );
      expect(
        await AssetPool(forge: forge, branch: 'main').existing([pngRef]),
        isEmpty,
      );
    });
  });
}
