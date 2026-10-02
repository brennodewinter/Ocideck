/// What a form does with a photo before it is hashed, sealed or sent
/// (FORM_INTAKE.md §5.5): decide what it is from its **magic bytes**, take the
/// personal data out of it, cut off everything after the image, and say how wide it
/// is *as shown*.
///
/// Phones put the position of the photo, the time, the serial number of the device
/// and sometimes a name inside it (EXIF, XMP, PNG text chunks). The Kookboek asks for
/// "the original file", which was read as "the original bytes"; what it needs is
/// resolution and a colour profile. So [cleanImage] strips **at the segment level, with
/// no re-encoding** — the picture itself is not touched, so nothing is lost but the
/// metadata — and keeps what the picture needs to look right: the colour profile and
/// the orientation (as a minimal EXIF holding only the orientation).
///
/// Everything here is pure functions over bytes, so the app, the web form shell and a
/// server share them. What is *not* done here is the full decode that proves a file
/// is a real picture and not a polyglot with a valid header: that needs an image
/// decoder, which the app has and this package does not. The cleaned bytes are what
/// the decoder then gets.
///
/// HEIC is the exception (decision D4): it is only recognised, never opened.
library;

import 'dart:typed_data';

/// The picture formats a form accepts, decided from the bytes and never from a file
/// name.
enum FormImageKind {
  jpeg('jpg'),
  png('png'),
  webp('webp'),
  heic('heic');

  const FormImageKind(this.extension);

  /// The extension a file of this kind gets in a package (§5.4).
  final String extension;
}

/// Which kind of file [bytes] is, or null when it is none of the four.
///
/// A HEIC is recognised by its container: an `ftyp` box whose major brand is one of
/// the HEIC family. AVIF and other `ftyp` files are *not* HEIC.
FormImageKind? sniffImageKind(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return FormImageKind.jpeg;
  }
  if (bytes.length >= 8 && _matches(bytes, 0, _pngSignature)) {
    return FormImageKind.png;
  }
  if (bytes.length >= 12 &&
      _ascii(bytes, 0, 'RIFF') &&
      _ascii(bytes, 8, 'WEBP')) {
    return FormImageKind.webp;
  }
  if (bytes.length >= 12 && _ascii(bytes, 4, 'ftyp')) {
    final brand = String.fromCharCodes(bytes.sublist(8, 12));
    if (_heicBrands.contains(brand)) return FormImageKind.heic;
  }
  return null;
}

const Set<String> _heicBrands = {
  'heic',
  'heix',
  'hevc',
  'hevx',
  'heim',
  'heis',
  'hevm',
  'hevs',
  'mif1',
  'msf1',
};

const List<int> _pngSignature = [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
];

bool _matches(Uint8List b, int at, List<int> expected) {
  if (at + expected.length > b.length) return false;
  for (var i = 0; i < expected.length; i++) {
    if (b[at + i] != expected[i]) return false;
  }
  return true;
}

bool _ascii(Uint8List b, int at, String text) =>
    _matches(b, at, text.codeUnits);

/// What [cleanImage] found in a picture and what is left of it.
class FormImageReport {
  const FormImageReport({
    required this.kind,
    required this.bytes,
    this.width,
    this.height,
    this.orientation,
    this.removed = const FormImageRemoved(),
  });

  final FormImageKind kind;

  /// The picture without its personal data and without anything after its end.
  /// For a HEIC these are the original bytes.
  final Uint8List bytes;

  /// As stored. Null for a HEIC, which is not opened.
  final int? width;
  final int? height;

  /// The EXIF orientation, 1–8, or null when there was none.
  final int? orientation;

  /// What was taken out.
  final FormImageRemoved removed;

  /// Whether this file could not be measured or cleaned: a HEIC kept as it is.
  bool get unverified => kind == FormImageKind.heic;

  /// The width as it is **shown**: a photo of 2400×1800 with orientation 6 is shown
  /// 1800 wide (§5.5).
  int? get displayedWidth {
    final o = orientation;
    return o != null && o >= 5 && o <= 8 ? height : width;
  }

  int? get displayedHeight {
    final o = orientation;
    return o != null && o >= 5 && o <= 8 ? width : height;
  }
}

