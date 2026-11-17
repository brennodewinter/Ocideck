@Tags(['benchmark', 'codec-matrix'])
library;

// Explicit installed-decoder/release probe, excluded from the ordinary VM gate.
// Missing configuration fails; it never skips and therefore never turns an
// absent decoder into green platform evidence.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/file_capture_source_io.dart';
import 'package:ocideck/services/transcription/wav_reader_io.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'real installed decoder normalizes the synthetic codec matrix',
    () async {
      final decoder = Platform.environment['OCIDECK_CODEC_MATRIX_DECODER'];
      expect(
        decoder,
        isNotNull,
        reason: 'Set the installed decoder path explicitly',
      );
      expect(File(decoder!).existsSync(), isTrue);
      const fixturePath = 'integration_test/fixtures/audio_formats';
      final manifest =
          jsonDecode(
                File(p.join(fixturePath, 'manifest.json')).readAsStringSync(),
              )
              as Map;
      final rows = <Map<String, Object?>>[];
      final directory = await Directory.systemTemp.createTemp(
        'ocideck-codec-matrix-',
      );
      try {
        for (final entry in manifest['fixtures'] as List) {
          final item = entry as Map;
          final name = item['source'] as String;
          final original = File(p.join(fixturePath, name));
          final originalBytes = await original.readAsBytes();
          expect(
            sha256.convert(originalBytes).toString(),
            item['source_sha256'],
          );
          final input = await original.copy(
            p.join(directory.path, 'brón ü met spaties $name'),
          );
          final staging = await Directory(
            p.join(directory.path, 'stage-$name'),
          ).create();
          final source = IoFileCaptureSource(decoderOverride: decoder);
          final info = await source.describe(input.path);
          final clock = Stopwatch()..start();
          final session = await source.start(
            CaptureRequest(
              kinds: const {CaptureSourceKind.file},
              sourcePath: input.path,
              stagingDir: staging.path,
              consent: const RecordingConsent(
                participantNoticeAcknowledged: true,
              ),
            ),
          );
          final audio = await session.stop();
          clock.stop();
          final result = File(audio.durablePath);
          final access = await result.open();
          final header = await readWavInfo(access, await result.length());
          await access.close();
          if (header == null) {
            fail('$name did not produce a readable WAV header');
          }
          expect(
            (
              header.formatTag,
              header.channels,
              header.sampleRate,
              header.bitsPerSample,
            ),
            (1, 1, 16000, 16),
            reason: name,
          );
          expect(
            header.duration.inMilliseconds,
            closeTo(
              item['expected_duration_ms'] as int,
              item['duration_tolerance_ms'] as int,
            ),
            reason: name,
          );
          expect(header.dataBytes, greaterThan(0), reason: name);
          final bytes = await result.readAsBytes();
          final samples = ByteData.sublistView(
            bytes,
            header.dataOffset,
            header.dataOffset + header.dataBytes,
          );
          var energy = 0;
          for (
            var offset = 0;
            offset + 1 < samples.lengthInBytes;
            offset += 2
          ) {
            energy += samples.getInt16(offset, Endian.little).abs();
          }
          expect(
            energy,
            greaterThan(0),
            reason: '$name must contain actual tone samples',
          );
          expect(await input.readAsBytes(), originalBytes);
          rows.add({
            'source': name,
            'container': info.container.name,
            'duration_ms': header.duration.inMilliseconds,
            'data_bytes': header.dataBytes,
            'elapsed_us': clock.elapsedMicroseconds,
            'offered_in_picker': item['offered_in_picker'],
          });
        }
        final failures = <Map<String, Object?>>[];
        for (final entry in manifest['negative_fixtures'] as List) {
          final item = entry as Map;
          final name = item['source'] as String;
          final original = File(p.join(fixturePath, name));
          final bytes = await original.readAsBytes();
          expect(sha256.convert(bytes).toString(), item['source_sha256']);
          final input = await original.copy(p.join(directory.path, name));
          final staging = await Directory(
            p.join(directory.path, 'negative-$name'),
          ).create();
          TranscriptionError? error;
          try {
            final source = IoFileCaptureSource(decoderOverride: decoder);
            final session = await source.start(
              CaptureRequest(
                kinds: const {CaptureSourceKind.file},
                sourcePath: input.path,
                stagingDir: staging.path,
                consent: const RecordingConsent(
                  participantNoticeAcknowledged: true,
                ),
              ),
            );
            await session.stop();
          } on TranscriptionError catch (caught) {
            error = caught;
          }
          expect(
            error,
            item['expected'] == 'unsupported-codec'
                ? isA<UnsupportedSource>()
                : isA<DecodeFailed>(),
            reason: name,
          );
          if (item['expected'] == 'no-audio') {
            expect(error!.message, contains('geen audiotrack'));
          }
          if (item['expected'] == 'corrupt') {
            expect(error!.message, contains('beschadigd'));
          }
          expect(await input.readAsBytes(), bytes);
          expect(await staging.list().toList(), isEmpty, reason: name);
          failures.add({
            'source': name,
            'expected': item['expected'],
            'error_type': error.runtimeType.toString(),
            'message': error!.message,
          });
        }
        final output = Platform.environment['OCIDECK_CODEC_MATRIX_OUTPUT'];
        expect(
          output,
          isNotNull,
          reason: 'Set evidence output path; no unrecorded green result',
        );
        await File(output!).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'platform': Platform.operatingSystem,
            'os': Platform.operatingSystemVersion,
            'decoder': decoder,
            'decoder_sha256': sha256
                .convert(await File(decoder).readAsBytes())
                .toString(),
            'scope': 'Actual file source and decoder; no ASR or UI claim',
            'results': rows,
            'negative_results': failures,
          }),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
