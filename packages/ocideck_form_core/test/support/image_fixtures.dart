/// Hand-built image files for the tests: just enough structure that the segment
/// and chunk walkers see a well-formed file, with the personal data a phone puts in
/// one. None of them decodes — [cleanImage] never decodes — but every length, size
/// field and checksum is right, because those are what it reads.
library;

import 'dart:typed_data';

Uint8List bytes(Iterable<int> parts) => Uint8List.fromList(parts.toList());

List<int> u16(int v) => [(v >> 8) & 0xFF, v & 0xFF];

List<int> u32(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

List<int> u32le(int v) => [
  v & 0xFF,
  (v >> 8) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 24) & 0xFF,
];

List<int> text(String s) => s.codeUnits;

/// A TIFF structure as found in EXIF: an orientation, optionally a pointer to a GPS
/// block and a "make" of three characters.
List<int> tiff({int? orientation, bool gps = false, bool little = false}) {
  final entries = <List<int>>[];
  List<int> w16(int v) => little ? [v & 0xFF, (v >> 8) & 0xFF] : u16(v);
  List<int> w32(int v) => little ? u32le(v) : u32(v);
  // Tags must be in ascending order.
  entries.add([
    ...w16(0x010F),
    ...w16(2),
    ...w32(3),
    ...text('AB'),
    0,
    0,
  ]); // Make
  if (orientation != null) {
    entries.add([
      ...w16(0x0112),
      ...w16(3),
      ...w32(1),
      ...w16(orientation),
      0,
      0,
    ]);
  }
  if (gps) {
    entries.add([...w16(0x8825), ...w16(4), ...w32(1), ...w32(0x40)]);
  }
  return [
    ...(little ? text('II') : text('MM')),
    ...w16(42),
    ...w32(8),
    ...w16(entries.length),
    for (final e in entries) ...e,
    ...w32(0),
  ];
}

List<int> _segment(int marker, List<int> body) => [
  0xFF,
  marker,
  ...u16(body.length + 2),
  ...body,
];

const List<int> _exifHeader = [0x45, 0x78, 0x69, 0x66, 0, 0];

/// A JPEG that never decodes but walks: SOI, optional metadata segments, the tables
/// and the frame header of a [width]×[height] picture, a scan with stuffed bytes and
/// a restart marker, EOI, and an optional [trailer].
Uint8List jpeg({
  int width = 640,
  int height = 480,
  bool jfif = true,
  List<int>? exif,
  List<int>? secondExif,
  bool xmp = false,
  bool comment = false,
  bool photoshop = false,
  bool makerNote = false,
  bool icc = true,
  bool adobe = false,
  List<int> trailer = const [],
}) => bytes([
  0xFF, 0xD8,
  if (jfif) ..._segment(0xE0, [...text('JFIF'), 0, 1, 1, 0, 0, 1, 0, 1, 0, 0]),
  if (exif != null) ..._segment(0xE1, [..._exifHeader, ...exif]),
  if (secondExif != null) ..._segment(0xE1, [..._exifHeader, ...secondExif]),
  if (xmp)
    ..._segment(0xE1, [
      ...text('http://ns.adobe.com/xap/1.0/'),
      0,
      ...text('<x/>'),
    ]),
  if (makerNote) ..._segment(0xE3, text('maker notes')),
  if (photoshop)
    ..._segment(0xED, [...text('Photoshop 3.0'), 0, ...text('caption')]),
  if (comment) ..._segment(0xFE, text('Oma Sien in de tuin')),
  if (icc) ..._segment(0xE2, [...text('ICC_PROFILE'), 0, 1, 1, 7, 7, 7]),
  if (adobe) ..._segment(0xEE, [...text('Adobe'), 0, 100, 0, 0, 0, 0, 1]),
  ..._segment(0xDB, [0, ...List.filled(64, 3)]),
  ..._segment(0xC0, [
    8,
    ...u16(height),
    ...u16(width),
    3,
    1,
    0x22,
    0,
    2,
    0x11,
    1,
    3,
    0x11,
    1,
  ]),
  ..._segment(0xC4, [0, ...List.filled(16, 0), 1]),
  ..._segment(0xDA, [3, 1, 0, 2, 0x11, 3, 0x11, 0, 63, 0]),
  // Scan data: stuffed 0xFF 0x00, a restart marker, plain bytes.
  1, 2, 0xFF, 0x00, 3, 0xFF, 0xD0, 4, 5, 0xFF, 0x00, 6,
  0xFF, 0xD9,
  ...trailer,
]);

/// The same picture with none of the metadata: what [cleanImage] has to produce.
Uint8List jpegClean({
  int width = 640,
  int height = 480,
  bool jfif = true,
  bool icc = true,
  bool adobe = false,
}) => jpeg(width: width, height: height, jfif: jfif, icc: icc, adobe: adobe);

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c ^= b;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
  }
  return c ^ 0xFFFFFFFF;
}

