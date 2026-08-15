import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/utils/image_resize.dart';

void main() {
  group('jpegExifRotationDegrees', () {
    Uint8List jpegWithOrientation(int orientation) {
      final image = img.Image(width: 4, height: 2);
      image.exif.imageIfd.orientation = orientation;
      return Uint8List.fromList(img.encodeJpg(image));
    }

    test('leest de rotatie uit de tag, ook al bakt de decoder hem weg', () {
      expect(jpegExifRotationDegrees(jpegWithOrientation(1)), 0);
      expect(jpegExifRotationDegrees(jpegWithOrientation(3)), 180);
      expect(jpegExifRotationDegrees(jpegWithOrientation(6)), 90);
      expect(jpegExifRotationDegrees(jpegWithOrientation(8)), 270);
    });

    test('van een spiegel-orientatie telt alleen het rotatiedeel', () {
      expect(jpegExifRotationDegrees(jpegWithOrientation(2)), 0);
      expect(jpegExifRotationDegrees(jpegWithOrientation(4)), 180);
      expect(jpegExifRotationDegrees(jpegWithOrientation(5)), 270);
      expect(jpegExifRotationDegrees(jpegWithOrientation(7)), 90);
    });

    test('een JPEG zonder tag, een PNG en rommel geven 0', () {
      expect(
        jpegExifRotationDegrees(
          Uint8List.fromList(img.encodeJpg(img.Image(width: 2, height: 2))),
        ),
        0,
      );
      expect(
        jpegExifRotationDegrees(
          Uint8List.fromList(img.encodePng(img.Image(width: 2, height: 2))),
        ),
        0,
      );
      expect(
        jpegExifRotationDegrees(Uint8List.fromList([0xFF, 0xD8, 0, 1])),
        0,
      );
      expect(jpegExifRotationDegrees(Uint8List(0)), 0);
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

  group('importCrop', () {
    test('vier nullen zijn geen uitsnede', () {
      expect(importCrop(), isNull);
    });

    test('een negatieve zijde vult aan en snijdt dus niet', () {
      expect(importCrop(left: -0.25), isNull);
      expect(importCrop(left: -0.25, right: 0.25)?.left, 0);
      expect(importCrop(left: -0.25, right: 0.25)?.right, 0.25);
    });

    test('een uitsnede die niets overlaat telt niet', () {
      expect(importCrop(left: 0.5, right: 0.5), isNull);
      expect(importCrop(top: 0.9, bottom: 0.2), isNull);
    });

    test('een onberekenbare waarde telt als niets', () {
      expect(importCrop(left: double.nan, top: double.infinity), isNull);
    });
  });

  group('imageNaturalSizeCm', () {
    // ODF meet `fo:clip` hiertegen af; de standaard van 0,2 mm per pixel en het
    // honoreren van de eigen resolutie zijn gemeten aan LibreOffice zelf.
    Uint8List png(int size) =>
        Uint8List.fromList(img.encodePng(img.Image(width: size, height: size)));

    test('zonder eigen resolutie is een pixel 0,2 mm', () {
      final size = imageNaturalSizeCm(png(100));
      expect(size?.width, closeTo(2, 0.001));
      expect(size?.height, closeTo(2, 0.001));
    });

    test('de pHYs-chunk van een PNG telt', () {
      final size = imageNaturalSizeCm(_pngWithDpi(300, 150, 300));
      expect(size?.width, closeTo(2.54, 0.01));
      expect(size?.height, closeTo(1.27, 0.01));
    });

    test('een JFIF-dichtheid in inches telt', () {
      final size = imageNaturalSizeCm(_jpegWithJfifDensity(144, 144, units: 1));
      expect(size?.width, closeTo(144 / 144 * 2.54, 0.01));
    });

    test('JFIF-eenheid 0 zegt alleen iets over de verhouding', () {
      // Alleen een beeldverhouding, geen resolutie: dan geldt de standaard.
      final size = imageNaturalSizeCm(_jpegWithJfifDensity(144, 1, units: 0));
      expect(size?.width, closeTo(144 / 50, 0.01));
    });

    test('onleesbare bytes geven null', () {
      expect(imageNaturalSizeCm(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });
  });
}

/// Een vierkante JPEG van [size] pixels met een JFIF-dichtheid van [density]
/// per [units] (1 = per inch, 2 = per cm, 0 = alleen beeldverhouding).
///
/// De `image`-encoder schrijft altijd eenheid 0 met dichtheid 1, dus de drie
/// velden worden hier in het APP0-segment overschreven.
Uint8List _jpegWithJfifDensity(int size, int density, {required int units}) {
  final bytes = Uint8List.fromList(
    img.encodeJpg(img.Image(width: size, height: size)),
  );
  // APP0 volgt direct op de SOI: FF D8 | FF E0 | lengte(2) | 'JFIF\0'(5) |
  // versie(2) | eenheid(1) | x(2) | y(2).
  expect(bytes.sublist(2, 4), [0xFF, 0xE0]);
  bytes[13] = units;
  bytes[14] = density >> 8;
  bytes[15] = density & 0xFF;
  bytes[16] = density >> 8;
  bytes[17] = density & 0xFF;
  return bytes;
}

/// Een PNG van [width] bij [height] pixels met een `pHYs`-chunk die [dpi]
/// voorschrijft.
Uint8List _pngWithDpi(int width, int height, int dpi) {
  final base = Uint8List.fromList(
    img.encodePng(img.Image(width: width, height: height)),
  );
  const type = [0x70, 0x48, 0x59, 0x73]; // 'pHYs'
  final perMetre = (dpi / 0.0254).round();
  final data = Uint8List(9);
  ByteData.sublistView(data)
    ..setUint32(0, perMetre)
    ..setUint32(4, perMetre);
  data[8] = 1; // eenheid: de meter
  final crc = Uint8List(4);
  ByteData.sublistView(crc).setUint32(0, getCrc32([...type, ...data]));
  final length = Uint8List(4);
  ByteData.sublistView(length).setUint32(0, data.length);
  // De chunk mag overal na de IHDR staan: 8 bytes signatuur plus 25 IHDR.
  return Uint8List.fromList([
    ...base.sublist(0, 33),
    ...length,
    ...type,
    ...data,
    ...crc,
    ...base.sublist(33),
  ]);
}
