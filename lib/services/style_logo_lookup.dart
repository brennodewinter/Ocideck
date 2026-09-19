// Stijlprofielen terugvinden op de inhoud van hun logo.
//
// Een import (presentatie of document) treft een beeld aan dat op elke dia of
// bladzijde staat. Staat datzelfde beeld al in een profiel, dan is dat het
// bewijs dat het een bekend logo is — en de kans om dat profiel te hergebruiken
// in plaats van er een tweede naast te zetten. De hash is leidend, niet het
// pad: hetzelfde beeld kan onder verschillende namen bewaard zijn.

import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../models/settings.dart';
import '../utils/bundled_asset.dart';
import '../utils/content_hash.dart';
import '../utils/log.dart';
import 'file_service.dart' show readStyleLogoBytes;

/// De profielen uit [profiles] op de SHA-256 van het logo dat [pathOf]
/// aanwijst — het presentatielogo, of het documentlogo. Een profiel zonder
/// dat logo, of met een onleesbaar logo, komt niet in de kaart; bij twee
/// profielen met hetzelfde beeld wint het eerste.
Future<Map<String, ThemeProfile>> styleProfilesByLogoHash(
  Iterable<ThemeProfile> profiles, {
  required String? Function(ThemeProfile profile) pathOf,
}) async {
  final result = <String, ThemeProfile>{};
  for (final profile in profiles) {
    final path = pathOf(profile)?.trim();
    if (path == null || path.isEmpty) continue;
    try {
      final Uint8List? bytes;
      if (isBundledAssetPath(path)) {
        final data = await rootBundle.load(bundledAssetKey(path));
        bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } else {
        bytes = await readStyleLogoBytes(path);
      }
      if (bytes != null && bytes.isNotEmpty) {
        result.putIfAbsent(sha256Hex(bytes), () => profile);
      }
    } on Exception catch (e, s) {
      logError('styleProfilesByLogoHash: stijlprofiellogo vergelijken', e, s);
    }
  }
  return result;
}