List<int> pngChunk(String type, List<int> body, {int? crc}) {
  final typed = [...text(type), ...body];
  return [...u32(body.length), ...typed, ...u32(crc ?? crc32(typed))];
}

/// A PNG that walks: IHDR, the chunks asked for, a couple of IDAT, IEND, a trailer.
Uint8List png({
  int width = 100,
  int height = 50,
  bool textChunk = false,
  bool xmp = false,
  List<int>? exif,
  bool time = false,
  bool iccp = true,
  bool unknownAncillary = false,
  bool unknownCritical = false,
  bool keepers = false,
  bool badCrc = false,
  List<int> trailer = const [],
}) => bytes([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  ...pngChunk('IHDR', [...u32(width), ...u32(height), 8, 2, 0, 0, 0]),
  if (exif != null) ...pngChunk('eXIf', exif),
  if (iccp) ...pngChunk('iCCP', [...text('sRGB'), 0, 0, 1, 2, 3]),
  if (textChunk)
    ...pngChunk('tEXt', [...text('Author'), 0, ...text('Oma Sien')]),
  if (xmp)
    ...pngChunk('iTXt', [
      ...text('XML:com.adobe.xmp'),
      0,
      0,
      0,
      0,
      0,
      ...text('<x/>'),
    ]),
  if (time) ...pngChunk('tIME', [7, 234, 10, 2, 9, 30, 0]),
  if (unknownAncillary) ...pngChunk('prVt', [1, 2, 3]),
  if (unknownCritical) ...pngChunk('PrVt', [1, 2, 3]),
  // Everything a picture needs and a cleaning must therefore keep.
  if (keepers) ...[
    ...pngChunk('gAMA', u32(45455)),
    ...pngChunk('cHRM', List.filled(32, 1)),
    ...pngChunk('sRGB', [0]),
    ...pngChunk('sBIT', [8, 8, 8]),
    ...pngChunk('pHYs', [...u32(2835), ...u32(2835), 1]),
    ...pngChunk('PLTE', [1, 2, 3, 4, 5, 6]),
    ...pngChunk('tRNS', [255, 128]),
    ...pngChunk('bKGD', [0]),
  ],
  ...pngChunk('IDAT', [1, 2, 3, 4, 5]),
  ...pngChunk('IDAT', [6, 7, 8], crc: badCrc ? 1 : null),
  ...pngChunk('IEND', []),
  ...trailer,
]);

List<int> _riffChunk(String type, List<int> body) => [
  ...text(type),
  ...u32le(body.length),
  ...body,
  if (body.length.isOdd) 0,
];

List<int> _w24(int v) => [v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF];

/// A WebP: extended (VP8X) with a lossless picture, or simple (a bare VP8 chunk).
Uint8List webp({
  int width = 300,
  int height = 200,
  bool extended = true,
  List<int>? exif,
  bool xmp = false,
  bool iccp = false,
  bool lossy = false,
  int scale = 0,
  List<int> trailer = const [],
}) {
  final image = lossy
      ? _riffChunk('VP8 ', [
          0,
          0,
          0,
          0x9D,
          0x01,
          0x2A,
          width & 0xFF,
          ((width >> 8) & 0x3F) | (scale << 6),
          height & 0xFF,
          ((height >> 8) & 0x3F) | (scale << 6),
          1,
          2,
          3,
        ])
      : _riffChunk('VP8L', [
          0x2F,
          ...u32le((width - 1) | ((height - 1) << 14)),
          9,
          9,
          9,
        ]);
  final flags =
      (iccp ? 0x20 : 0) | (exif != null ? 0x08 : 0) | (xmp ? 0x04 : 0);
  final body = [
    ...text('WEBP'),
    if (extended)
      ..._riffChunk('VP8X', [
        flags,
        0,
        0,
        0,
        ..._w24(width - 1),
        ..._w24(height - 1),
      ]),
    if (iccp) ..._riffChunk('ICCP', [1, 2, 3, 4]),
    ...image,
    if (exif != null) ..._riffChunk('EXIF', exif),
    if (xmp) ..._riffChunk('XMP ', text('<x/>')),
  ];
  return bytes([...text('RIFF'), ...u32le(body.length), ...body, ...trailer]);
}

/// A HEIC: an `ftyp` box with a HEIC brand, then something.
Uint8List heic({String brand = 'heic'}) => bytes([
  ...u32(24),
  ...text('ftyp'),
  ...text(brand),
  ...u32(0),
  ...text('mif1'),
  ...text('heic'),
  1,
  2,
  3,
  4,
]);
