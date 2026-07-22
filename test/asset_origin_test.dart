import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

import 'package:ocideck/models/asset_origin.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/web_asset_store.dart';
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

  group('deckCarriesMemoryAssets', () {
    tearDown(WebAssetStore.clear);

    Deck deckWith(Slide slide, {ThemeProfile? theme}) => Deck(
      title: 'D',
      slides: [slide],
      themeProfile: theme ?? const ThemeProfile(),
    );

    test('een deck met alleen padverwijzingen draagt niets vluchtigs', () {
      final deck = deckWith(
        Slide.create(SlideType.image).copyWith(imagePath: 'images/foto.png'),
      );
      expect(deckCarriesMemoryAssets(deck), isFalse);
    });

    test('een mem:-afbeelding maakt het deck vluchtig', () {
      final mem = WebAssetStore.put(Uint8List(4), name: 'foto.png');
      final deck = deckWith(
        Slide.create(SlideType.image).copyWith(imagePath: mem),
      );
      expect(deckCarriesMemoryAssets(deck), isTrue);
    });

    test('ook video, audio en de tweede afbeelding tellen mee', () {
      final mem = WebAssetStore.put(Uint8List(4), name: 'clip.mp4');
      for (final slide in [
        Slide.create(SlideType.image).copyWith(imagePath2: mem),
        Slide.create(SlideType.video).copyWith(videoPath: mem),
        Slide.create(SlideType.bullets).copyWith(audioPath: mem),
      ]) {
        expect(deckCarriesMemoryAssets(deckWith(slide)), isTrue);
      }
    });

    test('een mem:-logo maakt het deck ook vluchtig', () {
      final mem = WebAssetStore.put(Uint8List(4), name: 'logo.png');
      final deck = deckWith(
        Slide.create(SlideType.title),
        theme: const ThemeProfile().copyWith(logoPath: mem),
      );
      expect(deckCarriesMemoryAssets(deck), isTrue);
    });

    test('een mem:-afbeelding in de vrije tekst telt net zo goed mee', () {
      final mem = WebAssetStore.put(Uint8List(4), name: 'foto.png');
      final deck = deckWith(
        Slide.create(
          SlideType.freeMarkdown,
        ).copyWith(customMarkdown: 'Kijk:\n\n![foto]($mem)\n'),
      );
      expect(deckCarriesMemoryAssets(deck), isTrue);
    });
  });

  group('deckMemoryAssetPaths', () {
    tearDown(WebAssetStore.clear);

    // De sweep gooit weg wat híer niet in staat, dus een gemist pad is
    // dataverlies en geen schoonheidsfoutje.
    test('verzamelt ook de afbeeldingen uit de vrije tekst', () {
      final veld = WebAssetStore.put(Uint8List(4), name: 'veld.png');
      final tekst = WebAssetStore.put(Uint8List(4), name: 'tekst.png');
      final deck = Deck(
        title: 'D',
        slides: [
          Slide.create(SlideType.image).copyWith(
            imagePath: veld,
            customMarkdown: 'Zie ![in de tekst]($tekst) hierboven.',
          ),
        ],
      );

      expect(deckMemoryAssetPaths(deck), {veld, tekst});
    });

    test('addSlideMemoryAssetPaths ziet een dia op het klembord net zo', () {
      final mem = WebAssetStore.put(Uint8List(4), name: 'plak.png');
      final into = <String>{};

      addSlideMemoryAssetPaths(
        Slide.create(
          SlideType.freeMarkdown,
        ).copyWith(customMarkdown: '![x]($mem)'),
        into,
      );

      expect(into, {mem});
    });
  });
}
