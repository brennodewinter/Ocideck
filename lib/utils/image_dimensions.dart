// Lightweight image dimension reader — reads only the file header, no full
// decode. Used by the callout clip check to determine whether a target falls
// outside the visible image area under cover/zoom (#1853).
//
// PNG, JPEG, GIF, BMP and WebP are handled by their fixed header layout; any
// other format returns null and the clip check is skipped for that image.

import 'dart:io';
import 'dart:typed_data';

import 'log.dart';
import 'byte_readers.dart';

class ImageDimensions {
  final int width;
  final int height;
  const ImageDimensions(this.width, this.height);
  double get aspect => width / height;
}

/// Header reads are bounded because dimensions never require the image body.
const int kMaxImageHeaderBytes = 1024 * 1024;

/// Hoe vaak de bestandskop echt werd gelezen. Een cache-treffer telt niet
/// mee (#2685).
int debugImageDimensionFileReads = 0;

void debugResetImageDimensionCache() {
  debugImageDimensionFileReads = 0;
  _dimensionCache.clear();
}

class _CachedDimensions {
  const _CachedDimensions(this.mtimeMs, this.length, this.dims);
  final int mtimeMs;
  final int length;
  final ImageDimensions? dims;
}

final Map<String, _CachedDimensions> _dimensionCache = {};

/// Reads the pixel dimensions of the image at [path] from its header only.
/// Returns null when the file is missing, unreadable, or an unsupported format.
///
/// Herhaalde vragen voor hetzelfde bestand — een kwaliteitsronde per
/// toetsaanslag — lezen de kop niet opnieuw zolang stempel en grootte gelijk
/// blijven (#2685).
ImageDimensions? readImageDimensions(String path) {
  try {
    final stat = File(path).statSync();
    if (stat.type != FileSystemEntityType.file) return null;
    final cached = _touchDimensions(path);
    if (cached != null &&
        cached.mtimeMs == stat.modified.millisecondsSinceEpoch &&
        cached.length == stat.size) {
      return cached.dims;
    }
    debugImageDimensionFileReads++;
    final dims = _readHeader(path, stat.size);
    _storeDimensions(
      path,
      _CachedDimensions(stat.modified.millisecondsSinceEpoch, stat.size, dims),
    );
    return dims;
  } catch (e) {
    logError('readImageDimensions: failed to read $path', e);
    return null;
  }
}

ImageDimensions? _readHeader(String path, int length) {
  final handle = File(path).openSync();
  try {
    final bytes = handle.readSync(
      length < kMaxImageHeaderBytes ? length : kMaxImageHeaderBytes,
    );
    return imageDimensionsFromBytes(bytes);
  } finally {
    handle.closeSync();
  }
}

_CachedDimensions? _touchDimensions(String path) {
  final hit = _dimensionCache.remove(path);
  if (hit == null) return null;
  _dimensionCache[path] = hit;
  return hit;
}

void _storeDimensions(String path, _CachedDimensions entry) {
  _dimensionCache.remove(path);
  _dimensionCache[path] = entry;
  if (_dimensionCache.length > 256) {
    _dimensionCache.remove(_dimensionCache.keys.first);
  }
}

/// De breedte/hoogte-verhouding van een SVG uit zijn brontekst — uit
/// `width`/`height` op het root-element, anders uit de `viewBox`. Alleen de
/// verhouding is betrouwbaar: `width`/`height` mogen in elke eenheid staan,
/// en de `viewBox` zegt niets over pixels maar wél over de vorm (#2867).
/// `null` als de tekst geen bruikbare maat draagt.
double? svgAspectFromText(String text) {
  final svg = RegExp(r'<svg\b[^>]*>', caseSensitive: false).firstMatch(text);
  if (svg == null) return null;
  final tag = svg.group(0)!;
  double? attr(String name) {
    final m =
        RegExp(
          '$name\\s*=\\s*"([^"]*)"',
          caseSensitive: false,
        ).firstMatch(tag) ??
        RegExp("$name\\s*=\\s*'([^']*)'", caseSensitive: false).firstMatch(tag);
    if (m == null) return null;
    final raw = m.group(1)!.trim();
    // Een percentage of 'auto' zegt niets over een absolute maat.
    if (raw.isEmpty || raw.endsWith('%')) return null;
    return double.tryParse(
      RegExp(r'^-?[\d.]+(?:[eE][-+]?\d+)?').firstMatch(raw)?.group(0) ?? '',
    );
  }

  final w = attr('width');
  final h = attr('height');
  if (w != null && h != null && w > 0 && h > 0) return w / h;
  final box = RegExp(
    r'viewBox\s*=\s*"?\s*([-\d.eE]+)[,\s]+([-\d.eE]+)[,\s]+([-\d.eE]+)[,\s]+([-\d.eE]+)"?',
    caseSensitive: false,
  ).firstMatch(tag);
  if (box == null) return null;
  final bw = double.tryParse(box.group(3)!);
  final bh = double.tryParse(box.group(4)!);
  if (bw == null || bh == null || bw <= 0 || bh <= 0) return null;
  return bw / bh;
}

