// Explicit live-provider probe. No provider text/audio is written to the report.
// Requires the reference source server on 8866 and actual ASR server on 8093.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/services/media/downloaded_media.dart';
import 'package:ocideck/services/media/media_transcript.dart';
import 'package:ocideck/services/media/timed_captions.dart';
import 'package:ocideck/services/media/youtube_reference.dart';
import 'package:ocideck/services/media/youtube_source_client.dart';
import 'package:ocideck/services/transcription/asr_audio_source.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';

void main() {
  test(
    'real provider captions, source-clock audio, ASR and document roundtrip',
    () async {
      final output = Platform.environment['OCIDECK_YOUTUBE_RESULT'];
      expect(
        output,
        isNotNull,
        reason: 'provide an explicit external proof path',
      );
      final report = <String, Object?>{
        'scope':
            'native production clients and document model, not a release UI/platform qualification',
        'source_revision': Platform.environment['OCIDECK_SOURCE_REVISION'],
        'captions': <Object?>[],
        'audio': <Object?>[],
      };
      const destination = AsrServerProfile(
        enabled: true,
        mode: AsrServerMode.loopback,
        baseUrl: 'http://127.0.0.1:8866',
      );
      final source = YoutubeSourceClient(
        destination: destination,
        mayUseNetwork: () => true,
      );
      const asrProfile = AsrServerProfile(
        enabled: true,
        mode: AsrServerMode.loopback,
        baseUrl: 'http://127.0.0.1:8093',
        batchProtocol: AsrBatchProtocol.ocideckV1,
      );
      final engine = AsrServerEngine(
        profile: asrProfile,
        transport: createAsrTransport(),
        audioReader: readAsrAudio,
      );
      for (final id in ['M7lc1UVf-VE', 'jNQXAC9IVRw', 'aqz-KE-bpKQ']) {
        final reference = YoutubeReference.parse('https://youtu.be/$id')!;
        final consent = YoutubeSourceConsent(
          destination: destination.baseUrl,
          videoId: id,
        );
        final meta = await source.metadata(reference, consent);
        if (id == 'aqz-KE-bpKQ') expect(meta.tracks, isEmpty);
        final tracks = <Object?>[];
        for (final automatic in [false, true]) {
          final matching = meta.tracks.where(
            (t) => t.language == 'en' && t.automatic == automatic,
          );
          if (matching.isEmpty) continue;
          final watch = Stopwatch()..start();
          final captions = await source.captions(
            reference,
            matching.first,
            consent,
          );
          final plain = parseTimedCaptions(captions.text);
          final parsed = parseTimedCaptions(captions.text, rolling: automatic);
          expect(parsed, isNotEmpty);
          expect(
            parsed.every((s) => s.start != null && s.end! >= s.start!),
            isTrue,
          );
          if (automatic && id == 'M7lc1UVf-VE') {
            expect(
              parsed.fold<int>(0, (n, s) => n + s.text.length),
              lessThan(plain.fold<int>(0, (n, s) => n + s.text.length)),
            );
          }
          final origin = YoutubeTranscriptOrigin(
            reference: reference,
            title: meta.title,
          );
          String createDocument() => mediaTranscriptMarkdown(
            origin: origin,
            segments: parsed,
            methodLabel: automatic ? 'Automatic captions' : 'Manual captions',
            processedAtLabel: 'probe',
            language: 'en',
          );
          await roundtrip(markdown);
          tracks.add({
            'kind': automatic ? 'automatic' : 'manual',
            'caption_sha256': sha256
                .convert(utf8.encode(captions.text))
                .toString(),
            'cues': parsed.length,
            'input_cues': plain.length,
            'characters_before': plain.fold<int>(
              0,
              (n, s) => n + s.text.length,
            ),
            'characters_after': parsed.fold<int>(
              0,
              (n, s) => n + s.text.length,
            ),
            'elapsed_ms': watch.elapsedMilliseconds,
            'edit_save_reopen': true,
          });
        }
        (report['captions'] as List).add({
          'video_id': id,
          'available_tracks': meta.tracks.length,
          'tracks': tracks,
        });
        final start = id == 'M7lc1UVf-VE' ? 10000 : 0;
        final end = id == 'M7lc1UVf-VE'
            ? 35000
            : id == 'aqz-KE-bpKQ'
            ? 25000
            : 0;
        final watch = Stopwatch()..start();
        final audio = await source.audio(
          reference,
          consent,
          startMs: start,
          endMs: end,
        );
        final staged = await stageDownloadedMedia(audio.bytes, audio.extension);
        final path = staged.path;
        try {
          final result = await engine.transcribe(
            AudioRef(path),
            TranscriptionOptions(
              language: 'en',
              serverConsent: ServerConsent(
                host: asrProfile.host,
                audioPath: path,
              ),
            ),
          );
          if (id != 'aqz-KE-bpKQ') expect(result.segments, isNotEmpty);
          String createDocument() => mediaTranscriptMarkdown(
            origin: YoutubeTranscriptOrigin(
              reference: reference,
              title: meta.title,
              start: Duration(milliseconds: start),
              end: end == 0 ? null : Duration(milliseconds: end),
            ),
            segments: result.segments,
            methodLabel: 'ASR v1 · Whisper base',
            processedAtLabel: 'probe',
            audioOffset: audio.sourceOffset,
            language: 'en',
          );
          if (result.segments.isEmpty) {
            expect(createDocument, throwsA(isA<SourceUnavailable>()));
          } else {
            final markdown = createDocument();
            await roundtrip(markdown);
            expect(markdown, contains('https://www.youtube.com/watch?v=$id'));
          }
          (report['audio'] as List).add({
            'video_id': id,
            'start_ms': start,
            'end_ms': end,
            'source_offset_ms': audio.sourceOffset.inMilliseconds,
            'audio_sha256': sha256.convert(audio.bytes).toString(),
            'audio_bytes': audio.bytes.length,
            'asr_segments': result.segments.length,
            'no_speech_document_refused': result.segments.isEmpty,
            'text_sha256': sha256
                .convert(
                  utf8.encode(result.segments.map((s) => s.text).join('\n')),
                )
                .toString(),
            'segment_times': [
              for (final s in result.segments)
                {
                  'start_ms': s.start!.inMilliseconds + start,
                  'end_ms': s.end!.inMilliseconds + start,
                },
            ],
            'elapsed_ms': watch.elapsedMilliseconds,
            'edit_save_reopen': result.segments.isNotEmpty,
          });
        } finally {
          await staged.release();
        }
        expect(File(path).existsSync(), isFalse);
      }
      source.cancel();
      report['temporary_audio_removed'] = true;
      await File(output!).writeAsString(
        '${const JsonEncoder.withIndent('  ').convert(report)}\n',
      );
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
}

Future<void> roundtrip(String markdown) async {
  final dir = await Directory.systemTemp.createTemp('ocideck-source-document-');
  try {
    final edited = '$markdown\nReviewed locally.\n';
    final file = File('${dir.path}/transcript.md');
    await file.writeAsBytes(MarkdownDocument.parse(edited).toBytes());
    expect(
      MarkdownDocument.parse(await file.readAsString()).toMarkdown(),
      edited,
    );
  } finally {
    await dir.delete(recursive: true);
  }
}
