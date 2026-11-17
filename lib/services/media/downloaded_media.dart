import 'dart:typed_data';

import 'downloaded_media_stub.dart'
    if (dart.library.io) 'downloaded_media_io.dart'
    if (dart.library.js_interop) 'downloaded_media_web.dart'
    as impl;
import '../transcription/transcription_errors.dart';

/// Private, explicitly owned source bytes, removed after the ASR dialog.
class DownloadedMedia {
  DownloadedMedia(this.path, this._release);
  final String path;
  final Future<void> Function() _release;
  bool _released = false;
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _release();
  }
}

Future<DownloadedMedia> stageDownloadedMedia(
  Uint8List bytes,
  String extension,
) {
  if (bytes.isEmpty ||
      bytes.length > 8 * 1024 * 1024 ||
      !const ['m4a', 'webm', 'wav'].contains(extension)) {
    throw const CapacityExceeded('ongeldige of te grote bronbytes');
  }
  return impl.stageDownloadedMedia(bytes, extension);
}
