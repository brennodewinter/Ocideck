// Tests for the lightweight image dimension reader (#1853).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/image_dimensions.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('img_dims_test'));
  tearDown(() => tmp.deleteSync(recursive: true));

  test('PNG dimensions worden gelezen uit de header', () {
    // 2×3 PNG.
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
      0x00, 0x00, 0x00, 0x0D, // IHDR length
      0x49, 0x48, 0x44, 0x52, // "IHDR"
      0x00, 0x00, 0x00, 0x02, // width = 2
      0x00, 0x00, 0x00, 0x03, // height = 3
      0x08, 0x02, 0x00, 0x00, 0x00, // bit depth, color type, etc.
    ]);
    final file = File('${tmp.path}/test.png')..writeAsBytesSync(png);
    final dims = readImageDimensions(file.path);
    expect(dims, isNotNull);
    expect(dims!.width, 2);
    expect(dims.height, 3);
  });

  test('imageDimensionsFromBytes herkent PNG', () {
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
      0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x00, 0x64, // width = 100
      0x00, 0x00, 0x00, 0xC8, // height = 200
      0x08, 0x02, 0x00, 0x00, 0x00,
    ]);
    final dims = imageDimensionsFromBytes(png);
    expect(dims, isNotNull);
    expect(dims!.width, 100);
    expect(dims.height, 200);
    expect(dims.aspect, closeTo(0.5, 0.001));
  });

  test('GIF dimensions worden gelezen', () {
    // GIF87a, 4×5.
    final gif = Uint8List.fromList([
      0x47, 0x49, 0x46, 0x38, 0x37, 0x61, // "GIF87a"
      0x04, 0x00, // width = 4 (LE)
      0x05, 0x00, // height = 5 (LE)
      0x00, 0x00, 0x00, // padding
    ]);
    final dims = imageDimensionsFromBytes(gif);
    expect(dims, isNotNull);
    expect(dims!.width, 4);
    expect(dims.height, 5);
  });

  test('BMP dimensions worden gelezen', () {
    // Minimal BMP header, 6×7.
    final bmp = Uint8List(26);
    bmp[0] = 0x42; // 'B'
    bmp[1] = 0x4D; // 'M'
    // width at offset 18 (LE uint32) = 6
    bmp[18] = 0x06;
    // height at offset 22 (LE uint32) = 7
    bmp[22] = 0x07;
    final dims = imageDimensionsFromBytes(bmp);
    expect(dims, isNotNull);
    expect(dims!.width, 6);
    expect(dims.height, 7);
  });

  test('niet-ondersteund formaat geeft null', () {
    final bytes = Uint8List.fromList([0x00, 0x01, 0x02, 0x03, 0x04, 0x05]);
    expect(imageDimensionsFromBytes(bytes), isNull);
  });

  test('te korte bytes geven null', () {
    expect(imageDimensionsFromBytes(Uint8List(3)), isNull);
  });

  test('ontbrekend bestand geeft null', () {
    expect(readImageDimensions('${tmp.path}/bestaat_niet.png'), isNull);
  });
}
