import 'dart:io';

import 'package:path/path.dart' as p;

import 'recording_staging.dart';
import 'staged_recordings_stub.dart' hide listStagedMicRecordings;
import 'wav_reader_io.dart';
import 'wav_sink_io.dart';

export 'staged_recordings_stub.dart' show StagedMicRecording;

/// Afgeronde of herstelde microfoonopnames in de staging. Een crash
/// laat de header soms achterlopen; [repairWavHeader] maakt ze weer
/// afspeelbaar vóór we de duur tonen.
Future<List<StagedMicRecording>> listStagedMicRecordings(
  RecordingStaging staging,
) async {
  final found = <StagedMicRecording>[];
  for (final dir in await staging.listSessionDirs()) {
    final path = p.join(dir, recordingWavName);
    final file = File(path);
    if (!await file.exists()) continue;
    await repairWavHeader(path);
    final length = await file.length();
    if (length <= 44) continue;
    final ra = await file.open();
    try {
      final info = await readWavInfo(ra, length);
      if (info == null) continue;
      found.add(
        StagedMicRecording(
          sessionDir: dir,
          wavPath: path,
          duration: info.duration,
          recordedAt: await file.lastModified(),
        ),
      );
    } finally {
      await ra.close();
    }
  }
  found.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  return found;
}
