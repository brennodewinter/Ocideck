import 'dart:typed_data';

import '../web_asset_store.dart';
import 'transcription_errors.dart';

Future<Uint8List> readAsrAudio(String path) async {
  if (!path.startsWith(WebAssetStore.scheme)) {
    // Op web bestaat geen bestandspad — alleen bytes die al in de tab
    // liggen (mem:) zijn een bruikbare bron voor de upload.
    throw const UnsupportedSource('geen bestandspad op web');
  }
  final bytes = WebAssetStore.bytesFor(path);
  if (bytes == null) {
    throw const SourceUnavailable('mem-audio niet meer aanwezig');
  }
  return bytes;
}
