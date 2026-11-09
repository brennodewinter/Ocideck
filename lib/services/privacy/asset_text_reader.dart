import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../../utils/project_path.dart';
import '../web_asset_store.dart';

/// Plafond voor een gelezen tekstbestand bij een dia (nu: video-ondertitels,
/// #2841). Groter dan dit is geen captionbestand meer maar iets anders — de
/// scan kapt af in plaats van willekeurig veel in het fragment te stoppen.
const int kMaxAssetTextBytes = 512 * 1024;

/// Leest de tekst van een tekstbestand dat bij een dia-veld staat vermeld,
/// synchroon en begrensd.
///
/// Synchroon omdat de privacyscanner een pure functie is: `scanSlide` mag geen
/// `Future` teruggeven zonder het memocontract (`privacy_scan_memo.dart`) te
/// breken. Een captionbestand is klein; de leesbeurt kost minder dan een
/// regel-evaluatie.
///
/// Dekt de drie bronnen die de speler ook dekt: een `mem:`-pad (pakket- of
/// klembordmedia), een pad binnen de projectmap (containment via
/// [resolveContainedRealPath]), en niets anders — een pad buiten het project
/// of een leesfout levert `null`, nooit een exception.
String? readSlideAssetText(String path, {String? projectPath}) {
  final trimmed = path.trim();
  if (trimmed.isEmpty) return null;
  Uint8List? bytes;
  if (WebAssetStore.isMemPath(trimmed)) {
    bytes = WebAssetStore.bytesFor(trimmed);
  } else {
    final resolved = resolveContainedRealPath(trimmed, projectPath);
    if (resolved == null) return null;
    try {
      bytes = File(resolved).readAsBytesSync();
    } on FileSystemException {
      return null;
    }
  }
  if (bytes == null) return null;
  if (bytes.length > kMaxAssetTextBytes) {
    bytes = bytes.sublist(0, kMaxAssetTextBytes);
  }
  return utf8.decode(bytes, allowMalformed: true);
}
