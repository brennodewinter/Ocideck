import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/slide_image_refs.dart';
import 'package:path/path.dart' as p;

/// Regressie voor #2104: een slide kopiëren van een presentatie in map A naar
/// een presentatie in map B nam de afbeelding niet mee — het klembord bewaarde
/// de kale slide met een relatief pad, dat in B tegen de verkeerde map werd
/// aangelegd. De twee stappen van de reparatie: bij het kopiëren worden lokale
/// verwijzingen absoluut tegen de bronmap, bij het plakken kopiëren de bytes
/// mee de doelmap in.
void main() {
  late Directory tmp;
  final service = ImageService();

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_copy'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('absolutizeSlideAssetPaths', () {
    test('maakt relatieve paden absoluut tegen de bronmap', () {
      final sourceDir = Directory(p.join(tmp.path, 'bronmap'))..createSync();
      final slide = Slide.create(SlideType.image).copyWith(
        imagePath: 'images/een.png',
        imagePath2: 'images/twee.png',
        customMarkdown: 'Zie ![de foto](images/drie.png) hierboven.',
      );

      final out = absolutizeSlideAssetPaths(slide, sourceDir.path);

      expect(out.imagePath, p.join(sourceDir.path, 'images/een.png'));
      expect(out.imagePath2, p.join(sourceDir.path, 'images/twee.png'));
      expect(
        out.customMarkdown,
        'Zie ![de foto](${p.join(sourceDir.path, 'images/drie.png')}) hierboven.',
      );
    });

    test('neemt video, audio en de Marp-achtergrond mee', () {
      final sourceDir = Directory(p.join(tmp.path, 'bronmap'))..createSync();
      final slide = Slide.create(SlideType.video).copyWith(
        videoPath: 'media/clip.mp4',
        audioPath: 'media/geluid.mp3',
        marpStyle: const MarpStyle(backgroundImage: "url('images/bg.png')"),
      );

      final out = absolutizeSlideAssetPaths(slide, sourceDir.path);

      expect(out.videoPath, p.join(sourceDir.path, 'media/clip.mp4'));
      expect(out.audioPath, p.join(sourceDir.path, 'media/geluid.mp3'));
      expect(
        out.marpStyle.backgroundImage,
        "url('${p.join(sourceDir.path, 'images/bg.png')}')",
      );
    });

    test('laat absolute paden, URLs en mem:-verwijzingen ongemoeid', () {
      final slide = Slide.create(SlideType.image).copyWith(
        imagePath: '/ elders/plaatje.png'.replaceAll(' ', ''),
        imagePath2: 'mem:00000000-0000-0000-0000-000000000000',
        customMarkdown:
            '![web](https://voorbeeld.nl/x.png) ![data](data:image/png;base64,AA==)',
      );

      final out = absolutizeSlideAssetPaths(slide, '/bronmap');

      expect(out.imagePath, '/elders/plaatje.png');
      expect(out.imagePath2, 'mem:00000000-0000-0000-0000-000000000000');
      expect(out.customMarkdown, slide.customMarkdown);
    });

    test('doet niets zonder bronmap', () {
      final slide = Slide.create(
        SlideType.image,
      ).copyWith(imagePath: 'images/een.png');
      expect(identical(absolutizeSlideAssetPaths(slide, null), slide), isTrue);
    });
  });

  group('adoptSlideAssets — de gerepareerde kopieerroute', () {
    test('kopieert de afbeelding mee naar de doelmap', () async {
      // Map A met de bronpresentatie, map B met het doel-deck.
      final dirA = Directory(p.join(tmp.path, 'a'))..createSync();
      final dirB = Directory(p.join(tmp.path, 'b'))..createSync();
      File(p.join(dirA.path, 'images', 'pic.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      final copied = Slide.create(
        SlideType.image,
      ).copyWith(imagePath: 'images/pic.png');

      // Kopiëren in A: de verwijzing wordt absoluut tegen A aangelegd.
      final onClipboard = absolutizeSlideAssetPaths(copied, dirA.path);
      // Plakken in B: het bestand verhuist mee en het pad wordt weer relatief.
      final pasted = await service.adoptSlideAssets([onClipboard], dirB.path);

      expect(pasted.single.imagePath, 'images/pic.png');
      expect(File(p.join(dirB.path, 'images', 'pic.png')).readAsBytesSync(), [
        1,
        2,
        3,
      ]);
    });

    test('wijkt uit naar een vrije naam bij een naambotsing', () async {
      final dirA = Directory(p.join(tmp.path, 'a'))..createSync();
      final dirB = Directory(p.join(tmp.path, 'b'))..createSync();
      File(p.join(dirA.path, 'pic.png')).writeAsBytesSync([1]);
      // In B staat al een ándere pic.png — overschrijven zou de bestaande
      // slides van B breken.
      File(p.join(dirB.path, 'images', 'pic.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 9, 9]);
      final copied = Slide.create(
        SlideType.image,
      ).copyWith(imagePath: 'pic.png');

      final pasted = await service.adoptSlideAssets([
        absolutizeSlideAssetPaths(copied, dirA.path),
      ], dirB.path);

      expect(pasted.single.imagePath, 'images/pic_2.png');
      expect(File(p.join(dirB.path, 'images', 'pic_2.png')).readAsBytesSync(), [
        1,
      ]);
      // Het bestaande bestand is ongemoeid.
      expect(File(p.join(dirB.path, 'images', 'pic.png')).readAsBytesSync(), [
        9,
        9,
        9,
      ]);
    });

    test('kopieert video en audio mee naar media/', () async {
      final dirA = Directory(p.join(tmp.path, 'a'))..createSync();
      final dirB = Directory(p.join(tmp.path, 'b'))..createSync();
      File(p.join(dirA.path, 'media', 'clip.mp4'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      File(p.join(dirA.path, 'media', 'geluid.mp3'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([2]);
      final copied = Slide.create(
        SlideType.video,
      ).copyWith(videoPath: 'media/clip.mp4', audioPath: 'media/geluid.mp3');

      final pasted = await service.adoptSlideAssets([
        absolutizeSlideAssetPaths(copied, dirA.path),
      ], dirB.path);

      expect(pasted.single.videoPath, 'media/clip.mp4');
      expect(pasted.single.audioPath, 'media/geluid.mp3');
      expect(File(p.join(dirB.path, 'media', 'clip.mp4')).existsSync(), isTrue);
      expect(
        File(p.join(dirB.path, 'media', 'geluid.mp3')).existsSync(),
        isTrue,
      );
    });

    test('laat de slide staan als het doel-deck nog geen map heeft', () async {
      final slide = Slide.create(
        SlideType.image,
      ).copyWith(imagePath: '/bron/images/pic.png');
      final out = await service.adoptSlideAssets([slide], null);
      expect(identical(out.single, slide), isTrue);
    });
  });
}
