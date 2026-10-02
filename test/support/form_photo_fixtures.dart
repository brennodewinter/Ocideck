// Echte foto's voor de formuliertests: een JPEG die de decoder accepteert, met op
// verzoek een EXIF-segment dat een positie draagt.

import 'dart:typed_data';

import 'package:image/image.dart' as img;

List<int> _u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];
List<int> _u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

/// Een TIFF-blok met een verwijzing naar een GPS-blok.
List<int> gpsTiff() => [
  ...'MM'.codeUnits,
  ..._u16(42),
  ..._u32(8),
  ..._u16(1),
  ..._u16(0x8825),
  ..._u16(4),
  ..._u32(1),
  ..._u32(0x40),
  ..._u32(0),
];

/// Een echte JPEG van [width]×[height]; met [gps] staat er een EXIF-segment met
/// een positie direct na het SOI.
Uint8List jpegPhoto({int width = 40, int height = 20, bool gps = false}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(200, 100, 50));
  final jpg = img.encodeJpg(image, quality: 90);
  if (!gps) return jpg;
  final exif = gpsTiff();
  return Uint8List.fromList([
    ...jpg.sublist(0, 2),
    0xFF,
    0xE1,
    ..._u16(exif.length + 8),
    ...'Exif'.codeUnits,
    0,
    0,
    ...exif,
    ...jpg.sublist(2),
  ]);
}