/// What a cleaning took out; each flag is true when that kind of thing was there.
class FormImageRemoved {
  const FormImageRemoved({
    this.gps = false,
    this.exif = false,
    this.xmp = false,
    this.text = false,
    this.other = false,
    this.trailerBytes = 0,
  });

  /// A GPS position was in the EXIF.
  final bool gps;

  /// Any EXIF at all (capture time, device, owner).
  final bool exif;
  final bool xmp;

  /// PNG text chunks or a JPEG comment.
  final bool text;

  /// Other application segments and unknown chunks.
  final bool other;

  /// Bytes after the end-of-image marker (JPEG EOI, PNG IEND, the end of the WebP).
  final int trailerBytes;

  /// Whether the file held anything that was taken out.
  bool get any => gps || exif || xmp || text || other || trailerBytes > 0;

  FormImageRemoved merge(FormImageRemoved o) => FormImageRemoved(
    gps: gps || o.gps,
    exif: exif || o.exif,
    xmp: xmp || o.xmp,
    text: text || o.text,
    other: other || o.other,
    trailerBytes: trailerBytes + o.trailerBytes,
  );
}

/// Cleans [bytes] and reports on them, or returns null when the file is not a
/// well-formed picture of its kind (a bad signature, a truncated segment, a PNG chunk
/// with a wrong checksum). A null is a refusal: the caller says the file is not a
/// usable photo.
///
/// Never throws.
FormImageReport? cleanImage(Uint8List bytes) {
  final kind = sniffImageKind(bytes);
  if (kind == null) return null;
  try {
    return switch (kind) {
      FormImageKind.jpeg => _cleanJpeg(bytes),
      FormImageKind.png => _cleanPng(bytes),
      FormImageKind.webp => _cleanWebp(bytes),
      FormImageKind.heic => FormImageReport(kind: kind, bytes: bytes),
    };
  } on RangeError {
    return null;
  } on _Malformed {
    return null;
  }
}

class _Malformed implements Exception {
  const _Malformed(this.why);

  final String why;

  @override
  String toString() => 'malformed image: $why';
}

// ── EXIF ────────────────────────────────────────────────────────────────────

/// What the EXIF of a photo says that the form cares about.
class _Exif {
  const _Exif({
    this.orientation,
    this.hasGps = false,
    this.onlyOrientation = false,
  });

  final int? orientation;
  final bool hasGps;

  /// Whether the EXIF holds the orientation and nothing else — exactly what a
  /// cleaning writes back, so reading it again is not "removing data".
  final bool onlyOrientation;
}

/// Reads orientation and the presence of a GPS block from a TIFF structure
/// (`II*\0`/`MM\0*`), as found inside EXIF. Tolerant: anything it cannot read gives
/// "nothing known" — the data is removed either way.
_Exif _readExif(Uint8List tiff) {
  if (tiff.length < 8) return const _Exif();
  final little = tiff[0] == 0x49 && tiff[1] == 0x49;
  if (!little && !(tiff[0] == 0x4D && tiff[1] == 0x4D)) return const _Exif();
  final data = ByteData.sublistView(tiff);
  int u16(int at) => data.getUint16(at, little ? Endian.little : Endian.big);
  int u32(int at) => data.getUint32(at, little ? Endian.little : Endian.big);
  try {
    if (u16(2) != 42) return const _Exif();
    final ifd = u32(4);
    if (ifd + 2 > tiff.length) return const _Exif();
    final count = u16(ifd);
    int? orientation;
    var gps = false;
    for (var i = 0; i < count; i++) {
      final entry = ifd + 2 + i * 12;
      if (entry + 12 > tiff.length) break;
      final tag = u16(entry);
      if (tag == 0x0112 && u16(entry + 2) == 3 && u32(entry + 4) == 1) {
        orientation = u16(entry + 8);
      } else if (tag == 0x8825) {
        gps = true;
      }
    }
    if (orientation != null && (orientation < 1 || orientation > 8)) {
      orientation = null;
    }
    final next = ifd + 2 + count * 12;
    final only =
        count == 1 &&
        orientation != null &&
        next + 4 <= tiff.length &&
        u32(next) == 0;
    return _Exif(orientation: orientation, hasGps: gps, onlyOrientation: only);
  } on RangeError {
    return const _Exif();
  }
}

