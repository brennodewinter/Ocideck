import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/git/deck_search.dart';
import 'package:ocideck/services/git/git_forge.dart';

import 'git_forge_fake.dart';

Uint8List _b(String s) => Uint8List.fromList(utf8.encode(s));

/// A forge whose reads of one deck fail — an unreadable deck.
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

/// Counts what the search actually reads, so a test can prove a shortlist saves
/// reads: it should list no tree and read only the shortlisted decks.
class _CountingForge extends FakeForge {
  _CountingForge(super.repo);

  final readPaths = <String>[];
  int listTreeCalls = 0;

  @override
  Future<Uint8List> readBlob(String ref, String path) {
    readPaths.add(path);
    return super.readBlob(ref, path);
  }

  @override
  Future<List<RepoEntry>> listTree(
    String ref,
    String path, {
    bool recursive = false,
  }) {
    listTreeCalls++;
    return super.listTree(ref, path, recursive: recursive);
  }
}

/// A shortlister that hands back a fixed answer (or `null` to decline), and
/// counts how often it was consulted.
class _FakeShortlister implements DeckShortlister {
  _FakeShortlister(this.result);

  final DeckShortlist? result;
  int calls = 0;

  @override
  Future<DeckShortlist?> shortlist(
    String needle, {
    required bool caseSensitive,
    required String branch,
  }) async {
    calls++;
    return result;
  }
}

/// A shortlister that breaks — the search must survive it, not crash.
class _ThrowingShortlister implements DeckShortlister {
  @override
  Future<DeckShortlist?> shortlist(
    String needle, {
    required bool caseSensitive,
    required String branch,
  }) async => throw StateError('kapotte versneller');
}

