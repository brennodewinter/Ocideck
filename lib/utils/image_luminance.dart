import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'log.dart';

/// Average colour of a decoded image, cached by path + last-modified time +
/// length so the quality pass can re-run cheaply on every edit. Used to
/// estimate the background a title slide's text sits on (see
/// `title_contrast.dart`).
final Map<String, _CachedAverage> _cache = {};

/// Hard cap so a long session that cycles through many distinct images can't
/// grow the cache without bound; oldest entries are evicted first.
const int _maxCacheEntries = 256;

class _CachedAverage {
  final int mtimeMs;
  final int length;
  final Color? color;
  const _CachedAverage(this.mtimeMs, this.length, this.color);
}

/// Decodes [resolvedPath] downsampled to a small thumbnail and returns its
/// average opaque colour, or `null` when the file is missing or undecodable.
Future<Color?> averageImageColor(String resolvedPath) async {
  final file = File(resolvedPath);
  int mtimeMs;
  int length;
  try {
    final stat = await file.stat();
    mtimeMs = stat.modified.millisecondsSinceEpoch;
    length = stat.size;
  } catch (e) {
    logWarning('averageImageColor: stat failed', e);
    return null;
  }

  final cached = _cache[resolvedPath];
  // Invalidate on both mtime and length: in-place overwrites that preserve the
  // mtime (or collide within one millisecond) almost always change the size.
  if (cached != null && cached.mtimeMs == mtimeMs && cached.length == length) {
    return cached.color;
  }

  Color? result;
  try {
    final bytes = await file.readAsBytes();
    // 48×48 is plenty for an average and keeps decode + scan negligible.
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 48,
      targetHeight: 48,
    );
    try {
      final frame = await codec.getNextFrame();
      final image = frame.image;
      try {
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        if (data != null) result = _averageOf(data);
      } finally {
        image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } catch (e) {
    logError('averageImageColor: decode failed', e);
    result = null;
  }

  if (_cache.length >= _maxCacheEntries) {
    _cache.remove(_cache.keys.first);
  }
  _cache[resolvedPath] = _CachedAverage(mtimeMs, length, result);
  return result;
}

Color _averageOf(ByteData data) {
  final bytes = data.buffer.asUint8List();
  // rawRgba is premultiplied-alpha, so semi-transparent pixels carry darkened
  // RGB. Un-premultiply to recover the straight colour, and skip fully
  // transparent pixels so cut-outs don't drag the average to black.
  var r = 0.0, g = 0.0, b = 0.0;
  var count = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    final a = bytes[i + 3];
    if (a == 0) continue;
    if (a == 255) {
      r += bytes[i];
      g += bytes[i + 1];
      b += bytes[i + 2];
    } else {
      final inv = 255.0 / a;
      r += bytes[i] * inv;
      g += bytes[i + 1] * inv;
      b += bytes[i + 2] * inv;
    }
    count++;
  }
  if (count == 0) return Colors.black;
  return Color.fromARGB(
    255,
    (r / count).round().clamp(0, 255),
    (g / count).round().clamp(0, 255),
    (b / count).round().clamp(0, 255),
  );
}
