import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'media_sniff.dart';
import 'recording_staging.dart';
import 'staged_recordings_stub.dart' hide listStagedMicRecordings;
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
    final head = await _head(file);
    final info = parseWavHeader(head, length);
    if (info == null) continue;
    found.add(
      StagedMicRecording(
        sessionDir: dir,
        wavPath: path,
        duration: info.duration,
        recordedAt: await file.lastModified(),
      ),
    );
  }
  found.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
  return found;
}

Future<Uint8List> _head(File file) async {
  final bytes = await file
      .openRead(0, sniffHeadBytes)
      .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  return Uint8List.fromList(bytes);
}
