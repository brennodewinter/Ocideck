import 'capture_source.dart';
import 'clip_recorded_audio_stub.dart'
    if (dart.library.io) 'clip_recorded_audio_io.dart'
    if (dart.library.js_interop) 'clip_recorded_audio_web.dart'
    as impl;

/// Trim before ASR/upload. The returned lease owns the original audio lease;
/// on failure the caller still owns (and releases) its original audio.
Future<RecordedAudio> clipRecordedAudio(
  RecordedAudio audio, {
  required Duration start,
  Duration? end,
  String? stagingDir,
  required bool Function() cancelled,
}) => impl.clipRecordedAudio(
  audio,
  start: start,
  end: end,
  stagingDir: stagingDir,
  cancelled: cancelled,
);
