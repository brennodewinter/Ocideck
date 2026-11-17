import 'dart:typed_data';

import 'downloaded_media_stub.dart'
    if (dart.library.io) 'downloaded_media_io.dart'
    if (dart.library.js_interop) 'downloaded_media_web.dart'
    as impl;
import '../transcription/transcription_errors.dart';
import '../transcription/media_sniff.dart';

/// Private, explicitly owned source bytes, removed after the ASR dialog.
class DownloadedMedia {
  DownloadedMedia(this.path, this._release);
  final String path;
  final Future<void> Function() _release;
  bool _released = false;
  Future<void>? _releasing;
  Future<void> release() {
    if (_released) return Future.value();
    return _releasing ??= _release()
        .then((_) {
          _released = true;
        })
        .whenComplete(() => _releasing = null);
  }
}

Future<DownloadedMedia> stageDownloadedMedia(
  Uint8List bytes,
  String extension,
) {
  if (bytes.isEmpty ||
      bytes.length > 8 * 1024 * 1024 ||
      !mediaFileExtensions.contains(extension)) {
    throw const CapacityExceeded('ongeldige of te grote bronbytes');
  }
  return impl.stageDownloadedMedia(bytes, extension);
}