/// A TIFF structure that holds one thing, the orientation (big endian): 8 header
/// bytes, one directory entry, no next directory.
Uint8List _orientationTiff(int orientation) {
  final out = ByteData(26);
  out.setUint8(0, 0x4D);
  out.setUint8(1, 0x4D);
  out.setUint16(2, 42);
  out.setUint32(4, 8);
  out.setUint16(8, 1);
  out.setUint16(10, 0x0112);
  out.setUint16(12, 3);
  out.setUint32(14, 1);
  out.setUint16(18, orientation);
  out.setUint32(22, 0);
  return out.buffer.asUint8List();
}

// ── JPEG ────────────────────────────────────────────────────────────────────

FormImageReport _cleanJpeg(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(const [0xFF, 0xD8]);
  var removed = const FormImageRemoved();
  int? width;
  int? height;
  int? orientation;

  var i = 2;
  var sawEoi = false;
  while (i < b.length && !sawEoi) {
    // A marker: 0xFF (fill bytes allowed) then the code.
    if (b[i] != 0xFF) throw const _Malformed('jpeg marker expected');
    while (i < b.length && b[i] == 0xFF) {
      i++;
    }
    if (i >= b.length) throw const _Malformed('jpeg ends in a marker');
    final marker = b[i++];

    if (marker == 0xD9) {
      out.add(const [0xFF, 0xD9]);
      sawEoi = true;
      break;
    }
    if (marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0xD8) {
      throw const _Malformed('jpeg marker outside a scan');
    }
    if (i + 2 > b.length) throw const _Malformed('jpeg segment truncated');
    final length = (b[i] << 8) | b[i + 1];
    // A length that is too small or runs past the end makes the slices below
    // fail with a RangeError, which [cleanImage] turns into a refusal.

    final body = Uint8List.sublistView(b, i + 2, i + length);
    final segment = Uint8List.sublistView(
      b,
      i - 2,
      i + length,
    ); // FF xx len data
    i += length;

    // Frame headers carry the size.
    if (_isSof(marker)) {
      if (body.length < 5) throw const _Malformed('jpeg frame header');
      height = (body[1] << 8) | body[2];
      width = (body[3] << 8) | body[4];
      out.add(segment);
      continue;
    }

    if (marker == 0xDA) {
      // The scan: the header, then entropy-coded data up to the next real marker.
      out.add(segment);
      final start = i;
      while (i < b.length) {
        if (b[i] == 0xFF) {
          if (i + 1 >= b.length) throw const _Malformed('jpeg scan truncated');
          final next = b[i + 1];
          if (next == 0x00 || (next >= 0xD0 && next <= 0xD7)) {
            i += 2;
            continue;
          }
          if (next == 0xFF) {
            i++;
            continue;
          }
          break;
        }
        i++;
      }
      if (i >= b.length) throw const _Malformed('jpeg has no end marker');
      out.add(Uint8List.sublistView(b, start, i));
      continue;
    }

    if (marker == 0xE1) {
      // APP1: EXIF or XMP — both go; what the picture needs of EXIF is rewritten.
      if (_startsWith(body, _exifHeader)) {
        final exif = _readExif(Uint8List.sublistView(body, _exifHeader.length));
        removed = removed.merge(
          FormImageRemoved(exif: !exif.onlyOrientation, gps: exif.hasGps),
        );
        orientation ??= exif.orientation;
      } else if (_startsWith(body, _xmpHeader) ||
          _startsWith(body, _xmpExtensionHeader)) {
        removed = removed.merge(const FormImageRemoved(xmp: true));
      } else {
        removed = removed.merge(const FormImageRemoved(other: true));
      }
      continue;
    }
    if (marker == 0xFE) {
      removed = removed.merge(const FormImageRemoved(text: true));
      continue;
    }
    if (marker >= 0xE0 && marker <= 0xEF) {
      // APP0 (JFIF), APP2 (the ICC profile) and APP14 (Adobe colour transform)
      // are part of how the picture is drawn; the rest (APP3–APP13, APP15 — a
      // Photoshop block with a caption, a device's maker notes) is not.
      if (marker == 0xE0 || marker == 0xE2 || marker == 0xEE) {
        out.add(segment);
      } else {
        removed = removed.merge(const FormImageRemoved(other: true));
      }
      continue;
    }
    // Everything else (DQT, DHT, DRI, SOFn handled above…) belongs to the picture.
    out.add(segment);
  }
  if (!sawEoi) throw const _Malformed('jpeg has no end marker');

  final trailer = b.length - i;
  removed = removed.merge(FormImageRemoved(trailerBytes: trailer));
  if (width == null || height == null) {
    throw const _Malformed('jpeg has no frame header');
  }

  var bytes = out.toBytes();
  if (orientation != null && orientation != 1) {
    bytes = _insertJpegOrientation(bytes, orientation);
  }
  return FormImageReport(
    kind: FormImageKind.jpeg,
    bytes: bytes,
    width: width,
    height: height,
    orientation: orientation,
    removed: removed,
  );
}