/// Zie [svgAspectFromText]; deze leest de bytes eerst als UTF-8.
double? svgAspectFromBytes(Uint8List bytes) =>
    svgAspectFromText(String.fromCharCodes(bytes));

/// Same as [readImageDimensions] but from in-memory bytes.
ImageDimensions? imageDimensionsFromBytes(Uint8List bytes) {
  if (bytes.length < 10) return null;
  // PNG: signature + IHDR (width at 16, height at 20, big-endian uint32).
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    if (bytes.length < 24) return null;
    final w = readUint32BE(bytes, 16);
    final h = readUint32BE(bytes, 20);
    if (w > 0 && h > 0) return ImageDimensions(w, h);
    return null;
  }
  // JPEG: scan markers for a SOF frame.
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return _jpegDimensions(bytes);
  // GIF: width at 6, height at 8 (little-endian uint16).
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    final w = readUint16LE(bytes, 6);
    final h = readUint16LE(bytes, 8);
    if (w > 0 && h > 0) return ImageDimensions(w, h);
    return null;
  }
  // BMP: width at 18, height at 22 (little-endian uint32).
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    if (bytes.length < 26) return null;
    final w = readUint32LE(bytes, 18);
    final h = readUint32LE(bytes, 22).abs(); // top-down bitmaps use negative
    if (w > 0 && h > 0) return ImageDimensions(w, h);
    return null;
  }
  // WebP: RIFF container with VP8 / VP8L / VP8X chunk.
  if (bytes.length >= 16 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46) {
    return _webpDimensions(bytes);
  }
  return null;
}

ImageDimensions? _jpegDimensions(Uint8List bytes) {
  var i = 2; // skip FFD8
  while (i < bytes.length - 9) {
    if (bytes[i] != 0xFF) return null;
    final marker = bytes[i + 1];
    // SOF0–SOF15 (excl. DHT C4, JPG C8, DAC CC).
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      final h = readUint16BE(bytes, i + 5);
      final w = readUint16BE(bytes, i + 7);
      if (w > 0 && h > 0) return ImageDimensions(w, h);
      return null;
    }
    // Skip padding / variable-length markers.
    if (marker == 0xD8 || marker == 0xD9) return null; // SOI/EOI without SOF
    if (i + 3 >= bytes.length) return null;
    final len = readUint16BE(bytes, i + 2);
    if (len < 2) return null;
    i += 2 + len;
  }
  return null;
}

ImageDimensions? _webpDimensions(Uint8List bytes) {
  if (bytes.length < 30) return null;
  final fourcc = String.fromCharCodes(bytes.sublist(12, 16));
  switch (fourcc) {
    case 'VP8X':
      final w = (readUint32LE(bytes, 24) & 0xFFFFFF) + 1;
      final h = (readUint32LE(bytes, 27) & 0xFFFFFF) + 1;
      if (w > 0 && h > 0) return ImageDimensions(w, h);
    case 'VP8L':
      if (bytes.length < 25) return null;
      final b = bytes[22] | (bytes[23] << 8) | (bytes[24] << 16);
      final w = (b & 0x3FFF) + 1;
      final h = ((b >> 14) & 0x3FFF) + 1;
      if (w > 0 && h > 0) return ImageDimensions(w, h);
    case 'VP8 ':
      final w = readUint16LE(bytes, 26);
      final h = readUint16LE(bytes, 28);
      if (w > 0 && h > 0) return ImageDimensions(w, h);
  }
  return null;
}
