import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/asset_staging.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocideck_staging_test');
    AssetStaging.overrideRootForTest(p.join(tmp.path, 'ocideck_staging'));
  });

  tearDown(() {
    AssetStaging.overrideRootForTest(null);
    tmp.deleteSync(recursive: true);
  });

  File source(String name, String content) {
    final file = File(p.join(tmp.path, name));
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(content);
  }

  group('stage', () {
    test('kopieert de bron naar de subdir van de wachtkamer', () async {
      final src = source('foto.png', 'bytes');

      final staged = await AssetStaging.stage(src.path, subdir: 'images');

      expect(staged, isNotNull);
      expect(p.basename(staged!), 'foto.png');
      expect(p.basename(p.dirname(staged)), 'images');
      expect(File(staged).readAsStringSync(), 'bytes');
    });

    test('laat de kopie los van de bron staan', () async {
      final src = source('foto.png', 'bytes');
      final staged = await AssetStaging.stage(src.path, subdir: 'images');

      src.deleteSync();

      expect(File(staged!).existsSync(), isTrue);
    });

    test('houdt video en afbeeldingen in eigen submappen', () async {
      final clip = await AssetStaging.stage(
        source('clip.mp4', 'v').path,
        subdir: 'media',
      );

      expect(p.basename(p.dirname(clip!)), 'media');
    });

    test('geeft null voor een bron die niet bestaat', () async {
      final staged = await AssetStaging.stage(
        p.join(tmp.path, 'weg.png'),
        subdir: 'images',
      );

      expect(staged, isNull);
    });

    test('hergebruikt de kopie bij identieke inhoud', () async {
      final first = await AssetStaging.stage(
        source('a.png', 'zelfde').path,
        subdir: 'images',
      );
      final second = await AssetStaging.stage(
        source('kopie/a.png', 'zelfde').path,
        subdir: 'images',
      );

      expect(second, first);
    });

    test('wijkt uit bij dezelfde naam met andere inhoud', () async {
      final first = await AssetStaging.stage(
        source('a.png', 'een').path,
        subdir: 'images',
      );
      final second = await AssetStaging.stage(
        source('anders/a.png', 'twee').path,
        subdir: 'images',
      );

      expect(second, isNot(first));
      expect(File(second!).readAsStringSync(), 'twee');
      expect(File(first!).readAsStringSync(), 'een');
    });

    test('geeft null zonder wachtkamer', () async {
      AssetStaging.overrideRootForTest(null);

      expect(
        await AssetStaging.stage(
          source('a.png', 'x').path,
          subdir: 'images',
        ),
        isNull,
      );
    });
  });

  group('stageBytes', () {
    test('schrijft bytes zonder bronbestand', () async {
      final staged = await AssetStaging.stageBytes(
        Uint8List.fromList([1, 2, 3]),
        subdir: 'images',
        filename: 'geplakt.png',
      );

      expect(File(staged!).readAsBytesSync(), [1, 2, 3]);
      expect(p.basename(staged), 'geplakt.png');
    });
  });

  group('isStagedPath', () {
    test('herkent een gestaged pad', () async {
      final staged = await AssetStaging.stage(
        source('a.png', 'x').path,
        subdir: 'images',
      );

      expect(AssetStaging.isStagedPath(staged!), isTrue);
    });

    test('herkent een pad van een eerdere sessie', () async {
      final staged = await AssetStaging.stage(
        source('a.png', 'x').path,
        subdir: 'images',
      );

      // Een herstart maakt een nieuwe sessiemap, maar dezelfde wortel: een
      // teruggehaald deck moet zijn oude kopieën nog steeds herkennen.
      AssetStaging.overrideRootForTest(AssetStaging.rootPath);

      expect(AssetStaging.isStagedPath(staged!), isTrue);
    });

    test('is onwaar voor een pad daarbuiten', () {
      expect(AssetStaging.isStagedPath('/elders/foto.png'), isFalse);
    });

    test('is onwaar voor een relatief pad', () {
      expect(AssetStaging.isStagedPath('images/foto.png'), isFalse);
    });

    test('is onwaar voor een leeg pad', () {
      expect(AssetStaging.isStagedPath(''), isFalse);
    });

    test('is onwaar zonder wachtkamer', () {
      AssetStaging.overrideRootForTest(null);

      expect(AssetStaging.isStagedPath('/wat/dan/ook.png'), isFalse);
    });
  });
}