bool _isSof(int marker) =>
    marker >= 0xC0 &&
    marker <= 0xCF &&
    marker != 0xC4 &&
    marker != 0xC8 &&
    marker != 0xCC;

const List<int> _exifHeader = [0x45, 0x78, 0x69, 0x66, 0x00, 0x00]; // Exif\0\0
final List<int> _xmpHeader = 'http://ns.adobe.com/xap/1.0/\x00'.codeUnits;
final List<int> _xmpExtensionHeader =
    'http://ns.adobe.com/xmp/extension/\x00'.codeUnits;

bool _startsWith(Uint8List b, List<int> prefix) => _matches(b, 0, prefix);

/// Puts a minimal EXIF APP1 right after the SOI (and after a JFIF APP0 when there is
/// one — the JFIF segment has to come first, by the standard).
Uint8List _insertJpegOrientation(Uint8List jpeg, int orientation) {
  final tiff = _orientationTiff(orientation);
  final bodyLength = _exifHeader.length + tiff.length;
  final segment = BytesBuilder()
    ..add(const [0xFF, 0xE1])
    ..add([(bodyLength + 2) >> 8, (bodyLength + 2) & 0xFF])
    ..add(_exifHeader)
    ..add(tiff);

  var at = 2;
  if (jpeg.length > 4 && jpeg[2] == 0xFF && jpeg[3] == 0xE0) {
    at = 4 + ((jpeg[4] << 8) | jpeg[5]);
  }
  final out = BytesBuilder()
    ..add(Uint8List.sublistView(jpeg, 0, at))
    ..add(segment.toBytes())
    ..add(Uint8List.sublistView(jpeg, at));
  return out.toBytes();
}

// ── PNG ─────────────────────────────────────────────────────────────────────

/// The chunks a picture needs. Everything else — text, time, EXIF and any unknown
/// ancillary chunk — is dropped; an unknown *critical* chunk makes the file refused.
const Set<String> _pngKeep = {
  'IHDR',
  'PLTE',
  'IDAT',
  'IEND',
  'tRNS',
  'gAMA',
  'cHRM',
  'sRGB',
  'iCCP',
  'sBIT',
  'pHYs',
  'bKGD',
  'hIST',
  'sPLT',
  'cICP',
  'mDCV',
  'cLLI',
  'acTL',
  'fcTL',
  'fdAT',
};

