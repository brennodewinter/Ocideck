import 'dart:io';
import 'dart:typed_data';

import '../../utils/log.dart';
import '../web_asset_store.dart';
import 'transcription_errors.dart';

Future<Uint8List> readAsrAudio(String path) async {
  if (path.startsWith(WebAssetStore.scheme)) {
    final bytes = WebAssetStore.bytesFor(path);
    if (bytes == null) {
      throw const SourceUnavailable('mem-audio niet meer aanwezig');
    }
    return bytes;
  }
  try {
    return await File(path).readAsBytes();
  } on PathNotFoundException {
    throw const SourceUnavailable('audiobestand bestaat niet meer');
  } catch (e, s) {
    logError('asr_audio_source_io: lezen mislukt', e, s);
    throw const IoFailed('audiobestand niet te lezen');
  }
}
