import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asset_origin.dart';
import 'package:ocideck/services/asset_staging.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ocideck_origin');
    AssetStaging.overrideRootForTest(p.join(tmp.path, 'ocideck_staging'));
  });

  tearDown(() {
    AssetStaging.overrideRootForTest(null);
    tmp.deleteSync(recursive: true);
  });

  group('classifyAssetPath', () {
    test('leeg pad telt als geen verwijzing', () {
      expect(classifyAssetPath('', '/deck'), AssetOrigin.none);
      expect(classifyAssetPath('   ', '/deck'), AssetOrigin.none);
    });

    test('een relatief pad hoort bij het deck', () {
      expect(classifyAssetPath('images/foto.png', '/deck'), AssetOrigin.inDeck);
      expect(classifyAssetPath('media/clip.mp4', null), AssetOrigin.inDeck);
    });

    test('een absoluut pad binnen de deckmap hoort bij het deck', () {
      expect(
        classifyAssetPath('/deck/images/foto.png', '/deck'),
        AssetOrigin.inDeck,
      );
    });

    test('een absoluut pad daarbuiten is extern', () {
      expect(
        classifyAssetPath('/elders/foto.png', '/deck'),
        AssetOrigin.external,
      );
    });

    test('zonder projectmap is een absoluut pad extern', () {
      expect(classifyAssetPath('/elders/foto.png', null), AssetOrigin.external);
    });

    test('een pad in de stagingmap is gestaged', () async {
      final src = File(p.join(tmp.path, 'foto.png'))..writeAsStringSync('x');
      final staged = await AssetStaging.stage(src.path, subdir: 'images');

      expect(classifyAssetPath(staged!, null), AssetOrigin.staged);
    });

    test('de stagingmap wint van de externe uitkomst', () async {
      final src = File(p.join(tmp.path, 'foto.png'))..writeAsStringSync('x');
      final staged = await AssetStaging.stage(src.path, subdir: 'images');

      // Het deck is intussen ergens anders opgeslagen; de nog niet verhuisde
      // kopie blijft "in de stagingmap" en wordt niet als extern gemeld.
      expect(classifyAssetPath(staged!, '/deck'), AssetOrigin.staged);
    });

    test('webadressen zijn extern materiaal', () {
      expect(
        classifyAssetPath('https://example.org/a.png', '/deck'),
        AssetOrigin.remote,
      );
      expect(
        classifyAssetPath('HTTP://example.org/a.png', '/deck'),
        AssetOrigin.remote,
      );
    });

    test('een mem:-pad leeft alleen in deze sessie', () {
      expect(classifyAssetPath('mem:0123-abcd', null), AssetOrigin.memory);
    });
  });

  group('assetOriginNeedsAttention', () {
    test('zwijgt bij een gewone deckafbeelding', () {
      expect(assetOriginNeedsAttention(AssetOrigin.inDeck), isFalse);
      expect(assetOriginNeedsAttention(AssetOrigin.none), isFalse);
    });

    test('meldt alles wat niet vanzelf meeverhuist', () {
      expect(assetOriginNeedsAttention(AssetOrigin.staged), isTrue);
      expect(assetOriginNeedsAttention(AssetOrigin.external), isTrue);
      expect(assetOriginNeedsAttention(AssetOrigin.remote), isTrue);
      expect(assetOriginNeedsAttention(AssetOrigin.memory), isTrue);
    });
  });
}
