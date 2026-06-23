import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Average colour of a decoded image, cached by path + last-modified time so
/// the quality pass can re-run cheaply on every edit. Used to estimate the
/// background a title slide's text sits on (see `title_contrast.dart`).
final Map<String, _CachedAverage> _cache = {};

class _CachedAverage {
  final int mtimeMs;
  final Color? color;
  const _CachedAverage(this.mtimeMs, this.color);
}

/// Decodes [resolvedPath] downsampled to a small thumbnail and returns its
/// average opaque colour, or `null` when the file is missing or undecodable.
Future<Color?> averageImageColor(String resolvedPath) async {
  final file = File(resolvedPath);
  int mtimeMs;
  try {
    mtimeMs = (await file.lastModified()).millisecondsSinceEpoch;
  } catch (_) {
    return null;
  }

  final cached = _cache[resolvedPath];
  if (cached != null && cached.mtimeMs == mtimeMs) return cached.color;

  Color? result;
  try {
    final bytes = await file.readAsBytes();
    // 48×48 is plenty for an average and keeps decode + scan negligible.
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: 48,
      targetHeight: 48,
    );
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    image.dispose();
    codec.dispose();
    if (data != null) result = _averageOf(data);
  } catch (_) {
    result = null;
  }

  _cache[resolvedPath] = _CachedAverage(mtimeMs, result);
  return result;
}

Color _averageOf(ByteData data) {
  final bytes = data.buffer.asUint8List();
  // Skip fully transparent pixels so cut-outs don't drag the average to black.
  var r = 0, g = 0, b = 0, count = 0;
  for (var i = 0; i + 3 < bytes.length; i += 4) {
    if (bytes[i + 3] == 0) continue;
    r += bytes[i];
    g += bytes[i + 1];
    b += bytes[i + 2];
    count++;
  }
  if (count == 0) return const Color(0xFF000000);
  return Color.fromARGB(
    255,
    (r / count).round(),
    (g / count).round(),
    (b / count).round(),
  );
}
