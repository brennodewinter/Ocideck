// Web heeft geen opnamebestand op schijf. De klasse bestaat zodat de
// bronnen één type houden; een desktop-start komt hier niet aan.
import 'dart:typed_data';

import 'wav_sink.dart';

class IncrementalWav {
  IncrementalWav(
    this.path, {
    this.channels = recordingChannels,
    this.maxBytes = maxRecordingWavBytes,
  });

  final String path;
  final int channels;
  final int maxBytes;

  int get dataBytes => 0;

  Duration get duration => Duration.zero;

  Future<void> open() async {
    throw UnsupportedError('een opnamebestand hoort op de desktop');
  }

  Future<void> add(Uint8List pcm) async {
    if (pcm.isEmpty) return;
    throw UnsupportedError('een opnamebestand hoort op de desktop');
  }

  Future<void> close() async {}
}

Future<bool> repairWavHeader(String path) async {
  if (path.isEmpty) return false;
  return false;
}