void main() {
  const jaarplan = '''
---
title: Jaarplan
author: Aisha
---

# Doelstellingen

We verhogen de dekking naar 80 procent.

---

# Risico's

Een onleesbaar deck is een risico.
''';

  const kwartaal = '''
# Kwartaalcijfers

De dekking staat op 79 procent.
''';

  FakeRepo repo() => FakeRepo(
    branches: {'main': 'c'},
    files: {
      'decks/jaarplan/deck.md': _b(jaarplan),
      'decks/kwartaalcijfers/deck.md': _b(kwartaal),
    },
  );

  DeckSearch search(GitForge forge) => DeckSearch(forge: forge, branch: 'main');

  group('DeckSearch.search', () {
    test('finds a term across every deck', () async {
      final result = await search(FakeForge(repo())).search('dekking');

      expect(result.isComplete, isTrue);
      expect(result.hits.map((h) => h.deck).toSet(), {
        'jaarplan',
        'kwartaalcijfers',
      });
      expect(
        result.hits.first.snippet,
        contains('dekking'),
        reason: 'de regel zelf, niet de hele slide',
      );
    });

    test('attributes a hit to the slide it is on', () async {
      final result = await search(FakeForge(repo())).search('risico');

      // Twee treffers in dezelfde slide: de kop en de regel eronder.
      expect(result.hits, hasLength(2));
      expect(result.hits.every((h) => h.deck == 'jaarplan'), isTrue);
      expect(
        result.hits.map((h) => h.slideIndex).toSet(),
        {1},
        reason: 'de tweede slide, niet de eerste',
      );
      expect(result.hits.first.slideTitle, "Risico's");
    });

    test('a hit in the deck properties is not a slide hit', () async {
      final result = await search(FakeForge(repo())).search('Aisha');

      expect(result.hits, hasLength(1));
      expect(result.hits.single.isFrontMatter, isTrue);
      expect(result.hits.single.slideIndex, -1);
    });

    test('is case-insensitive by default and exact on request', () async {
      final forge = FakeForge(repo());
      expect((await search(forge).search('RISICO')).hits, isNotEmpty);
      expect(
        (await search(forge).search('RISICO', caseSensitive: true)).hits,
        isEmpty,
      );
    });

    test('an empty or whitespace term finds nothing', () async {
      final forge = FakeForge(repo());
      expect((await search(forge).search('')).hits, isEmpty);
      expect((await search(forge).search('   ')).hits, isEmpty);
    });

    test('a --- inside a code block is not a slide boundary', () async {
      // De reden dat dit de splitser van de parser gebruikt en geen
      // split('---'): anders schuift elke treffer ná dit codeblok een slide op
      // en wijst het zoekresultaat de gebruiker naar de verkeerde plek.
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {
            'decks/a/deck.md': _b(
              '# Eerste\n\n```yaml\nfoo: 1\n---\nbar: 2\n```\n\n'
              '---\n\n# Tweede\n\nnaaldterm\n',
            ),
          },
        ),
      );

      final result = await search(forge).search('naaldterm');
      expect(result.hits.single.slideIndex, 1);
      expect(result.hits.single.slideTitle, 'Tweede');
    });

    test('a long line comes back as a window, not in full', () async {
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {
            'decks/a/deck.md': _b('# A\n\n${'x' * 400}naald${'y' * 400}\n'),
          },
        ),
      );

      final snippet = (await search(forge).search('naald')).hits.single.snippet;
      expect(snippet, contains('naald'));
      expect(snippet.length, lessThan(200));
      expect(snippet, startsWith('…'));
      expect(snippet, endsWith('…'));
    });
  });

  group('DeckSearch en onvolledigheid', () {
    test(
      'an unreadable deck shortens the answer but does not kill it',
      () async {
        // Bewust het spiegelbeeld van AssetIndex.unusedAssets, dat juist wél
        // weigert: daar is het antwoord "niemand gebruikt dit" en volgt er een
        // onomkeerbare verwijdering uit. Hier is elke treffer die je toont waar,
        // dus een gedeeltelijk antwoord is beter dan geen antwoord — zolang de
        // gebruiker maar hoort dat het gedeeltelijk is.
        final forge = _BrokenDeckForge(repo(), 'decks/jaarplan');

        final result = await search(forge).search('dekking');
        expect(result.hits.map((h) => h.deck), ['kwartaalcijfers']);
        expect(result.unreadableDecks, ['jaarplan']);
        expect(result.isComplete, isFalse);
      },
    );

    test('truncation is reported, never silent', () async {
      final many = List.generate(50, (i) => 'naald regel $i').join('\n');
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {'decks/a/deck.md': _b('# A\n\n$many\n')},
        ),
      );

      final result = await search(forge).search('naald', maxHits: 10);
      expect(result.hits, hasLength(10));
      expect(result.truncated, isTrue);
      expect(result.isComplete, isFalse);
    });

    test('a list that is exactly full is not called truncated', () async {
      final forge = FakeForge(
        FakeRepo(
          branches: {'main': 'c'},
          files: {'decks/a/deck.md': _b('# A\n\nnaald een\nnaald twee\n')},
        ),
      );

      final result = await search(forge).search('naald', maxHits: 2);
      expect(result.hits, hasLength(2));
      expect(
        result.truncated,
        isFalse,
        reason: 'precies vol is niet hetzelfde als afgekapt',
      );
    });
  });

  group('DeckSearch met een versneller', () {
    test('leest alleen de decks op de shortlist, niet elk deck', () async {
      final forge = _CountingForge(repo());
      final searcher = DeckSearch(
        forge: forge,
        branch: 'main',
        shortlister: _FakeShortlister(
          const DeckShortlist({'decks/kwartaalcijfers'}),
        ),
      );

      final result = await searcher.search('dekking');

      // 'dekking' staat in beide decks, maar de shortlist wees er één aan: alleen
      // die is gelezen, en de treffer komt daarvandaan.
      expect(result.hits.map((h) => h.deck).toSet(), {'kwartaalcijfers'});
      expect(forge.readPaths, ['decks/kwartaalcijfers/deck.md']);
      // De volledige-scan-lijsting is overgeslagen: dat is de besparing.
      expect(forge.listTreeCalls, 0);
      expect(result.coverage, DeckSearchCoverage.exhaustive);
    });

    test('een pad dat geen geldige deckmap is, wordt genegeerd', () async {
      final forge = _CountingForge(repo());
      final searcher = DeckSearch(
        forge: forge,
        branch: 'main',
        shortlister: _FakeShortlister(
          const DeckShortlist({'decks/kwartaalcijfers', 'assets'}),
        ),
      );

      await searcher.search('dekking');
      expect(forge.readPaths, ['decks/kwartaalcijfers/deck.md']);
    });

    test('de dekkingsvlag van de versneller komt door', () async {
      final searcher = DeckSearch(
        forge: FakeForge(repo()),
        branch: 'main',
        shortlister: _FakeShortlister(
          const DeckShortlist({
            'decks/kwartaalcijfers',
          }, coverage: DeckSearchCoverage.bestEffort),
        ),
      );

      final result = await searcher.search('dekking');
      expect(result.coverage, DeckSearchCoverage.bestEffort);
      expect(result.hits, isNotEmpty);
    });

    test('een null-shortlist valt terug op de volledige scan', () async {
      final forge = _CountingForge(repo());
      final shortlister = _FakeShortlister(null);
      final searcher = DeckSearch(
        forge: forge,
        branch: 'main',
        shortlister: shortlister,
      );

      final result = await searcher.search('dekking');

      expect(shortlister.calls, 1);
      // Terugval: alle decks gezien, de lijsting is wél gedaan.
      expect(result.hits.map((h) => h.deck).toSet(), {
        'jaarplan',
        'kwartaalcijfers',
      });
      expect(forge.listTreeCalls, greaterThan(0));
      expect(result.coverage, DeckSearchCoverage.exhaustive);
    });

    test('een kapotte versneller breekt de zoekopdracht niet', () async {
      final searcher = DeckSearch(
        forge: FakeForge(repo()),
        branch: 'main',
        shortlister: _ThrowingShortlister(),
      );

      final result = await searcher.search('dekking');
      // Gewoon de volledige scan, alsof er geen versneller was.
      expect(result.hits.map((h) => h.deck).toSet(), {
        'jaarplan',
        'kwartaalcijfers',
      });
      expect(result.coverage, DeckSearchCoverage.exhaustive);
    });

    test('een lege term raadpleegt de versneller niet', () async {
      final shortlister = _FakeShortlister(
        const DeckShortlist({'decks/kwartaalcijfers'}),
      );
      final searcher = DeckSearch(
        forge: FakeForge(repo()),
        branch: 'main',
        shortlister: shortlister,
      );

      expect((await searcher.search('   ')).hits, isEmpty);
      expect(shortlister.calls, 0);
    });
  });
}
