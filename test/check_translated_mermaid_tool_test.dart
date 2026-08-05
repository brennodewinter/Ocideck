import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_translated_mermaid.dart';

/// The English mermaid diagram from the User Guide, as `translate_docs` leaves it
/// in a variant: the translator does not touch code blocks, so the labels stay
/// English. This is the exact shape of #1278.
const String _englishDiagram = '''
```mermaid
flowchart LR
    New[New or open a deck] --> Edit[Compose typed slides]
    Edit --> Preview[Live preview]
```
''';

/// The same diagram with its labels translated by hand — node IDs and syntax
/// intact, only the bracketed prose changed.
const String _dutchDiagram = '''
```mermaid
flowchart LR
    New[Nieuw of een deck openen] --> Edit[Getypte dia's samenstellen]
    Edit --> Preview[Live voorbeeld]
```
''';

TranslatedDoc _pair(String base, String variant) => TranslatedDoc(
  basePath: 'docs/USER_GUIDE.md',
  baseMarkdown: base,
  variantPath: 'docs/USER_GUIDE.nl.md',
  variantMarkdown: variant,
);

void main() {
  group('check_translated_mermaid — blokextractie', () {
    test('haalt elk mermaid-blok in documentvolgorde eruit', () {
      const md = '''
# Titel

```mermaid
graph TD
    A[Een] --> B[Twee]
```

Tussentekst.

```mermaid
flowchart LR
    X[Drie]
```
''';
      final blocks = mermaidBlocks(md);
      expect(blocks.length, 2);
      expect(blocks[0], contains('A[Een] --> B[Twee]'));
      expect(blocks[1], contains('X[Drie]'));
    });

    test('negeert niet-mermaid codeblokken', () {
      const md = '''
```dart
final x = 1;
```

```mermaid
graph TD
    A --> B
```
''';
      final blocks = mermaidBlocks(md);
      expect(blocks.length, 1);
      expect(blocks.single, contains('A --> B'));
    });
  });

  group('check_translated_mermaid — variant/basis-koppeling', () {
    test('koppelt NAME.<lang>.md aan NAME.md wanneer de basis bestaat', () {
      final pairs = pairVariantsWithBase([
        'USER_GUIDE.md',
        'USER_GUIDE.nl.md',
        'README.md',
        'README.nl.md',
      ]);
      expect(pairs, hasLength(2));
      expect(
        pairs.map((p) => '${p.variant}->${p.base}'),
        containsAll([
          'USER_GUIDE.nl.md->USER_GUIDE.md',
          'README.nl.md->README.md',
        ]),
      );
    });

    test('een basisdocument met underscores is geen variant', () {
      // FILE_FORMAT.md heeft geen taal-infix; het mag niet als variant tellen.
      final pairs = pairVariantsWithBase(['FILE_FORMAT.md', 'PRIVACY.md']);
      expect(pairs, isEmpty);
    });

    test('een variant zonder basis wordt niet gekoppeld', () {
      final pairs = pairVariantsWithBase(['GHOST.nl.md']);
      expect(pairs, isEmpty);
    });
  });

  group('check_translated_mermaid — detectie', () {
    test('vlagt een Engels diagram in een vertaalde variant (rood)', () {
      final collisions = findUntranslatedMermaid([
        _pair(_englishDiagram, _englishDiagram),
      ]);
      expect(collisions, hasLength(1));
      expect(collisions.single.variantPath, 'docs/USER_GUIDE.nl.md');
      expect(collisions.single.basePath, 'docs/USER_GUIDE.md');
      expect(collisions.single.blockIndex, 0);
    });

    test('een handmatig vertaald diagram is schoon (groen)', () {
      final collisions = findUntranslatedMermaid([
        _pair(_englishDiagram, _dutchDiagram),
      ]);
      expect(collisions, isEmpty);
    });

    test('een witte-lijst-diagram mag byte-identiek zijn', () {
      const neutral = '''
```mermaid
graph LR
    A --> B --> C
```
''';
      final body = mermaidBlocks(neutral).single;
      final collisions = findUntranslatedMermaid(
        [_pair(neutral, neutral)],
        whitelist: {normaliseBlock(body)},
      );
      expect(collisions, isEmpty);
    });

    test('meerdere diagrammen: alleen het onvertaalde blok wordt gemeld', () {
      const base = '$_englishDiagram\n$_englishDiagram';
      // Eerste blok vertaald, tweede nog Engels.
      const variant = '$_dutchDiagram\n$_englishDiagram';
      final collisions = findUntranslatedMermaid([_pair(base, variant)]);
      expect(collisions, hasLength(1));
      expect(collisions.single.blockIndex, 1);
    });

    test('geen mermaid in de basis: niets te melden', () {
      final collisions = findUntranslatedMermaid([
        _pair('# Titel\n\nGewoon tekst.\n', '# Titel\n\nPlain text.\n'),
      ]);
      expect(collisions, isEmpty);
    });
  });

  group('check_translated_mermaid — de echte gebundelde docs', () {
    test('geen enkele vertaalde variant draagt een Engels mermaid-diagram', () {
      // Draait tegen de echte docs op schijf, zodat de fix voor #1278 en elke
      // toekomstige regressie hier valt — niet alleen op synthetische invoer.
      final dir = Directory('docs');
      final names = dir
          .listSync()
          .whereType<File>()
          .map((f) => f.uri.pathSegments.last)
          .toList();
      final docs = [
        for (final pair in pairVariantsWithBase(names))
          TranslatedDoc(
            basePath: 'docs/${pair.base}',
            baseMarkdown: File('docs/${pair.base}').readAsStringSync(),
            variantPath: 'docs/${pair.variant}',
            variantMarkdown: File('docs/${pair.variant}').readAsStringSync(),
          ),
      ];
      final collisions = findUntranslatedMermaid(docs);
      expect(
        collisions,
        isEmpty,
        reason: collisions
            .map((c) => '${c.variantPath} #${c.blockIndex + 1}')
            .join(', '),
      );
    });
  });
}
