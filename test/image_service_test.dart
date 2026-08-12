import 'dart:typed_data';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tmp;
  final service = ImageService();

  setUp(() => tmp = Directory.systemTemp.createTempSync('ocideck_img'));
  tearDown(() => tmp.deleteSync(recursive: true));

  group('resolve', () {
    test('returns empty for an empty path', () {
      expect(service.resolve('', '/project'), '');
    });

    test('returns absolute paths unchanged', () {
      expect(
        service.resolve('/abs/pic.png', '/project'),
        p.normalize('/abs/pic.png'),
      );
    });

    test('joins relative paths with the project path', () {
      expect(
        service.resolve('images/pic.png', '/project'),
        p.normalize(p.join('/project', 'images/pic.png')),
      );
    });
  });

  group('copyImagesToProject', () {
    test(
      'copies an absolute image into images/ and rewrites the path',
      () async {
        final src = File(p.join(tmp.path, 'photo.png'))
          ..writeAsBytesSync([1, 2]);
        final project = Directory(p.join(tmp.path, 'project'))..createSync();

        final out = await service.copyImagesToProject([
          Slide.create(SlideType.image).copyWith(imagePath: src.path),
        ], project.path);

        expect(out.single.imagePath, 'images/photo.png');
        expect(
          File(p.join(project.path, 'images', 'photo.png')).existsSync(),
          isTrue,
        );
      },
    );

    test('leaves already-relative image paths unchanged', () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final out = await service.copyImagesToProject([
        Slide.create(SlideType.image).copyWith(imagePath: 'images/keep.png'),
      ], project.path);
      expect(out.single.imagePath, 'images/keep.png');
    });

    test('leaves the path unchanged when the source file is missing', () async {
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      final missing = p.join(tmp.path, 'does_not_exist.png');
      final out = await service.copyImagesToProject([
        Slide.create(SlideType.image).copyWith(imagePath: missing),
      ], project.path);
      expect(out.single.imagePath, missing);
    });

    test('copies the second image of a twoImages slide', () async {
      final a = File(p.join(tmp.path, 'a.png'))..writeAsBytesSync([1]);
      final b = File(p.join(tmp.path, 'b.png'))..writeAsBytesSync([2]);
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final out = await service.copyImagesToProject([
        Slide.create(
          SlideType.twoImages,
        ).copyWith(imagePath: a.path, imagePath2: b.path),
      ], project.path);

      expect(out.single.imagePath, 'images/a.png');
      expect(out.single.imagePath2, 'images/b.png');
    });

    test('materialiseert een mem:-afbeelding als bestand in images/', () async {
      // Slides uit een remote deck dragen hun beeld als mem:-pad. Bij opslaan
      // moeten die bytes een echt bestand worden, anders breken ze na herladen.
      addTearDown(WebAssetStore.clear);
      final bytes = Uint8List.fromList([9, 8, 7, 6, 5]);
      final mem = WebAssetStore.put(bytes, name: 'plaatje.png');
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final out = await service.copyImagesToProject([
        Slide.create(SlideType.image).copyWith(imagePath: mem),
      ], project.path);

      expect(out.single.imagePath, 'images/plaatje.png');
      final file = File(p.join(project.path, 'images', 'plaatje.png'));
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), bytes);
    });

    test('laat een mem:-pad staan als de bytes weg zijn', () async {
      // Na een paginaherlaad is de store leeg; er valt niets te schrijven, dus
      // het pad blijft ongemoeid in plaats van naar een leeg bestand te wijzen.
      final project = Directory(p.join(tmp.path, 'project'))..createSync();
      const dangling = 'mem:00000000-0000-0000-0000-000000000000';
      final out = await service.copyImagesToProject([
        Slide.create(SlideType.image).copyWith(imagePath: dangling),
      ], project.path);
      expect(out.single.imagePath, dangling);
      expect(Directory(p.join(project.path, 'images')).listSync(), isEmpty);
    });

    test('kopieert ook een afbeelding uit de vrije tekst', () async {
      // Zonder deze stap houdt de opgeslagen presentatie een absoluut pad naar
      // een bestand buiten haar eigen map: bij de maker in orde, bij de
      // ontvanger een leeg vak.
      final src = File(p.join(tmp.path, 'inline.png'))
        ..writeAsBytesSync([1, 2, 3]);
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final out = await service.copyImagesToProject([
        Slide.create(SlideType.freeMarkdown).copyWith(
          customMarkdown: 'Zie ![w:600 de foto](${src.path}) hierboven.',
        ),
      ], project.path);

      expect(
        out.single.customMarkdown,
        'Zie ![w:600 de foto](images/inline.png) hierboven.',
      );
      expect(
        File(p.join(project.path, 'images', 'inline.png')).existsSync(),
        isTrue,
      );
    });

    test(
      'hergebruikt een bestaande afbeelding met dezelfde inhoud onder een andere naam',
      () async {
        // Cross-import dedup: een herimport of aanverwante presentatie met
        // dezelfde afbeelding onder een andere naam mag geen duplicaat maken.
        addTearDown(WebAssetStore.clear);
        final bytes = Uint8List.fromList([10, 20, 30, 40]);
        final project = Directory(p.join(tmp.path, 'project'))..createSync();
        // Bestaande afbeelding in de projectmap, andere naam.
        final existing =
            File(p.join(project.path, 'images', 'logo_bedrijf.png'))
              ..createSync(recursive: true)
              ..writeAsBytesSync(bytes);

        final mem = WebAssetStore.put(bytes, name: 'logo.png');
        final out = await service.copyImagesToProject([
          Slide.create(SlideType.image).copyWith(imagePath: mem),
        ], project.path);

        // Het pad wijst naar de bestaande afbeelding, niet naar een nieuw bestand.
        expect(out.single.imagePath, 'images/logo_bedrijf.png');
        // Er is geen nieuw bestand bijgekomen.
        expect(Directory(p.join(project.path, 'images')).listSync().length, 1);
        // Het bestaande bestand is ongemoeid.
        expect(existing.readAsBytesSync(), bytes);
      },
    );

    test(
      'schrijft een nieuwe afbeelding als de inhoud verschilt ondanks dezelfde naam',
      () async {
        // Namen botsen maar de inhoud is anders: dan moet er een _1-kopie komen,
        // niet een stille overschrijving van het bestaande bestand.
        addTearDown(WebAssetStore.clear);
        final project = Directory(p.join(tmp.path, 'project'))..createSync();
        final imagesDir = Directory(p.join(project.path, 'images'))
          ..createSync(recursive: true);
        File(p.join(imagesDir.path, 'logo.png')).writeAsBytesSync([1, 1, 1]);

        final newBytes = Uint8List.fromList([2, 2, 2]);
        final mem = WebAssetStore.put(newBytes, name: 'logo.png');
        final out = await service.copyImagesToProject([
          Slide.create(SlideType.image).copyWith(imagePath: mem),
        ], project.path);

        expect(out.single.imagePath, 'images/logo_2.png');
        expect(
          File(p.join(project.path, 'images', 'logo_2.png')).readAsBytesSync(),
          newBytes,
        );
      },
    );
  });

  group('copyMediaToProject', () {
    test(
      'copies absolute video/audio into media/ and rewrites paths',
      () async {
        final vid = File(p.join(tmp.path, 'clip.mp4'))..writeAsBytesSync([1]);
        final aud = File(p.join(tmp.path, 'sound.mp3'))..writeAsBytesSync([2]);
        final project = Directory(p.join(tmp.path, 'project'))..createSync();

        final out = await service.copyMediaToProject([
          Slide.create(
            SlideType.video,
          ).copyWith(videoPath: vid.path, audioPath: aud.path),
        ], project.path);

        expect(out.single.videoPath, 'media/clip.mp4');
        expect(out.single.audioPath, 'media/sound.mp3');
        expect(
          File(p.join(project.path, 'media', 'clip.mp4')).existsSync(),
          isTrue,
        );
      },
    );
  });

  group('copyImageToClipboard', () {
    test('returns false for an empty path', () async {
      expect(await service.copyImageToClipboard(''), isFalse);
    });

    test('returns false for a non-existent file', () async {
      final missing = p.join(tmp.path, 'nope.png');
      expect(await service.copyImageToClipboard(missing), isFalse);
    });

    test('copyImageBytesToClipboard returns false for empty bytes', () async {
      expect(await service.copyImageBytesToClipboard(Uint8List(0)), isFalse);
    });
  });

  group('looksLikeImage magic-byte validation', () {
    test('accepts real raster signatures', () {
      expect(
        ImageService.looksLikeImage(const [0x89, 0x50, 0x4E, 0x47]),
        isTrue,
      ); // PNG
      expect(
        ImageService.looksLikeImage(const [0xFF, 0xD8, 0xFF, 0xE0]),
        isTrue,
      ); // JPEG
      expect(
        ImageService.looksLikeImage(const [0x47, 0x49, 0x46, 0x38]),
        isTrue,
      ); // GIF
      expect(
        ImageService.looksLikeImage(const [
          0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF
          0x57, 0x45, 0x42, 0x50, // WEBP
        ]),
        isTrue,
      );
    });

    test('rejects non-image bytes (e.g. a script renamed to .png)', () {
      expect(ImageService.looksLikeImage('<?php evil();'.codeUnits), isFalse);
      expect(ImageService.looksLikeImage('# markdown'.codeUnits), isFalse);
      expect(ImageService.looksLikeImage(const [0x00, 0x01]), isFalse);
    });
  });

  group('mediaMimeFromBytes', () {
    // Video en audio waren tot 2026-07-22 alleen op grootte begrensd, dus een
    // willekeurig bestand hernoemd naar .mp4 kwam het project in en ging daarna
    // naar de mediastack van het platform. Dit geeft ze dezelfde waarborg die
    // afbeeldingen al hadden.
    test('herkent de containers die er echt toe doen', () {
      expect(
        ImageService.mediaMimeFromBytes(const [
          0, 0, 0, 0x20, // boxlengte
          0x66, 0x74, 0x79, 0x70, // "ftyp"
          0x69, 0x73, 0x6F, 0x6D, // "isom"
        ]),
        'video/mp4',
      );
      expect(
        ImageService.mediaMimeFromBytes(const [0x1A, 0x45, 0xDF, 0xA3]),
        'video/webm',
      );
      expect(ImageService.mediaMimeFromBytes('OggS'.codeUnits), 'audio/ogg');
      expect(ImageService.mediaMimeFromBytes('fLaC'.codeUnits), 'audio/flac');
      expect(
        ImageService.mediaMimeFromBytes('ID3\u0004'.codeUnits),
        'audio/mpeg',
      );
      expect(
        ImageService.mediaMimeFromBytes(const [0xFF, 0xFB, 0x90, 0x00]),
        'audio/mpeg',
      );
      expect(
        ImageService.mediaMimeFromBytes(const [
          0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF
          0x57, 0x41, 0x56, 0x45, // WAVE
        ]),
        'audio/wav',
      );
    });

    test('weigert wat geen mediacontainer is', () {
      expect(
        ImageService.mediaMimeFromBytes('<?php evil();'.codeUnits),
        isNull,
      );
      expect(ImageService.mediaMimeFromBytes('# markdown'.codeUnits), isNull);
      expect(
        ImageService.mediaMimeFromBytes('MZ\u0090\u0000'.codeUnits),
        isNull,
      );
      expect(ImageService.mediaMimeFromBytes(const [0x00, 0x01]), isNull);
    });

    test('een RIFF die geen WAVE of AVI is telt niet mee — WebP is een '
        'afbeelding, geen media', () {
      expect(
        ImageService.mediaMimeFromBytes(const [
          0x52, 0x49, 0x46, 0x46, 0, 0, 0, 0, // RIFF
          0x57, 0x45, 0x42, 0x50, // WEBP
        ]),
        isNull,
      );
    });
  });

  group('EXIF-orientatie bakken bij import', () {
    test('een JPEG met orientatie 3 (180°) wordt geroteerd en de tag wordt '
        'gewist', () async {
      // Maak een kleine afbeelding met een herkenbaar patroon: pixel (0,0)
      // is rood, pixel (w-1,h-1) is blauw. Na 180° rotatie moet pixel (0,0)
      // blauw zijn.
      final original = img.Image(width: 4, height: 2);
      original.setPixelRgb(0, 0, 255, 0, 0); // linksboven = rood
      original.setPixelRgb(3, 1, 0, 0, 255); // rechtsonder = blauw
      original.exif.imageIfd.orientation = 3; // 180°
      final jpegBytes = Uint8List.fromList(img.encodeJpg(original));

      // Sla op als tijdelijk bestand en importeer in het project.
      final src = File(p.join(tmp.path, 'rotated.jpg'))
        ..writeAsBytesSync(jpegBytes);
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final imported = await service.importIntoDeck(
        src.path,
        projectPath: project.path,
      );

      // De geïmporteerde afbeelding moet de orientatie-tag kwijt zijn.
      final outBytes = File(p.join(project.path, imported)).readAsBytesSync();
      final decoded = img.decodeImage(outBytes);
      expect(decoded, isNotNull);
      expect(
        decoded!.exif.imageIfd.hasOrientation,
        isFalse,
        reason: 'de orientatie-tag moet zijn gewist na het bakken',
      );
      // Na 180° rotatie moet pixel (0,0) blauw zijn (was rood).
      final px = decoded.getPixel(0, 0);
      expect(px.r, 0);
      expect(px.b, greaterThan(200), reason: 'pixel (0,0) moet blauw zijn');
    });

    test('een JPEG zonder orientatie-tag gaat ongewijzigd door', () async {
      final original = img.Image(width: 2, height: 2);
      final jpegBytes = Uint8List.fromList(img.encodeJpg(original));
      final src = File(p.join(tmp.path, 'plain.jpg'))
        ..writeAsBytesSync(jpegBytes);
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final imported = await service.importIntoDeck(
        src.path,
        projectPath: project.path,
      );

      // Zonder orientatie-tag mag de inhoud niet veranderen (geen re-encode).
      final outBytes = File(p.join(project.path, imported)).readAsBytesSync();
      expect(outBytes, jpegBytes);
    });

    test('een PNG gaat ongewijzigd door (geen EXIF-orientatie)', () async {
      final pngBytes = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      final src = File(p.join(tmp.path, 'pic.png'))..writeAsBytesSync(pngBytes);
      final project = Directory(p.join(tmp.path, 'project'))..createSync();

      final imported = await service.importIntoDeck(
        src.path,
        projectPath: project.path,
      );

      final outBytes = File(p.join(project.path, imported)).readAsBytesSync();
      expect(outBytes, pngBytes);
    });
  });
}
