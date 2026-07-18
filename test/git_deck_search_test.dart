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
}
