import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/image_library_scanner.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_imgscan'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  File makeImg(String relative) {
    final f = File(p.join(tmp.path, relative));
    f.parent.createSync(recursive: true);
    f.writeAsBytesSync(const [0x89, 0x50, 0x4e, 0x47]);
    return f;
  }

  test('caps the number of files and reports truncation', () async {
    for (var i = 0; i < 10; i++) {
      makeImg('pic$i.png');
    }
    final result = await ImageLibraryScanner.scan([tmp.path], maxFiles: 5);
    expect(result.paths, hasLength(5));
    expect(result.truncated, isTrue);
  });

  test('honours the depth ceiling', () async {
    // Een afbeelding drie niveaus diep; met maxDepth 1 wordt hij niet bereikt.
    makeImg(p.join('a', 'b', 'c', 'deep.png'));
    makeImg('shallow.png');

    final shallow = await ImageLibraryScanner.scan([tmp.path], maxDepth: 1);
    expect(shallow.paths.map(p.basename), contains('shallow.png'));
    expect(
      shallow.paths.map(p.basename),
      isNot(contains('deep.png')),
      reason:
          'onder de dieptegrens hoort de diepe afbeelding niet mee te komen',
    );

    // Ruime diepte vindt hem wél.
    final deep = await ImageLibraryScanner.scan([tmp.path], maxDepth: 8);
    expect(deep.paths.map(p.basename), contains('deep.png'));
  });

  test('overlapping search paths yield each image once', () async {
    final sub = Directory(p.join(tmp.path, 'sub'))..createSync();
    makeImg(p.join('sub', 'one.png'));

    // Zowel de wortel als de submap doorzoeken: `sub/one.png` valt onder beide.
    final result = await ImageLibraryScanner.scan([tmp.path, sub.path]);
    final ones = result.paths.where((x) => p.basename(x) == 'one.png');
    expect(ones, hasLength(1), reason: 'een overlappend pad mag niet dubbel');
  });

  test('a cancelled scan stops and returns nothing', () async {
    for (var i = 0; i < 10; i++) {
      makeImg('pic$i.png');
    }
    // Meteen annuleren: er komt niets uit, en zeker geen volledige lijst.
    final result = await ImageLibraryScanner.scan([
      tmp.path,
    ], isCancelled: () => true);
    expect(result.paths, isEmpty);
    expect(result.truncated, isFalse);
  });

  test('non-image files are ignored and results are newest first', () async {
    makeImg('a.png');
    File(p.join(tmp.path, 'notes.txt')).writeAsStringSync('geen afbeelding');
    // Maak een tweede, nieuwere afbeelding.
    final newer = makeImg('b.png');
    newer.setLastModifiedSync(DateTime.now().add(const Duration(hours: 1)));

    final result = await ImageLibraryScanner.scan([tmp.path]);
    expect(result.paths.map(p.basename), ['b.png', 'a.png']);
    expect(result.paths.map(p.basename), isNot(contains('notes.txt')));
  });

  test(
    'ontbrekende wortels zonder treffers → failed + unreachableRoots',
    () async {
      final missing = p.join(tmp.path, 'bestaat-niet');
      final result = await ImageLibraryScanner.scan([missing]);
      expect(result.paths, isEmpty);
      expect(result.failed, isTrue);
      expect(result.unreachableRoots, [missing]);
    },
  );

  test('ontbrekende wortel naast een gevulde blijft niet failed', () async {
    makeImg('ok.png');
    final missing = p.join(tmp.path, 'weg');
    final result = await ImageLibraryScanner.scan([missing, tmp.path]);
    expect(result.paths.map(p.basename), contains('ok.png'));
    expect(result.failed, isFalse);
    expect(result.unreachableRoots, [missing]);
  });
}
