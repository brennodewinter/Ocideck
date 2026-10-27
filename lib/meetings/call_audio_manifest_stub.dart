// Web-helft: geen bestandssysteem — de manifest-JSON ligt daar als tweede
// `mem:`-asset in de WebAssetStore, gezet door de sessie zelf onder de naam
// `<wav-sleutel>.sources.json`, zodat hij bij de duurzame wav terug te
// vinden is.
import 'dart:convert';

import '../services/web_asset_store.dart';

Future<void> writeCallSources(String stagingDir, String json) async {}

/// Dezelfde leeskant als de io-helft (#2530), maar dan over de `mem:`-
/// assetstore: [wavPath] is de `mem:`-sleutel van de mix-wav, het manifest
/// draagt diens sleutel in zijn naam. Dezelfde versie-gate — een provenance
/// die we niet zeker weten claimen we niet.
Map<String, Object?>? readCallSources(String wavPath) {
  try {
    final path = WebAssetStore.pathForName('$wavPath.sources.json');
    if (path == null) return null;
    final bytes = WebAssetStore.bytesFor(path);
    if (bytes == null) return null;
    final decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map<String, Object?> && decoded['version'] == 1
        ? decoded
        : null;
  } on Object {
    return null;
  }
}
