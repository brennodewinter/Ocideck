// Lightweight image dimension reader — reads only the file header, no full
// decode. Used by the callout clip check to determine whether a target falls
// outside the visible image area under cover/zoom (#1853).
//
// PNG, JPEG, GIF, BMP and WebP are handled by their fixed header layout; any
// other format returns null and the clip check is skipped for that image.

import 'dart:io';
import 'dart:typed_data';

import 'log.dart';

class ImageDimensions {
  final int width;
  final int height;
  const ImageDimensions(this.width, this.height);
  double get aspect => width / height;
}

/// Reads the pixel dimensions of the image at [path] from its header only.
/// Returns null when the file is missing, unreadable, or an unsupported format.
ImageDimensions? readImageDimensions(String path) {
  try {
    final file = File(path);
    if (!file.existsSync()) return null;
    final bytes = file.readAsBytesSync();
    return imageDimensionsFromBytes(bytes);
  } catch (e) {
    logError('readImageDimensions: failed to read $path', e);
    return null;
  }
}

/// Same as [readImageDimensions] but from in-memory bytes.
ImageDimensions? imageDimensionsFromBytes(Uint8List bytes) {
  if (bytes.length < 10) return null;
  // PNG: signature + IHDR (width at 16, height at 20, big-endian uint32).
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    if (bytes.length < 24) return null;
    final w = _readUint32BE(bytes, 16);
    final h = _readUint32BE(bytes, 20);
    if (w > 0 && h > 0) return ImageDimensions(w, h);
    return null;
  }
  // JPEG: scan markers for a SOF frame.
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) return _jpegDimensions(bytes);
  // GIF: width at 6, height at 8 (little-endian uint16).
  if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) {
    final w = _readUint16LE(bytes, 6);
    final h = _readUint16LE(bytes, 8);
    if (w > 0 && h > 0) return ImageDimensions(w, h);
    return null;
  }
  // BMP: width at 18, height at 22 (little-endian uint32).
  if (bytes[0] == 0x42 && bytes[1] == 0x4D) {
    if (bytes.length < 26) return null;
    final w = _readUint32LE(bytes, 18);
    final h = _readUint32LE(bytes, 22).abs(); // top-down bitmaps use negative
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
      final h = _readUint16BE(bytes, i + 5);
      final w = _readUint16BE(bytes, i + 7);
      if (w > 0 && h > 0) return ImageDimensions(w, h);
      return null;
    }
    // Skip padding / variable-length markers.
    if (marker == 0xD8 || marker == 0xD9) return null; // SOI/EOI without SOF
    if (i + 3 >= bytes.length) return null;
    final len = _readUint16BE(bytes, i + 2);
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
      final w = (_readUint32LE(bytes, 24) & 0xFFFFFF) + 1;
      final h = (_readUint32LE(bytes, 27) & 0xFFFFFF) + 1;
      if (w > 0 && h > 0) return ImageDimensions(w, h);
    case 'VP8L':
      if (bytes.length < 25) return null;
      final b = bytes[22] | (bytes[23] << 8) | (bytes[24] << 16);
      final w = (b & 0x3FFF) + 1;
      final h = ((b >> 14) & 0x3FFF) + 1;
      if (w > 0 && h > 0) return ImageDimensions(w, h);
    case 'VP8 ':
      final w = _readUint16LE(bytes, 26);
      final h = _readUint16LE(bytes, 28);
      if (w > 0 && h > 0) return ImageDimensions(w, h);
  }
  return null;
}

int _readUint16BE(Uint8List b, int o) => (b[o] << 8) | b[o + 1];
int _readUint16LE(Uint8List b, int o) => b[o] | (b[o + 1] << 8);
int _readUint32BE(Uint8List b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
int _readUint32LE(Uint8List b, int o) =>
    b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24);
