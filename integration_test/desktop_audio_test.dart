import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ocideck/services/transcription/bundled_audio_helper_io.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:path/path.dart' as p;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('installed helper decodes local media without FFmpeg on PATH', (
    tester,
  ) async {
    final helper = bundledAudioHelper();
    expect(helper, isNotNull, reason: 'native audio helper was not installed');
    final temp = await Directory.systemTemp.createTemp('ocideck-audio-proof-');
    addTearDown(() => temp.delete(recursive: true));
    for (final extension in ['mp3', 'm4a', 'mp4']) {
      // flutter test integration runs from the repository; copy input to verify
      // UTF-8 paths and the helper's argument boundary as well as the codec.
      final input = await File(
        'integration_test/fixtures/audio/tone.$extension',
      ).copy(p.join(temp.path, 'geluid ü met spaties.$extension'));
      final output = p.join(temp.path, 'decoded-$extension.wav');
      final result = await Process.run(
        helper!,
        ['--decode', input.path, output],
        environment: {
          if (Platform.isWindows)
            'SystemRoot': Platform.environment['SystemRoot']!,
          if (Platform.isLinux)
            'LD_LIBRARY_PATH': p.join(p.dirname(helper), 'lib'),
        },
        includeParentEnvironment: false,
      ).timeout(const Duration(seconds: 30));
      expect(result.exitCode, 0, reason: 'decoder failed for $extension');
      final file = File(output);
      final wav = parseWavHeader(
        Uint8List.fromList(await file.readAsBytes()),
        await file.length(),
      );
      expect(wav, isNotNull);
      expect(wav!.duration.inMilliseconds, inInclusiveRange(450, 800));
    }
    final output = p.join(temp.path, 'no-audio.wav');
    final result = await Process.run(helper!, [
      '--decode',
      p.absolute('integration_test/fixtures/audio/silent-video.mp4'),
      output,
    ]).timeout(const Duration(seconds: 30));
    expect(result.exitCode, isNot(0));
    expect(File(output).existsSync(), isFalse);
  });
}
