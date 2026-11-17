import 'capture_source.dart';
import 'transcription_errors.dart';

Future<RecordedAudio> clipRecordedAudio(
  RecordedAudio audio, {
  required Duration start,
  Duration? end,
  String? stagingDir,
  required bool Function() cancelled,
}) async => throw const UnsupportedSource('fragmenten niet beschikbaar');
