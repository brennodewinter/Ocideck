import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/git_settings.dart';
import 'package:ocideck/services/git/asset_index.dart';
import 'package:ocideck/services/git/git_forge.dart';

import 'git_forge_fake.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));
String _ref(String seed, [String ext = 'png']) =>
    GitRepoLayout.assetRef(sha256.convert(_b(seed)).toString(), ext)!;

/// A forge whose deck.md reads fail — to prove an unreadable deck cannot make an
/// asset look unused.
class _BrokenDeckForge extends FakeForge {
  _BrokenDeckForge(super.repo, this.brokenDeckDir);

  final String brokenDeckDir;

  @override
  Future<Uint8List> readBlob(String ref, String path) {
    if (path.startsWith('$brokenDeckDir/')) {
      throw const GitForgeException(GitForgeError.server, 'stuk');
    }
    return super.readBlob(ref, path);
  }
}

/// A forge where a release tag holds *different* deck content than the branch —
/// the situation the release scan exists for. The plain [FakeRepo] shares one
/// file tree, so a tag would otherwise read back the current text and the whole
/// question would be invisible.
class _TaggedForge extends FakeForge {
  _TaggedForge(super.repo, this.atTag);

  /// tag → deck.md content at that tag.
  final Map<String, String> atTag;

  @override
  Future<Uint8List> readBlob(String ref, String path) async {
    final markdown = atTag[ref.trim()];
    if (markdown != null) return _b(markdown);
    return super.readBlob(ref, path);
  }
}

/// A forge whose reads at a given tag fail — an unreadable released version.
class _BrokenTagForge extends FakeForge {
  _BrokenTagForge(super.repo, this.brokenTag);

  final String brokenTag;

  @override
  Future<Uint8List> readBlob(String ref, String path) {
    if (ref.trim() == brokenTag) {
      throw const GitForgeException(GitForgeError.server, 'stuk');
    }
    return super.readBlob(ref, path);
  }
}

