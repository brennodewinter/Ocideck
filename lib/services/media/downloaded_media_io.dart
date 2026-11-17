import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../utils/atomic_file.dart';
import 'downloaded_media.dart';

Future<DownloadedMedia> stageDownloadedMedia(
  Uint8List bytes,
  String extension,
) async {
  final directory = await Directory.systemTemp.createTemp(
    'ocideck-youtube-audio-',
  );
  try {
    final file = File(p.join(directory.path, 'source.$extension'));
    await writeBytesAtomic(file, bytes);
    return DownloadedMedia(file.path, () async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
  } on Object {
    if (await directory.exists()) await directory.delete(recursive: true);
    rethrow;
  }
}
