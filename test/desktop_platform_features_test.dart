import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/call_audio_source.dart';
import 'package:ocideck/services/trash_service.dart';
import 'package:ocideck/services/transcription/bundled_audio_helper_io.dart';
import 'package:ocideck/services/transcription/linux_mic_recorder_io.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'each desktop has a per-track call binding; mobile remains unavailable',
    () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      for (final platform in TargetPlatform.values) {
        debugDefaultTargetPlatformOverride = platform;
        expect(
          callAudioCaptureOfCurrentBinding().wholeCall,
          [
            TargetPlatform.macOS,
            TargetPlatform.windows,
            TargetPlatform.linux,
          ].contains(platform),
          reason: platform.name,
        );
      }
    },
  );

  test(
    'audio helper resolves beside the executable, independent of PATH',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'ocideck-helper-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final executable = p.join(directory.path, 'ocideck');
      expect(
        bundledAudioHelper(executable: executable, windows: false),
        isNull,
      );
      File(
        p.join(directory.path, 'ocideck-audio'),
      ).writeAsStringSync('fixture');
      expect(
        bundledAudioHelper(executable: executable, windows: false),
        p.join(directory.path, 'ocideck-audio'),
      );
      expect(bundledAudioHelper(executable: executable, windows: true), isNull);
      File(
        p.join(directory.path, 'ocideck-audio.exe'),
      ).writeAsStringSync('fixture');
      expect(
        bundledAudioHelper(executable: executable, windows: true),
        p.join(directory.path, 'ocideck-audio.exe'),
      );
    },
  );

  test('bundled recorder passes source IDs as arguments and rejects flags', () {
    expect(
      planLinuxRecording(
        parecordPath: '/app/ocideck-audio',
        deviceId: 'sink.monitor',
      )!.args,
      ['--capture', 'sink.monitor'],
    );
    expect(planLinuxRecording(parecordPath: '/app/ocideck-audio')!.args, [
      '--capture',
    ]);
    expect(
      planLinuxRecording(
        parecordPath: '/app/ocideck-audio',
        deviceId: '--inject',
      ),
      isNull,
    );
  });

  group('Windows recycle channel', () {
    const channel = MethodChannel('ocideck/trash');
    late Directory directory;
    late File deck;
    late File sidecar;
    late File unrelated;
    final calls = <String>[];
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('ocideck-recycle-');
      deck = File(p.join(directory.path, 'demo.md'))
        ..writeAsStringSync('# demo');
      sidecar = File(p.join(directory.path, 'demo.ink.json'))
        ..writeAsStringSync('{}');
      unrelated = File(p.join(directory.path, 'other.md'))
        ..writeAsStringSync('# other');
      calls.clear();
    });
    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
      await directory.delete(recursive: true);
    });
    test('dispatches only the deck and its sidecars', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'recycle');
            calls.add((call.arguments as Map)['path'] as String);
            return true;
          });
      final service = TrashService(windows: true, osHome: () => null);
      expect(service.isSupported, isTrue);
      expect(await service.moveToTrash(deck.path), isTrue);
      expect(calls, [deck.path, sidecar.path]);
      expect(unrelated.existsSync(), isTrue);
    });
    test(
      'failed or missing native recycling never falls back to delete',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add((call.arguments as Map)['path'] as String);
              if (calls.length == 1) {
                throw PlatformException(code: 'cannot_recycle');
              }
              return false;
            });
        expect(
          await TrashService(windows: true).moveToTrash(deck.path),
          isFalse,
        );
        expect(calls, [deck.path, sidecar.path]);
        expect(deck.existsSync(), isTrue);
        expect(sidecar.existsSync(), isTrue);
        expect(unrelated.existsSync(), isTrue);
      },
    );
  });
}
