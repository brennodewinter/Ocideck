import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/asset_destination.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_dest'));
  tearDown(() => tmp.deleteSync(recursive: true));

  File write(String name, String content) {
    final file = File(p.join(tmp.path, name))..writeAsStringSync(content);
    return file;
  }

  Directory dest() =>
      Directory(p.join(tmp.path, 'images'))..createSync(recursive: true);

  group('resolveAssetDestination', () {
    test('gebruikt de naam zelf als die nog vrij is', () async {
      final src = write('foto.png', 'aaa');
      final result = await resolveAssetDestination(dest(), 'foto.png', src);

      expect(result, isNotNull);
      expect(p.basename(result!.file.path), 'foto.png');
      expect(result.alreadyPresent, isFalse);
    });

    test('wijst naar het bestaande bestand als de inhoud gelijk is', () async {
      final destDir = dest();
      final src = write('foto.png', 'zelfde');
      File(p.join(destDir.path, 'foto.png')).writeAsStringSync('zelfde');

      final result = await resolveAssetDestination(destDir, 'foto.png', src);

      expect(p.basename(result!.file.path), 'foto.png');
      expect(result.alreadyPresent, isTrue);
    });

    test('kiest een nieuwe naam als de inhoud verschilt', () async {
      final destDir = dest();
      final src = write('screenshot.png', 'de nieuwe');
      File(p.join(destDir.path, 'screenshot.png')).writeAsStringSync('de oude');

      final result = await resolveAssetDestination(
        destDir,
        'screenshot.png',
        src,
      );

      expect(p.basename(result!.file.path), 'screenshot_2.png');
      expect(result.alreadyPresent, isFalse);
    });

    test('telt door bij meerdere botsingen', () async {
      final destDir = dest();
      final src = write('a.png', 'drie');
      File(p.join(destDir.path, 'a.png')).writeAsStringSync('een');
      File(p.join(destDir.path, 'a_2.png')).writeAsStringSync('twee');

      final result = await resolveAssetDestination(destDir, 'a.png', src);

      expect(p.basename(result!.file.path), 'a_3.png');
    });

    test('herkent gelijke inhoud ook onder een achtervoegsel', () async {
      final destDir = dest();
      final src = write('a.png', 'twee');
      File(p.join(destDir.path, 'a.png')).writeAsStringSync('een');
      File(p.join(destDir.path, 'a_2.png')).writeAsStringSync('twee');

      final result = await resolveAssetDestination(destDir, 'a.png', src);

      expect(p.basename(result!.file.path), 'a_2.png');
      expect(result.alreadyPresent, isTrue);
    });

    test('houdt bestanden zonder extensie heel', () async {
      final destDir = dest();
      final src = write('LICENSE', 'nieuw');
      File(p.join(destDir.path, 'LICENSE')).writeAsStringSync('oud');

      final result = await resolveAssetDestination(destDir, 'LICENSE', src);

      expect(p.basename(result!.file.path), 'LICENSE_2');
    });
  });

  group('filesHaveSameContent', () {
    test('is waar voor identieke inhoud', () async {
      expect(
        await filesHaveSameContent(
          write('a', 'x' * 200),
          write('b', 'x' * 200),
        ),
        isTrue,
      );
    });

    test('is onwaar bij een verschillende lengte', () async {
      expect(
        await filesHaveSameContent(write('a', 'xx'), write('b', 'x')),
        isFalse,
      );
    });

    test('is onwaar bij gelijke lengte maar andere bytes', () async {
      expect(
        await filesHaveSameContent(write('a', 'abc'), write('b', 'abd')),
        isFalse,
      );
    });

    test('vergelijkt voorbij één leesblok', () async {
      final long = 'y' * (128 * 1024);
      expect(
        await filesHaveSameContent(write('a', long), write('b', long)),
        isTrue,
      );
      expect(
        await filesHaveSameContent(
          write('c', long),
          write('d', '${long.substring(0, long.length - 1)}z'),
        ),
        isFalse,
      );
    });

    test('is onwaar als een bestand ontbreekt', () async {
      expect(
        await filesHaveSameContent(
          write('a', 'x'),
          File(p.join(tmp.path, 'weg')),
        ),
        isFalse,
      );
    });

    test('is waar voor twee lege bestanden', () async {
      expect(
        await filesHaveSameContent(write('a', ''), write('b', '')),
        isTrue,
      );
    });
  });
}