FormImageReport _cleanPng(Uint8List b) {
  final out = BytesBuilder(copy: false)..add(_pngSignature);
  var removed = const FormImageRemoved();
  int? width;
  int? height;
  int? orientation;
  var i = _pngSignature.length;
  var sawIend = false;
  var first = true;

  while (i + 12 <= b.length && !sawIend) {
    final data = ByteData.sublistView(b);
    final length = data.getUint32(i);
    if (length > 0x7FFFFFFF || i + 12 + length > b.length) {
      throw const _Malformed('png chunk truncated');
    }
    final type = String.fromCharCodes(b.sublist(i + 4, i + 8));
    final body = Uint8List.sublistView(b, i + 8, i + 8 + length);
    final crc = data.getUint32(i + 8 + length);
    if (_crc32(b, i + 4, i + 8 + length) != crc) {
      throw const _Malformed('png checksum');
    }
    final whole = Uint8List.sublistView(b, i, i + 12 + length);
    i += 12 + length;

    if (first && type != 'IHDR') {
      throw const _Malformed('png starts without IHDR');
    }
    first = false;
    if (type == 'IHDR') {
      if (length != 13) throw const _Malformed('png header');
      width = ByteData.sublistView(body).getUint32(0);
      height = ByteData.sublistView(body).getUint32(4);
    }
    if (type == 'eXIf') {
      final exif = _readExif(body);
      removed = removed.merge(
        FormImageRemoved(exif: !exif.onlyOrientation, gps: exif.hasGps),
      );
      orientation ??= exif.orientation;
      continue;
    }
    if (type == 'tEXt' || type == 'zTXt' || type == 'iTXt') {
      final xmp =
          type == 'iTXt' && _startsWith(body, 'XML:com.adobe.xmp'.codeUnits);
      removed = removed.merge(
        xmp
            ? const FormImageRemoved(xmp: true)
            : const FormImageRemoved(text: true),
      );
      continue;
    }
    if (_pngKeep.contains(type)) {
      out.add(whole);
      if (type == 'IEND') sawIend = true;
      continue;
    }
    // The first letter of a chunk name tells critical (upper) from ancillary
    // (lower): an unknown critical chunk cannot be dropped without breaking the
    // picture, so the file is refused.
    if (type.codeUnitAt(0) < 0x61) throw const _Malformed('png critical chunk');
    removed = removed.merge(const FormImageRemoved(other: true));
  }
  if (!sawIend || width == null || height == null) {
    throw const _Malformed('png has no end');
  }
  removed = removed.merge(FormImageRemoved(trailerBytes: b.length - i));

  var bytes = out.toBytes();
  if (orientation != null && orientation != 1) {
    bytes = _insertPngOrientation(bytes, orientation);
  }
  return FormImageReport(
    kind: FormImageKind.png,
    bytes: bytes,
    width: width,
    height: height,
    orientation: orientation,
    removed: removed,
  );
}

/// An `eXIf` chunk holding only the orientation, placed right after `IHDR` (a
/// position every decoder accepts).
Uint8List _insertPngOrientation(Uint8List png, int orientation) {
  final tiff = _orientationTiff(orientation);
  final chunk = _pngChunk('eXIf', tiff);
  final afterIhdr = _pngSignature.length + 12 + 13;
  return (BytesBuilder()
        ..add(Uint8List.sublistView(png, 0, afterIhdr))
        ..add(chunk)
        ..add(Uint8List.sublistView(png, afterIhdr)))
      .toBytes();
}

Uint8List _pngChunk(String type, Uint8List body) {
  final out = ByteData(12 + body.length);
  out.setUint32(0, body.length);
  final bytes = out.buffer.asUint8List();
  bytes.setRange(4, 8, type.codeUnits);
  bytes.setRange(8, 8 + body.length, body);
  out.setUint32(8 + body.length, _crc32(bytes, 4, 8 + body.length));
  return bytes;
}

Uint32List _crcTable() {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}

final Uint32List _crc = _crcTable();

