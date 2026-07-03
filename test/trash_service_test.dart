import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/trash_service.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory temp;
  late TrashService trash;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('ocideck_trash_');
    trash = TrashService(osHome: () => temp.path);
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  String trashDir() => Platform.isMacOS
      ? p.join(temp.path, '.Trash')
      : p.join(temp.path, '.local', 'share', 'Trash', 'files');

  test('trashTargetsFor pakt de eigen projectmap, ook met (n)-suffix', () {
    expect(TrashService.trashTargetsFor('/decks/Demo/Demo.md'), [
      '/decks/Demo',
    ]);
    expect(TrashService.trashTargetsFor('/decks/Demo (3)/Demo.md'), [
      '/decks/Demo (3)',
    ]);
    // Een map van een ánder deck blijft staan: alleen het bestand gaat mee.
    expect(TrashService.trashTargetsFor('/decks/Presentaties/Demo.md'), [
      '/decks/Presentaties/Demo.md',
    ]);
  });

  test('een los bestand gaat met zijn sidecars de prullenbak in', () async {
    final md = File(p.join(temp.path, 'Demo.md'))..writeAsStringSync('# Demo');
    final ink = File(p.join(temp.path, 'Demo.ink.json'))
      ..writeAsStringSync('{}');
    final blijft = File(p.join(temp.path, 'Anders.md'))
      ..writeAsStringSync('# Anders');

    expect(await trash.moveToTrash(md.path), isTrue);

    expect(md.existsSync(), isFalse);
    expect(ink.existsSync(), isFalse);
    expect(blijft.existsSync(), isTrue);
    expect(File(p.join(trashDir(), 'Demo.md')).existsSync(), isTrue);
    expect(File(p.join(trashDir(), 'Demo.ink.json')).existsSync(), isTrue);
  });

  test('een deck in zijn eigen map verhuist als hele map', () async {
    final dir = Directory(p.join(temp.path, 'Demo (2)'))
      ..createSync(recursive: true);
    final md = File(p.join(dir.path, 'Demo.md'))..writeAsStringSync('# Demo');
    File(p.join(dir.path, 'images', 'x.png'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);

    expect(await trash.moveToTrash(md.path), isTrue);

    expect(dir.existsSync(), isFalse);
    final moved = Directory(p.join(trashDir(), 'Demo (2)'));
    expect(moved.existsSync(), isTrue);
    expect(File(p.join(moved.path, 'images', 'x.png')).existsSync(), isTrue);
  });

  test('naamgelijke items in de prullenbak worden uniek gehouden', () async {
    for (var i = 0; i < 2; i++) {
      final md = File(p.join(temp.path, 'Demo.md'))
        ..writeAsStringSync('# Versie $i');
      expect(await trash.moveToTrash(md.path), isTrue);
    }
    expect(File(p.join(trashDir(), 'Demo.md')).existsSync(), isTrue);
    expect(File(p.join(trashDir(), 'Demo (2).md')).existsSync(), isTrue);
  });

  test('zonder thuismap is de prullenbak niet ondersteund', () {
    final geen = TrashService(osHome: () => null);
    expect(geen.isSupported, isFalse);
  });
}
