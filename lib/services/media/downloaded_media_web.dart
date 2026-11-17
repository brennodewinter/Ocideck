import 'dart:typed_data';

import '../web_asset_store.dart';
import 'downloaded_media.dart';

Future<DownloadedMedia> stageDownloadedMedia(
  Uint8List bytes,
  String extension,
) async {
  final path = WebAssetStore.put(bytes, name: 'youtube-source.$extension');
  final lease = WebAssetStore.lease([path]);
  return DownloadedMedia(path, () async => lease.release());
}