/// The CRC-32 of `bytes[start, end)`, as PNG uses it.
int _crc32(Uint8List bytes, int start, int end) {
  var c = 0xFFFFFFFF;
  for (var i = start; i < end; i++) {
    c = _crc[(c ^ bytes[i]) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}

// ── WebP ────────────────────────────────────────────────────────────────────

FormImageReport _cleanWebp(Uint8List b) {
  final data = ByteData.sublistView(b);
  final riffSize = data.getUint32(4, Endian.little);
  // The RIFF size counts everything after its own field; bytes past that are a
  // trailer, and a size beyond the file is a truncated file.
  final end = 8 + riffSize;
  // A size beyond the file makes a chunk run past the end: a RangeError, caught.
  if (riffSize < 4) throw const _Malformed('webp size');
  var removed = FormImageRemoved(trailerBytes: b.length - end);

  final chunks = BytesBuilder(copy: false);
  int? width;
  int? height;
  int? orientation;
  Uint8List? vp8x;
  var i = 12;
  while (i + 8 <= end) {
    final type = String.fromCharCodes(b.sublist(i, i + 4));
    final size = data.getUint32(i + 4, Endian.little);
    final padded = size + (size & 1);
    if (i + 8 + size > end) throw const _Malformed('webp chunk truncated');
    final body = Uint8List.sublistView(b, i + 8, i + 8 + size);
    final whole = Uint8List.sublistView(
      b,
      i,
      i + 8 + padded > end ? end : i + 8 + padded,
    );
    i += 8 + padded;

    switch (type) {
      case 'VP8X':
        if (size < 10) throw const _Malformed('webp VP8X');
        vp8x = Uint8List.fromList(whole);
        width = 1 + (body[4] | (body[5] << 8) | (body[6] << 16));
        height = 1 + (body[7] | (body[8] << 8) | (body[9] << 16));
      case 'EXIF':
        final exif = _readExif(
          _startsWith(body, _exifHeader)
              ? Uint8List.sublistView(body, _exifHeader.length)
              : body,
        );
        removed = removed.merge(
          FormImageRemoved(exif: !exif.onlyOrientation, gps: exif.hasGps),
        );
        orientation ??= exif.orientation;
      case 'XMP ':
        removed = removed.merge(const FormImageRemoved(xmp: true));
      case 'VP8 ':
        if (width == null && size >= 10) {
          width = (body[6] | (body[7] << 8)) & 0x3FFF;
          height = (body[8] | (body[9] << 8)) & 0x3FFF;
        }
        chunks.add(whole);
      case 'VP8L':
        if (width == null && size >= 5 && body[0] == 0x2F) {
          final bits =
              body[1] | (body[2] << 8) | (body[3] << 16) | (body[4] << 24);
          width = 1 + (bits & 0x3FFF);
          height = 1 + ((bits >> 14) & 0x3FFF);
        }
        chunks.add(whole);
      default:
        chunks.add(whole);
    }
  }
  if (width == null || height == null) {
    throw const _Malformed('webp has no size');
  }

  // Rebuild: RIFF header, VP8X first (with the EXIF and XMP flags cleared, and the
  // EXIF flag set again if the orientation is written back), then the chunks. A
  // simple file has no VP8X; one is made when the orientation has to be kept,
  // because an EXIF chunk is only allowed in the extended format.
  final body = BytesBuilder(copy: false)..add('WEBP'.codeUnits);
  final wantsExif = orientation != null && orientation != 1;
  if (vp8x != null) {
    final x = Uint8List.fromList(vp8x);
    x[8] = (x[8] & ~0x0C & 0xFF) | (wantsExif ? 0x08 : 0);
    body.add(x);
  } else if (wantsExif) {
    final x = ByteData(18)
      ..setUint32(4, 10, Endian.little)
      ..setUint8(8, 0x08);
    // A simple file is at most 16384 pixels either way, so the third byte of
    // each size is always 0.
    final w = width - 1;
    final h = height - 1;
    final bytes = x.buffer.asUint8List()
      ..setRange(0, 4, 'VP8X'.codeUnits)
      ..[12] = w & 0xFF
      ..[13] = (w >> 8) & 0xFF
      ..[15] = h & 0xFF
      ..[16] = (h >> 8) & 0xFF;
    body.add(bytes);
  }
  body.add(chunks.toBytes());
  if (wantsExif) {
    final tiff = _orientationTiff(orientation);
    final exifChunk = ByteData(8 + tiff.length)
      ..setUint32(4, tiff.length, Endian.little);
    body.add(
      exifChunk.buffer.asUint8List()
        ..setRange(0, 4, 'EXIF'.codeUnits)
        ..setRange(8, 8 + tiff.length, tiff),
    );
  }
  final payload = body.toBytes();
  final out = ByteData(8 + payload.length);
  final result = out.buffer.asUint8List()
    ..setRange(0, 4, 'RIFF'.codeUnits)
    ..setRange(8, 8 + payload.length, payload);
  out.setUint32(4, payload.length, Endian.little);
  return FormImageReport(
    kind: FormImageKind.webp,
    bytes: result,
    width: width,
    height: height,
    orientation: orientation,
    removed: removed,
  );
}
