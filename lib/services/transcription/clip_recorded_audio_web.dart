import 'dart:typed_data';

import '../web_asset_store.dart';
import 'capture_source.dart';
import 'media_sniff.dart';
import 'pcm_clip.dart';
import 'transcription_errors.dart';

Future<RecordedAudio> clipRecordedAudio(
  RecordedAudio audio, {
  required Duration start,
  Duration? end,
  String? stagingDir,
  required bool Function() cancelled,
}) async {
  if (cancelled()) throw const Cancelled('fragment geannuleerd');
  final bytes = WebAssetStore.bytesFor(audio.durablePath);
  if (bytes == null) {
    throw const SourceUnavailable('fragmentbron niet meer beschikbaar');
  }
  final info = parseWavHeader(bytes, bytes.length);
  if (info == null) throw const DecodeFailed('onleesbare fragmentbron');
  final plan = planPcmClip(info, start, end);
  if (plan.dataBytes + 44 >
      WebAssetStore.maxTotalBytes - WebAssetStore.totalBytes) {
    throw const CapacityExceeded('fragment past niet in het geheugenbudget');
  }
  final output = Uint8List(44 + plan.dataBytes)..setRange(0, 44, plan.header);
  output.setRange(44, output.length, bytes, plan.byteOffset);
  final String key;
  try {
    key = WebAssetStore.put(output, name: 'source-clip.wav');
  } on WebAssetBudgetExceeded {
    throw const CapacityExceeded('fragment past niet in het geheugenbudget');
  }
  final lease = WebAssetStore.lease([key]);
  return RecordedAudio(
    durablePath: key,
    duration: plan.duration,
    kinds: audio.kinds,
    onRelease: () {
      lease.release();
      audio.releaseAssets();
    },
  );
}
