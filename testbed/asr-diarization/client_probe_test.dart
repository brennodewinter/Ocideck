// Expliciete praktijkproef met een werkelijk gestart ASR v1-endpoint.
// Geen overgeslagen tests die groen lijken: fixture en rapportpad zijn vereist.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/services/transcription/asr_audio_source.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/transcript_document.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';

void main() {
  test(
    'echt ASR v1-transport bewaart timings en bewerkbare clusterlabels',
    () async {
      final path = Platform.environment['OCIDECK_DIARIZATION_FIXTURE'];
      final output = Platform.environment['OCIDECK_DIARIZATION_RESULT'];
      expect(path, isNotNull, reason: 'geef een gelabelde mono PCM16 WAV op');
      expect(output, isNotNull, reason: 'bewaar het bewijs buiten de bronboom');
      final input = await File(path!).readAsBytes();
      const profile = AsrServerProfile(
        enabled: true,
        mode: AsrServerMode.loopback,
        baseUrl: 'http://127.0.0.1:8093',
        batchProtocol: AsrBatchProtocol.ocideckV1,
      );
      final engine = AsrServerEngine(
        profile: profile,
        transport: createAsrTransport(),
        audioReader: readAsrAudio,
      );
      final caps = await engine.capabilities();
      expect(caps.diarization, isTrue);
      expect(caps.languages, contains('nl'));
      expect(caps.automaticLanguage, isFalse);
      final timer = Stopwatch()..start();
      final result = await engine.transcribe(
        AudioRef(path),
        TranscriptionOptions(
          language: 'nl',
          diarize: true,
          serverConsent: ServerConsent(host: profile.host, audioPath: path),
        ),
      );
      timer.stop();
      expect(result.segments, isNotEmpty);
      expect(result.segments.any((s) => s.speakerIds.isNotEmpty), isTrue);
      for (final segment in result.segments) {
        expect(segment.end, isNotNull);
        expect(segment.end! >= segment.start!, isTrue);
        expect(
          segment.speakerUncertain,
          isTrue,
          reason: 'de experimentele Vosk-backend belooft geen zekere indeling',
        );
      }
      final markdown = buildTranscriptMarkdown(
        const TranscriptProvenance(
          title: 'Publieke NL-sprekerproef',
          sourceLabel: 'MLS Dutch test',
          recordedAt: '2026-11-17',
          sourceKindLabel: 'bestand',
          engineLabel: 'Experimentele Vosk ASR v1',
        ),
        formatTranscriptBody(result.segments),
      );
      final edited = markdown.replaceAll('Spreker 1', 'Alice');
      final temporary = await Directory.systemTemp.createTemp(
        'ocideck-asr-v1-',
      );
      try {
        final document = MarkdownDocument.parse(edited);
        final saved = File('${temporary.path}/transcript.md');
        await saved.writeAsBytes(document.toBytes());
        final reopened = MarkdownDocument.parse(await saved.readAsString());
        expect(reopened.toMarkdown(), edited);
        expect(reopened.source, contains('Alice (?)'));
        expect(reopened.source, contains('ocideck:segments:v1'));
      } finally {
        await temporary.delete(recursive: true);
      }
      await File(output!).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert({
          'scope': 'real HTTP client and document model; not full release UI acceptance',
          'fixture_sha256': sha256.convert(input).toString(),
          'elapsed_ms': timer.elapsedMilliseconds,
          'segments': [
            for (final s in result.segments) {'start': s.start!.inMicroseconds / 1000000, 'end': s.end!.inMicroseconds / 1000000, 'speaker_ids': s.speakerIds, 'speaker_uncertain': s.speakerUncertain},
          ],
          'document_rename_save_reopen': true,
          'quality_acceptance': false,
        })}\n',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
