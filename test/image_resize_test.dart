import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/utils/image_resize.dart';

void main() {
  group('bakeJpegOrientation', () {
    test(
      'een JPEG met orientatie 3 (180°) wordt geroteerd en de tag gewist',
      () {
        final original = img.Image(width: 4, height: 2);
        original.setPixelRgb(0, 0, 255, 0, 0); // linksboven = rood
        original.setPixelRgb(3, 1, 0, 0, 255); // rechtsonder = blauw
        original.exif.imageIfd.orientation = 3; // 180°
        final jpeg = Uint8List.fromList(img.encodeJpg(original));

        final baked = bakeJpegOrientation(jpeg);
        final decoded = img.decodeImage(baked);

        expect(decoded, isNotNull);
        expect(
          decoded!.exif.imageIfd.hasOrientation,
          isFalse,
          reason: 'orientatie-tag moet zijn gewist',
        );
        final px = decoded.getPixel(0, 0);
        expect(px.r, 0);
        expect(px.b, greaterThan(200), reason: 'pixel (0,0) moet blauw zijn');
      },
    );

    test('een JPEG zonder orientatie-tag gaat ongewijzigd door', () {
      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 2, height: 2)),
      );
      expect(bakeJpegOrientation(jpeg), jpeg);
    });

    test('een PNG gaat ongewijzigd door', () {
      final png = Uint8List.fromList(
        img.encodePng(img.Image(width: 2, height: 2)),
      );
      expect(bakeJpegOrientation(png), png);
    });

    test('geen afbeelding gaat ongewijzigd door', () {
      final notImage = Uint8List.fromList([0, 1, 2, 3]);
      expect(bakeJpegOrientation(notImage), notImage);
    });
  });

  group('rotateImageBytes', () {
    test('180° rotatie wisselt linkerboven en rechtonder', () {
      final original = img.Image(width: 4, height: 2);
      original.setPixelRgb(0, 0, 255, 0, 0); // linksboven = rood
      original.setPixelRgb(3, 1, 0, 0, 255); // rechtsonder = blauw
      final jpeg = Uint8List.fromList(img.encodeJpg(original));

      final rotated = rotateImageBytes(jpeg, 180);
      final decoded = img.decodeImage(rotated);

      expect(decoded, isNotNull);
      final tl = decoded!.getPixel(0, 0);
      final br = decoded.getPixel(3, 1);
      expect(tl.b, greaterThan(200), reason: 'pixel (0,0) moet blauw zijn');
      expect(br.r, greaterThan(200), reason: 'pixel (3,1) moet rood zijn');
    });

    test('0° rotatie geeft de bytes ongewijzigd terug', () {
      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 2, height: 2)),
      );
      expect(rotateImageBytes(jpeg, 0), jpeg);
    });

    test('360° rotatie geeft de bytes ongewijzigd terug', () {
      final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 2, height: 2)),
      );
      expect(rotateImageBytes(jpeg, 360), jpeg);
    });

    test('90° rotatie wisselt breedte en hoogte', () {
      final original = img.Image(width: 4, height: 2);
      original.setPixelRgb(0, 0, 255, 0, 0); // linksboven = rood
      final jpeg = Uint8List.fromList(img.encodeJpg(original));

      final rotated = rotateImageBytes(jpeg, 90);
      final decoded = img.decodeImage(rotated);

      expect(decoded, isNotNull);
      expect(decoded!.width, 2);
      expect(decoded.height, 4);
      // Na 90° CW komt pixel (0,0) van het origineel rechtsboven te staan
      final tr = decoded.getPixel(decoded.width - 1, 0);
      expect(
        tr.r,
        greaterThan(200),
        reason: 'pixel rechtsboven moet rood zijn',
      );
    });

    test('PNG wordt als PNG gere-encodeerd', () {
      final original = img.Image(width: 2, height: 2);
      final png = Uint8List.fromList(img.encodePng(original));

      final rotated = rotateImageBytes(png, 180);
      // PNG signature: 89 50 4e 47
      expect(rotated[0], 0x89);
      expect(rotated[1], 0x50);
      expect(rotated[2], 0x4e);
      expect(rotated[3], 0x47);
    });
  });
}
