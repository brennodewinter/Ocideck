import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/asset_staging.dart';
import 'package:ocideck/services/recovery_service.dart';
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
    test('kopieert de bron naar de subdir van de stagingmap', () async {
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

    test('geeft null zonder stagingmap', () async {
      AssetStaging.overrideRootForTest(null);

      expect(
        await AssetStaging.stage(source('a.png', 'x').path, subdir: 'images'),
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

  group('pruneStale', () {
    /// Zet de tijdstempels van elk bestand in een sessieboom [age] terug,
    /// zodat een test niet hoeft te wachten om oud te zijn. Mapdatums zijn niet
    /// te zetten in dart:io — en dat hoeft ook niet, want de opruimer kijkt
    /// bewust alleen naar bestanden.
    void age(Directory session, Duration age) {
      final when = DateTime.now().subtract(age);
      for (final entry in session.listSync(recursive: true)) {
        if (entry is File) entry.setLastModifiedSync(when);
      }
    }

    Directory sessionOf(String stagedPath) =>
        Directory(p.dirname(p.dirname(stagedPath)));

    test('laat een verse sessiemap staan', () async {
      final staged = await AssetStaging.stage(
        source('a.png', 'x').path,
        subdir: 'images',
      );

      expect(await AssetStaging.pruneStale(), 0);
      expect(File(staged!).existsSync(), isTrue);
    });

    test('ruimt een sessiemap op die over de datum is', () async {
      final staged = await AssetStaging.stage(
        source('a.png', 'x').path,
        subdir: 'images',
      );
      final session = sessionOf(staged!);
      age(session, const Duration(days: 30));
      // Vergeet de sessie, zoals bij een herstart: anders wordt hij ontzien.
      AssetStaging.overrideRootForTest(AssetStaging.rootPath);

      expect(await AssetStaging.pruneStale(), 1);
      expect(session.existsSync(), isFalse);
    });

    test('kijkt naar het jongste bestand, niet naar de map', () async {
      final staged = await AssetStaging.stage(
        source('a.png', 'x').path,
        subdir: 'images',
      );
      final session = sessionOf(staged!);
      age(session, const Duration(days: 30));
      // Eén recent bestand: de sessie is dus wél in gebruik. Zou de map zelf
      // de maatstaf zijn, dan werd dit werk weggegooid.
      File(staged).setLastModifiedSync(DateTime.now());
      AssetStaging.overrideRootForTest(AssetStaging.rootPath);

      expect(await AssetStaging.pruneStale(), 0);
      expect(File(staged).existsSync(), isTrue);
    });

    test('ontziet de sessie van de draaiende app', () async {
      final staged = await AssetStaging.stage(
        source('a.png', 'x').path,
        subdir: 'images',
      );
      age(sessionOf(staged!), const Duration(days: 30));

      // Geen override: deze sessie is de huidige en moet blijven, hoe oud de
      // tijdstempels ook zijn.
      expect(await AssetStaging.pruneStale(), 0);
      expect(File(staged).existsSync(), isTrue);
    });

    test('houdt het minstens zo lang vol als de herstelbestanden', () {
      expect(
        AssetStaging.defaultMaxAge,
        greaterThanOrEqualTo(RecoveryService.defaultMaxAge),
      );
    });

    test('doet niets zonder stagingmap', () async {
      AssetStaging.overrideRootForTest(null);

      expect(await AssetStaging.pruneStale(), 0);
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

    test('is onwaar zonder stagingmap', () {
      AssetStaging.overrideRootForTest(null);

      expect(AssetStaging.isStagedPath('/wat/dan/ook.png'), isFalse);
    });
  });
}
