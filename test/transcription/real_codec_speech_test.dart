@Tags(['codec-matrix'])
library;

import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/file_capture_source_io.dart';
import 'package:ocideck/services/transcription/local_whisper_engine_io.dart';
import 'package:ocideck/services/transcription/model_store_io.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';
import 'package:path/path.dart' as p;

void main() {
  test(
    'real decoded speech passes through the local production engine',
    () async {
      final environment = Platform.environment;
      final decoder = environment['OCIDECK_CODEC_MATRIX_DECODER'];
      final cli = environment['OCIDECK_CODEC_SPEECH_WHISPER'];
      final modelPath = environment['OCIDECK_CODEC_SPEECH_MODEL'];
      final output = environment['OCIDECK_CODEC_SPEECH_OUTPUT'];
      expect(
        [decoder, cli, modelPath, output],
        everyElement(isNotNull),
        reason:
            'Provide explicit installed helper, CLI, model and evidence paths',
      );
      final model = whisperModelCatalog.singleWhere(
        (entry) => entry.id == 'base',
      );
      final directory = await Directory.systemTemp.createTemp(
        'ocideck-codec-speech-',
      );
      try {
        final store = await Directory(
          p.join(directory.path, 'models'),
        ).create();
        await File(modelPath!).copy(p.join(store.path, model.fileName));
        final work = await Directory(p.join(directory.path, 'engine')).create();
        final engine = IoLocalWhisperEngine(
          executable: cli,
          model: model,
          store: IoModelStore(root: store, candidateRoots: const []),
          workDir: work,
        );
        const fixtureRoot = 'integration_test/fixtures/codec_speech';
        final manifest =
            jsonDecode(
                  await File(
                    p.join(fixtureRoot, 'manifest.json'),
                  ).readAsString(),
                )
                as Map;
        final rows = <Map<String, Object?>>[];
        for (final item in manifest['fixtures'] as List) {
          final entry = item as Map;
          final name = entry['source'] as String;
          final original = File(p.join(fixtureRoot, name));
          final originalHash = sha256
              .convert(await original.readAsBytes())
              .toString();
          expect(originalHash, entry['sha256']);
          final stage = await Directory(p.join(directory.path, name)).create();
          final session = await IoFileCaptureSource(decoderOverride: decoder)
              .start(
                CaptureRequest(
                  sourcePath: original.absolute.path,
                  stagingDir: stage.path,
                  kinds: const {CaptureSourceKind.file},
                  consent: const RecordingConsent(
                    participantNoticeAcknowledged: true,
                  ),
                ),
              );
          final audio = await session.stop();
          final result = await engine.transcribe(
            AudioRef(audio.durablePath),
            const TranscriptionOptions(language: 'en'),
          );
          expect(result.text.toLowerCase(), contains('country'), reason: name);
          expect(result.segments, isNotEmpty);
          expect(
            result.segments.every((segment) => segment.start != null),
            isTrue,
          );
          expect(
            sha256.convert(await original.readAsBytes()).toString(),
            originalHash,
          );
          rows.add({
            'source': name,
            'text': result.text,
            'segments': result.segments
                .map(
                  (s) => {'start_ms': s.start!.inMilliseconds, 'text': s.text},
                )
                .toList(),
          });
        }
        await File(output!).writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'scope':
                'Real file source to production local ASR; limited English sample; no UI/release certification',
            'platform': Platform.operatingSystemVersion,
            'model': model.id,
            'model_sha256': model.sha256,
            'decoder_sha256': sha256
                .convert(await File(decoder!).readAsBytes())
                .toString(),
            'whisper_sha256': sha256
                .convert(await File(cli!).readAsBytes())
                .toString(),
            'results': rows,
          }),
        );
      } finally {
        await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
