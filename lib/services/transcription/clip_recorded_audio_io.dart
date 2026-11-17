import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'capture_source.dart';
import 'pcm_clip.dart';
import 'transcription_errors.dart';
import 'wav_reader_io.dart';

Future<RecordedAudio> clipRecordedAudio(
  RecordedAudio audio, {
  required Duration start,
  Duration? end,
  String? stagingDir,
  required bool Function() cancelled,
}) async {
  if (stagingDir == null) throw const IoFailed('geen staging voor fragment');
  final source = await File(audio.durablePath).open();
  final target = File(
    p.join(stagingDir, 'source-clip-${const Uuid().v4()}.wav'),
  );
  try {
    if (cancelled()) throw const Cancelled('fragment geannuleerd');
    final info = await readWavInfo(source, await source.length());
    if (info == null) throw const DecodeFailed('onleesbare fragmentbron');
    final plan = planPcmClip(info, start, end);
    final output = await target.open(mode: FileMode.write);
    try {
      await output.writeFrom(plan.header);
      await source.setPosition(plan.byteOffset);
      var remaining = plan.dataBytes;
      while (remaining > 0) {
        if (cancelled()) throw const Cancelled('fragment geannuleerd');
        final chunk = await source.read(remaining < 65536 ? remaining : 65536);
        if (chunk.isEmpty) throw const DecodeFailed('afgekapte fragmentbron');
        await output.writeFrom(chunk);
        remaining -= chunk.length;
      }
    } finally {
      await output.close();
    }
    if (cancelled()) throw const Cancelled('fragment geannuleerd');
    return RecordedAudio(
      durablePath: target.path,
      duration: plan.duration,
      kinds: audio.kinds,
      onRelease: audio.releaseAssets,
    );
  } on Object {
    try {
      if (await target.exists()) await target.delete();
    } on FileSystemException {
      // The owner also removes the complete private session directory.
    }
    rethrow;
  } finally {
    await source.close();
  }
}
