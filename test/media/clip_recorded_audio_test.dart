import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/clip_recorded_audio_io.dart'
    as native;
import 'package:ocideck/services/transcription/clip_recorded_audio_web.dart'
    as browser;
import 'package:ocideck/services/transcription/clip_recorded_audio_stub.dart'
    as unsupported;
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/web_asset_store.dart';

Uint8List _wav() => encodePcmWav(
  Float32List.fromList(List.generate(160000, (i) => (i % 100) / 100 - .5)),
);

void main() {
  test(
    'unsupported clipping refuses before I/O and retains caller ownership',
    () async {
      var released = 0;
      final audio = RecordedAudio(
        durablePath: 'unavailable:fixture',
        duration: const Duration(seconds: 10),
        kinds: const {CaptureSourceKind.file},
        onRelease: () => released++,
      );
      await expectLater(
        unsupported.clipRecordedAudio(
          audio,
          start: const Duration(seconds: 2),
          end: const Duration(seconds: 3),
          cancelled: () => false,
        ),
        throwsA(isA<UnsupportedSource>()),
      );
      expect(released, 0);
      audio.releaseAssets();
      expect(released, 1);
    },
  );

  test(
    'native clipping streams exact source frames and leaves padded source intact',
    () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-clip-test-');
      addTearDown(() => dir.delete(recursive: true));
      final original = _wav();
      final padded = Uint8List(original.length + 40)
        ..setRange(0, 36, original)
        ..setRange(36, 40, 'JUNK'.codeUnits)
        ..setRange(76, original.length + 40, original, 36);
      ByteData.sublistView(padded).setUint32(40, 32, Endian.little);
      ByteData.sublistView(
        padded,
      ).setUint32(4, padded.length - 8, Endian.little);
      final file = File('${dir.path}/source.wav');
      final out = await Directory('${dir.path}/private').create();
      final handle = await file.open(mode: FileMode.write);
      await handle.writeFrom(padded);
      await handle.close();
      var released = 0;
      final audio = RecordedAudio(
        durablePath: file.path,
        duration: const Duration(seconds: 10),
        kinds: const {CaptureSourceKind.file},
        onRelease: () => released++,
      );
      final result = await native.clipRecordedAudio(
        audio,
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 3),
        stagingDir: out.path,
        cancelled: () => false,
      );
      final bytes = await File(result.durablePath).readAsBytes();
      expect(
        parseWavHeader(bytes, bytes.length)!.duration,
        const Duration(seconds: 1),
      );
      expect(bytes.sublist(44), original.sublist(44 + 64000, 44 + 96000));
      expect(await file.readAsBytes(), padded);
      expect(released, 0);
      result.releaseAssets();
      expect(released, 1);
    },
  );

  test(
    'native cancellation removes partial output and leaves ownership with caller',
    () async {
      final dir = await Directory.systemTemp.createTemp('ocideck-clip-cancel-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/source.wav');
      final handle = await file.open(mode: FileMode.write);
      await handle.writeFrom(_wav());
      await handle.close();
      final out = await Directory('${dir.path}/private').create();
      var calls = 0;
      var released = false;
      final audio = RecordedAudio(
        durablePath: file.path,
        duration: const Duration(seconds: 10),
        kinds: const {CaptureSourceKind.file},
        onRelease: () => released = true,
      );
      await expectLater(
        native.clipRecordedAudio(
          audio,
          start: Duration.zero,
          stagingDir: out.path,
          cancelled: () => ++calls > 2,
        ),
        throwsA(isA<Cancelled>()),
      );
      expect(await out.list().toList(), isEmpty);
      expect(released, isFalse);
      expect(await file.length(), _wav().length);
    },
  );

  test(
    'browser clipping shares the budget and releases original and output leases',
    () async {
      WebAssetStore.clear();
      addTearDown(WebAssetStore.clear);
      addTearDown(WebAssetStore.registerRoots(() => {}));
      final original = _wav();
      final path = WebAssetStore.put(original, name: 'source.wav');
      final lease = WebAssetStore.lease([path]);
      final audio = RecordedAudio(
        durablePath: path,
        duration: const Duration(seconds: 10),
        kinds: const {CaptureSourceKind.file},
        onRelease: lease.release,
      );
      final result = await browser.clipRecordedAudio(
        audio,
        start: const Duration(seconds: 2),
        end: const Duration(seconds: 3),
        cancelled: () => false,
      );
      final bytes = WebAssetStore.bytesFor(result.durablePath)!;
      expect(bytes.sublist(44), original.sublist(44 + 64000, 44 + 96000));
      expect(WebAssetStore.totalBytes, original.length + bytes.length);
      result.releaseAssets();
      expect(WebAssetStore.totalBytes, 0);
    },
  );
}