void main() {
  final shared = _ref('gedeelde-afbeelding');
  final onlyJaarplan = _ref('alleen-jaarplan');
  final unused = _ref('niemand-gebruikt-mij');

  FakeRepo repo() => FakeRepo(
    branches: {'main': 'c'},
    files: {
      'decks/kwartaalcijfers/deck.md': _b('# Q\n\n![]($shared)'),
      'decks/jaarplan/deck.md': _b('# J\n\n![]($shared)\n![]($onlyJaarplan)'),
      GitRepoLayout.assetPathOf(shared)!: _b('gedeelde-afbeelding'),
      GitRepoLayout.assetPathOf(onlyJaarplan)!: _b('alleen-jaarplan'),
      GitRepoLayout.assetPathOf(unused)!: _b('niemand-gebruikt-mij'),
    },
  );

  AssetIndex index(GitForge forge) => AssetIndex(forge: forge, branch: 'main');

  group('AssetIndex.referencesIn', () {
    test('finds a reference anywhere in the text', () {
      expect(
        AssetIndex.referencesIn('bla ![x]($shared) bla\n<!-- $unused -->'),
        {shared, unused},
      );
    });

    test('reports one reference once, however often it appears', () {
      expect(AssetIndex.referencesIn('$shared $shared $shared'), {shared});
    });

    test('ignores the other schemes and a malformed pool path', () {
      expect(
        AssetIndex.referencesIn(
          'mem:abc asset:x.png images/y.png '
          'repo:assets/tekort.png repo:decks/a/deck.md',
        ),
        isEmpty,
      );
    });
  });

  group('AssetIndex.build', () {
    test('maps every pool asset to the decks that use it', () async {
      final snapshot = await index(FakeForge(repo())).build();

      expect(snapshot.isComplete, isTrue);
      expect(snapshot.assets.map((a) => a.reference).toSet(), {
        shared,
        onlyJaarplan,
        unused,
      });
      expect(snapshot.assets.firstWhere((a) => a.reference == shared).decks, [
        'jaarplan',
        'kwartaalcijfers',
      ]);
      expect(
        snapshot.assets.firstWhere((a) => a.reference == onlyJaarplan).decks,
        ['jaarplan'],
      );
      expect(
        snapshot.assets.firstWhere((a) => a.reference == unused).decks,
        isEmpty,
      );
    });

    test('carries the blob size through', () async {
      final snapshot = await index(FakeForge(repo())).build();
      final asset = snapshot.assets.firstWhere((a) => a.reference == shared);
      expect(asset.size, 'gedeelde-afbeelding'.length);
    });

    test('a stray non-pool file under assets/ is not an asset', () async {
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {
            'decks/a/deck.md': _b('# A'),
            'assets/README.md': _b('handmatig neergezet'),
          },
        ),
      );
      expect((await index(forge).build()).assets, isEmpty);
    });
  });

  group('AssetIndex.decksUsing', () {
    test('answers the image-search question', () async {
      expect(await index(FakeForge(repo())).decksUsing(shared), [
        'jaarplan',
        'kwartaalcijfers',
      ]);
    });

    test('is empty for an unused or unknown asset', () async {
      final idx = index(FakeForge(repo()));
      expect(await idx.decksUsing(unused), isEmpty);
      expect(await idx.decksUsing(_ref('bestaat-niet')), isEmpty);
    });
  });

  group('AssetIndex.unusedAssets', () {
    test('lists only what no deck references', () async {
      final orphans = await index(FakeForge(repo())).unusedAssets();
      expect(orphans.map((a) => a.reference), [unused]);
    });

    test('refuses to answer when a deck could not be read', () async {
      // The expensive mistake this guards: jaarplan is the only user of
      // onlyJaarplan. If its deck.md is skipped silently, that asset looks
      // unused — and the user deletes it. Deleting is irreversible, so an
      // incomplete index must not produce a delete list at all (P2).
      final forge = _BrokenDeckForge(repo(), 'decks/jaarplan');

      final snapshot = await index(forge).build();
      expect(snapshot.isComplete, isFalse);
      expect(snapshot.unreadableDecks, ['jaarplan']);
      // Note what the incomplete snapshot *would* have claimed:
      expect(
        snapshot.assets.firstWhere((a) => a.reference == onlyJaarplan).isUnused,
        isTrue,
      );

      // …which is exactly why this refuses rather than reporting it.
      await expectLater(
        index(forge).unusedAssets(),
        throwsA(
          isA<GitForgeException>().having(
            (e) => e.message,
            'message',
            contains('jaarplan'),
          ),
        ),
      );
    });

    test('image search still works on an incomplete index', () async {
      // A partial answer is fine here: whoever is listed does use it. Only the
      // *absence* of users is the unprovable claim.
      final forge = _BrokenDeckForge(repo(), 'decks/jaarplan');
      expect(await index(forge).decksUsing(shared), ['kwartaalcijfers']);
    });
  });

  group('AssetIndex en uitgebrachte versies', () {
    // De afbeelding staat niet meer in de huidige tekst, maar wél in de versie
    // die vorig kwartaal is gepresenteerd. Weggooien zou die versie breken.
    final onlyInRelease = _ref('alleen-in-een-release');

    FakeRepo repoWithRelease() => FakeRepo(
      branches: {'main': 'c'},
      tags: {'decks/kwartaalcijfers/v1.0': 'c-oud'},
      files: {
        // De huidige tekst verwijst er niet meer naar.
        'decks/kwartaalcijfers/deck.md': _b('# Q zonder plaatje'),
        GitRepoLayout.assetPathOf(onlyInRelease)!: _b('alleen-in-een-release'),
      },
    );

    test(
      'een asset die alleen een release nog gebruikt is niet ongebruikt',
      () async {
        final forge = _TaggedForge(repoWithRelease(), {
          'decks/kwartaalcijfers/v1.0':
              '# Q vorig kwartaal\n\n![]($onlyInRelease)',
        });

        final unused = await index(forge).unusedAssets();
        expect(
          unused.map((a) => a.reference),
          isNot(contains(onlyInRelease)),
          reason: 'hij zit nog in een uitgebrachte versie',
        );

        final snapshot = await index(forge).build(includeReleases: true);
        final usage = snapshot.assets.firstWhere(
          (a) => a.reference == onlyInRelease,
        );
        expect(usage.decks, isEmpty, reason: 'niet meer in de huidige tekst');
        expect(usage.releases, ['decks/kwartaalcijfers/v1.0']);
        expect(usage.isUnused, isFalse);
      },
    );

    test('zonder de release-ronde zou hij er wél als ongebruikt uitzien', () {
      // Legt vast waaróm unusedAssets() de ronde altijd doet: op een index
      // zonder releases is precies deze asset een verkeerde kandidaat.
      final forge = _TaggedForge(repoWithRelease(), {
        'decks/kwartaalcijfers/v1.0':
            '# Q vorig kwartaal\n\n![]($onlyInRelease)',
      });
      expect(() async {
        final snapshot = await index(forge).build();
        final usage = snapshot.assets.firstWhere(
          (a) => a.reference == onlyInRelease,
        );
        expect(snapshot.scannedReleases, isFalse);
        expect(usage.isUnused, isTrue);
      }, returnsNormally);
    });

    test('een onleesbare release blokkeert het oordeel net zo hard', () async {
      // Fail-closed (P2): een versie die je niet kunt lezen, kan de enige
      // gebruiker zijn. Dan is "ongebruikt" een onbewezen bewering.
      final forge = _BrokenTagForge(
        repoWithRelease(),
        'decks/kwartaalcijfers/v1.0',
      );

      await expectLater(
        index(forge).unusedAssets(),
        throwsA(isA<GitForgeException>()),
      );
      // Beeldzoeken blijft wél werken: dat mag een gedeeltelijk antwoord geven.
      expect(await index(forge).decksUsing(onlyInRelease), isEmpty);
    });
  });
}
