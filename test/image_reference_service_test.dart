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
