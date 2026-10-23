// Afgeronde microfoonopnames in de staging (#2516). Een lege of
// onleesbare file telt niet mee; de stub op web vindt niets.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/recording_staging_io.dart';
import 'package:ocideck/services/transcription/recording_staging_stub.dart';
import 'package:ocideck/services/transcription/staged_recordings_io.dart';
import 'package:ocideck/services/transcription/staged_recordings_stub.dart'
    as stub;
import 'package:ocideck/services/transcription/wav_sink_io.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late IoRecordingStaging staging;

  setUp(() {
    root = Directory.systemTemp.createTempSync('ocideck_staged_mic');
    staging = IoRecordingStaging(baseDir: root);
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('een afgeronde wav komt terug, rommel niet', () async {
    final older = (await staging.createSessionDir())!;
    final newer = (await staging.createSessionDir())!;
    final empty = (await staging.createSessionDir())!;
    await staging.createSessionDir();

    Future<void> write(String dir, int samples) async {
      final wav = IncrementalWav(p.join(dir, recordingWavName));
      await wav.open();
      await wav.add(Uint8List(samples * 2));
      await wav.close();
    }

    await write(older, 16000);
    await write(newer, 8000);
    await File(
      p.join(older, recordingWavName),
    ).setLastModified(DateTime.utc(2026, 1, 1));
    await File(
      p.join(newer, recordingWavName),
    ).setLastModified(DateTime.utc(2026, 6, 1));
    await File(
      p.join(empty, recordingWavName),
    ).writeAsBytes(List.filled(44, 0));
    await File(p.join(empty, 'geen-wav.bin')).writeAsBytes(List.filled(80, 1));

    final listed = await listStagedMicRecordings(staging);
    expect(listed, hasLength(2));
    expect(listed.first.sessionDir, newer);
    expect(listed.first.duration, const Duration(milliseconds: 500));
    expect(listed.last.duration, const Duration(seconds: 1));
    expect(listed.first.wavPath, endsWith(recordingWavName));
  });

  test('de stub vindt niets, ook als er een staging is', () async {
    expect(
      await stub.listStagedMicRecordings(const NoopRecordingStaging()),
      isEmpty,
    );
  });
}
