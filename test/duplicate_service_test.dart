import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/services/duplicate_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:path/path.dart' as p;

ScanHit _hit(String path, {String? title, int size = 0, DateTime? modified}) {
  return ScanHit(
    path: path,
    fileName: p.basename(path),
    title: title,
    theme: null,
    isOcideckTheme: false,
    size: size,
    modified: modified,
  );
}

void main() {
  final service = DuplicateService();

  test(
    'groupScanHits bundelt byte-identieke bestanden onder één primaire',
    () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_dup_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final inhoud = '---\nmarp: true\n---\n# Zelfde';
      final a = File(p.join(temp.path, 'a.md'))..writeAsStringSync(inhoud);
      final b = File(p.join(temp.path, 'b.md'))..writeAsStringSync(inhoud);
      final c = File(p.join(temp.path, 'c.md'))
        ..writeAsStringSync('---\nmarp: true\n---\n# Anders!');

      final size = a.lengthSync();
      final groups = await service.groupScanHits([
        _hit(a.path, title: 'Zelfde', size: size),
        _hit(b.path, title: 'Zelfde', size: b.lengthSync()),
        _hit(c.path, title: 'Anders', size: c.lengthSync()),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.primary.path, a.path);
      expect(groups.first.identical.map((h) => h.path), [b.path]);
      expect(groups.last.primary.path, c.path);
      expect(groups.last.hasIdenticalCopies, isFalse);
    },
  );

  test(
    'naamgenoten met afwijkende inhoud worden gemarkeerd, niet gebundeld',
    () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_dup_titel_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      // Even groot maar andere inhoud: het grootte-voorfilter moet ze hashen
      // en daarna als verschillend herkennen.
      final a = File(p.join(temp.path, 'een', 'Demo.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nmarp: true\n---\n# A');
      final b = File(p.join(temp.path, 'twee', 'Demo.md'))
        ..createSync(recursive: true)
        ..writeAsStringSync('---\nmarp: true\n---\n# B');

      final groups = await service.groupScanHits([
        _hit(a.path, title: 'Demo', size: a.lengthSync()),
        _hit(b.path, title: 'Demo', size: b.lengthSync()),
      ]);

      expect(groups, hasLength(2));
      expect(groups.first.hasIdenticalCopies, isFalse);
      expect(groups.first.hasTitleConflict, isTrue);
      expect(groups.first.sameTitle.single.path, b.path);
      expect(groups.last.sameTitle.single.path, a.path);
    },
  );

  test('groupScanned werkt op de al ingelezen markdown', () {
    ScannedPresentation pres(String path, String content) =>
        ScannedPresentation(
          path: path,
          fileName: p.basename(path),
          deck: Deck(title: 'T', slides: const []),
          content: content,
        );

    final groups = service.groupScanned([
      pres('/x/a.md', 'inhoud'),
      pres('/y/a.md', 'inhoud'),
      pres('/z/b.md', 'anders'),
    ]);

    expect(groups, hasLength(2));
    expect(groups.first.identical.single.path, '/y/a.md');
    // Alle drie heten "T": de twee primaire vermeldingen botsen qua titel.
    expect(groups.first.hasTitleConflict, isTrue);
  });

  test(
    'findIdenticalCopy vindt een kopie via het grootte-voorfilter',
    () async {
      final temp = await Directory.systemTemp.createTemp('ocideck_dup_find_');
      addTearDown(() async {
        if (await temp.exists()) await temp.delete(recursive: true);
      });

      final inhoud = '---\nmarp: true\n---\n# Kopie';
      final opened = File(p.join(temp.path, 'open.md'))
        ..writeAsStringSync(inhoud);
      final copy = File(p.join(temp.path, 'kopie.md'))
        ..writeAsStringSync(inhoud);
      final other = File(p.join(temp.path, 'anders.md'))
        ..writeAsStringSync('---\nmarp: true\n---\n# Nee');

      expect(
        await service.findIdenticalCopy(opened.path, [
          opened.path, // zichzelf overslaan
          other.path,
          p.join(temp.path, 'bestaat-niet.md'),
          copy.path,
        ]),
        copy.path,
      );
      expect(
        await service.findIdenticalCopy(opened.path, [other.path]),
        isNull,
      );
    },
  );

  test('contentHash is stabiel over bytes', () {
    expect(
      DuplicateService.contentHash(utf8.encode('x')),
      DuplicateService.contentHash(utf8.encode('x')),
    );
    expect(
      DuplicateService.contentHash(utf8.encode('x')),
      isNot(DuplicateService.contentHash(utf8.encode('y'))),
    );
  });
}
