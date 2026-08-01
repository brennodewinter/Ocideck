import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:ocideck/services/image_reference_service.dart';

void main() {
  late Directory tmp;
  final service = ImageReferenceService();

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_refs'));
  tearDown(() => tmp.deleteSync(recursive: true));

  String write(String relativePath, String content) {
    final file = File(p.join(tmp.path, relativePath));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
    return file.path;
  }

  group('findDeckFiles', () {
    test('finds .md files recursively but skips asset directories', () async {
      final deck = write('presentaties/deck.md', '# Deck');
      write('presentaties/images/notitie.md', 'hoort niet mee');
      write('presentaties/.verborgen/geheim.md', 'hoort niet mee');

      final found = await service.findDeckFiles([tmp.path]);

      expect(found, [p.normalize(deck)]);
    });

    test('deduplicates hits from overlapping search paths', () async {
      final deck = write('project/deck.md', '# Deck');

      final found = await service.findDeckFiles([
        tmp.path,
        p.join(tmp.path, 'project'),
      ]);

      expect(found, [p.normalize(deck)]);
    });

    test('descends deeper than four levels', () async {
      // Zes mappen diep — voorbij de oude limiet van vier.
      final deck = write('a/b/c/d/e/f/diep.md', '# Diep');

      final found = await service.findDeckFiles([tmp.path]);

      expect(found, [p.normalize(deck)]);
    });
  });

  group('countReferences', () {
    test('resolves relative paths against the deck file directory', () async {
      final img = p.join(tmp.path, 'project', 'images', 'foto.png');
      final deck = write(
        'project/deck.md',
        '![bg left:50%](images/foto.png)\n\n---\n\n![](images/foto.png)\n',
      );

      final counts = await service.countReferences([deck], [img]);

      expect(counts[p.normalize(img)], 2);
    });

    test('ignores other images and web URLs', () async {
      final img = p.join(tmp.path, 'project', 'images', 'foto.png');
      final deck = write(
        'project/deck.md',
        '![](images/anders.png)\n![](https://example.com/foto.png)\n',
      );

      expect(await service.countReferences([deck], [img]), isEmpty);
    });

    test(
      'counts each reference against many targets in one pass (#1052)',
      () async {
        // Veel doelen, veel verwijzingen: de telling gebruikt een canonieke
        // lookup-map, geen vergelijking van elke verwijzing tegen elk doel.
        final a = p.join(tmp.path, 'project', 'images', 'a.png');
        final b = p.join(tmp.path, 'project', 'images', 'b.png');
        final ongebruikt = [
          for (var i = 0; i < 50; i++)
            p.join(tmp.path, 'project', 'images', 'x$i.png'),
        ];
        final deck = write(
          'project/deck.md',
          '![](images/a.png)\n![](images/a.png)\n![](images/b.png)\n',
        );

        final counts = await service.countReferences(
          [deck],
          [a, b, ...ongebruikt],
        );

        expect(counts[a], 2);
        expect(counts[b], 1);
        // Geen van de vijftig ongebruikte doelen mag een telling krijgen.
        expect(counts.keys, unorderedEquals([a, b]));
      },
    );
  });

  group('replaceReferencesMulti', () {
    test(
      'rewrites every target in a single pass, relative POSIX kept',
      () async {
        final keepA = p.join(tmp.path, 'project', 'images', 'keepA.png');
        final keepB = p.join(tmp.path, 'project', 'images', 'keepB.png');
        final fromA = p.join(tmp.path, 'project', 'images', 'copyA.png');
        final fromB = p.join(tmp.path, 'project', 'images', 'copyB.png');
        final deck = write(
          'project/deck.md',
          '![één](images/copyA.png)\n![twee](images/copyB.png)\n'
              '![blijft](images/ongemoeid.png)\n',
        );

        final changed = await service.replaceReferencesMulti(deck, {
          fromA: keepA,
          fromB: keepB,
        });

        expect(changed, isTrue);
        final content = File(deck).readAsStringSync();
        // Beide doelen omgezet, relatief en met '/' (portabel), in één schrijf.
        expect(content, contains('![één](images/keepA.png)'));
        expect(content, contains('![twee](images/keepB.png)'));
        // Wat niet in de map staat, blijft byte-voor-byte gelijk.
        expect(content, contains('![blijft](images/ongemoeid.png)'));
      },
    );

    test('does not write and returns false when nothing matches', () async {
      final deck = write('project/deck.md', '![](images/ongemoeid.png)\n');
      final before = File(deck).lastModifiedSync();

      final changed = await service.replaceReferencesMulti(deck, {
        p.join(tmp.path, 'project', 'images', 'afwezig.png'): p.join(
          tmp.path,
          'project',
          'images',
          'keep.png',
        ),
      });

      expect(changed, isFalse);
      expect(File(deck).lastModifiedSync(), before, reason: 'niet herschreven');
      expect(File(deck).readAsStringSync(), '![](images/ongemoeid.png)\n');
    });

    test('one call handles all targets across many decks (#1052)', () async {
      // Twee decks, één replacement-map met veel doelen: elk deck wordt met één
      // aanroep volledig omgezet — O(decks + doelen), niet het product.
      final keep = p.join(tmp.path, 'project', 'images', 'keep.png');
      final replacements = <String, String>{
        for (var i = 0; i < 40; i++)
          p.join(tmp.path, 'project', 'images', 'c$i.png'): keep,
      };
      final deck1 = write('project/d1.md', '![](images/c0.png)\n');
      final deck2 = write('project/d2.md', '![](images/c39.png)\n');
      final deck3 = write('project/d3.md', '![](images/geen.png)\n');

      var writes = 0;
      for (final deck in [deck1, deck2, deck3]) {
        if (await service.replaceReferencesMulti(deck, replacements)) writes++;
      }

      // Precies de twee decks met een treffer zijn (elk één keer) herschreven.
      expect(writes, 2);
      expect(File(deck1).readAsStringSync(), '![](images/keep.png)\n');
      expect(File(deck2).readAsStringSync(), '![](images/keep.png)\n');
      expect(File(deck3).readAsStringSync(), '![](images/geen.png)\n');
    });
  });

  group('referencingFiles', () {
    test('reports per deck file how often the image is referenced', () async {
      final img = p.join(tmp.path, 'project', 'images', 'foto.png');
      final twice = write(
        'project/deck.md',
        '![](images/foto.png)\n---\n![bg](images/foto.png)\n',
      );
      final never = write('project/anders.md', '![](images/anders.png)\n');

      final result = await service.referencingFiles([twice, never], img);

      expect(result, {twice: 2});
    });
  });

  group('replaceReferences', () {
    test('rewrites relative references and keeps them relative', () async {
      final from = p.join(tmp.path, 'project', 'images', 'kopie.png');
      final to = p.join(tmp.path, 'project', 'images', 'origineel.png');
      final deck = write(
        'project/deck.md',
        '# Titel\n\n![bg right:40%](images/kopie.png)\n\nTekst blijft staan.\n',
      );

      final changed = await service.replaceReferences(deck, from, to);

      expect(changed, isTrue);
      expect(
        File(deck).readAsStringSync(),
        '# Titel\n\n![bg right:40%](images/origineel.png)\n\nTekst blijft staan.\n',
      );
    });

    test('rewrites absolute references to the absolute kept path', () async {
      final from = p.join(tmp.path, 'elders', 'kopie.png');
      final to = p.join(tmp.path, 'elders', 'origineel.png');
      final deck = write('project/deck.md', '![]($from)\n');

      final changed = await service.replaceReferences(deck, from, to);

      expect(changed, isTrue);
      expect(File(deck).readAsStringSync(), '![]($to)\n');
    });

    test('leaves the file untouched when nothing matches', () async {
      final from = p.join(tmp.path, 'project', 'images', 'kopie.png');
      final to = p.join(tmp.path, 'project', 'images', 'origineel.png');
      final deck = write('project/deck.md', '![](images/anders.png)\n');
      final before = File(deck).lastModifiedSync();

      final changed = await service.replaceReferences(deck, from, to);

      expect(changed, isFalse);
      expect(File(deck).readAsStringSync(), '![](images/anders.png)\n');
      expect(File(deck).lastModifiedSync(), before);
    });

    test(
      'uses an absolute path when the kept file lies outside the project',
      () async {
        final from = p.join(tmp.path, 'project', 'images', 'kopie.png');
        final to = p.join(tmp.path, 'elders', 'origineel.png');
        final deck = write('project/deck.md', '![](images/kopie.png)\n');

        final changed = await service.replaceReferences(deck, from, to);

        expect(changed, isTrue);
        expect(File(deck).readAsStringSync(), '![]($to)\n');
      },
    );
  });
}
