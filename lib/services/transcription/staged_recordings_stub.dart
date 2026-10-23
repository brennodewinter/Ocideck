import 'recording_staging.dart';

class StagedMicRecording {
  const StagedMicRecording({
    required this.sessionDir,
    required this.wavPath,
    required this.duration,
    required this.recordedAt,
  });

  final String sessionDir;
  final String wavPath;
  final Duration duration;
  final DateTime recordedAt;
}

Future<List<StagedMicRecording>> listStagedMicRecordings(
  RecordingStaging staging,
) async => const [];
