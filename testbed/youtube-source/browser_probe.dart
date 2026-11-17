// Explicit compiled production-client probe, not the complete release UI.
import 'dart:convert';
import 'dart:js_interop';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
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
import 'package:ocideck/services/web_asset_store.dart';

@JS('ocideckYoutubeProbeResult')
external set _report(JSString value);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Explicit source client probe')),
    ),
  );
  final unregisterRoots = WebAssetStore.registerRoots(() => {});
  var stage = 'metadata';
  try {
    const destination = AsrServerProfile(
      enabled: true,
      mode: AsrServerMode.loopback,
      baseUrl: 'https://127.0.0.1:8867',
    );
    final client = YoutubeSourceClient(
      destination: destination,
      mayUseNetwork: () => true,
    );
    final reference = YoutubeReference.parse('https://youtu.be/M7lc1UVf-VE')!;
    final consent = YoutubeSourceConsent(
      destination: destination.baseUrl,
      videoId: 'M7lc1UVf-VE',
    );
    final meta = await client.metadata(reference, consent);
    final tracks = <Object?>[];
    for (final automatic in [false, true]) {
      final track = meta.tracks.firstWhere(
        (t) => t.language == 'en' && t.automatic == automatic,
      );
      stage = automatic ? 'automatic captions' : 'manual captions';
      final captions = await client.captions(reference, track, consent);
      final segments = parseTimedCaptions(captions.text, rolling: automatic);
      if (segments.isEmpty) throw StateError('No captions');
      tracks.add({
        'automatic': automatic,
        'cues': segments.length,
        'caption_sha256': sha256.convert(utf8.encode(captions.text)).toString(),
      });
    }
    stage = 'audio';
    final audio = await client.audio(
      reference,
      consent,
      startMs: 10000,
      endMs: 35000,
    );
    if (audio.sourceOffset.inMilliseconds != 10000 ||
        audio.bytes.length != 800044) {
      throw StateError('Wrong source interval');
    }
    final staged = await stageDownloadedMedia(audio.bytes, audio.extension);
    final report = <String, Object?>{
      'success': false,
      'scope':
          'compiled production source/ASR web clients and document model, not full release UI',
      'captions': tracks,
      'audio_sha256': sha256.convert(audio.bytes).toString(),
      'audio_bytes': audio.bytes.length,
      'source_offset_ms': audio.sourceOffset.inMilliseconds,
    };
    try {
      const asr = AsrServerProfile(
        enabled: true,
        mode: AsrServerMode.loopback,
        baseUrl: 'https://127.0.0.1:8893',
        batchProtocol: AsrBatchProtocol.ocideckV1,
      );
      final engine = AsrServerEngine(
        profile: asr,
        transport: createAsrTransport(),
        audioReader: readAsrAudio,
      );
      stage = 'ASR';
      final result = await engine.transcribe(
        AudioRef(staged.path),
        TranscriptionOptions(
          language: 'en',
          serverConsent: ServerConsent(host: asr.host, audioPath: staged.path),
        ),
      );
      if (result.segments.isEmpty) throw StateError('No actual ASR segments');
      stage = 'document';
      final markdown = mediaTranscriptMarkdown(
        origin: YoutubeTranscriptOrigin(
          reference: reference,
          title: meta.title,
          start: const Duration(seconds: 10),
          end: const Duration(seconds: 35),
        ),
        segments: result.segments,
        methodLabel: 'Whisper base ASR v1',
        processedAtLabel: 'probe',
        audioOffset: audio.sourceOffset,
        language: 'en',
      );
      final edited = '$markdown\nReviewed locally.\n';
      if (MarkdownDocument.parse(
            utf8.decode(MarkdownDocument.parse(edited).toBytes()),
          ).toMarkdown() !=
          edited) {
        throw StateError('Document bytes changed');
      }
      report.addAll({
        'asr_segments': result.segments.length,
        'segment_times': [
          for (final s in result.segments)
            {
              'start_ms': s.start!.inMilliseconds + 10000,
              'end_ms': s.end!.inMilliseconds + 10000,
            },
        ],
        'document_byte_roundtrip': true,
        'text_sha256': sha256
            .convert(utf8.encode(result.segments.map((s) => s.text).join('\n')))
            .toString(),
      });
    } finally {
      await staged.release();
      client.cancel();
      WebAssetStore.collectGarbage();
    }
    stage = 'cleanup';
    if (WebAssetStore.totalBytes != 0) {
      throw StateError('Leased audio retained');
    }
    report.addAll({'success': true, 'leased_audio_released': true});
    _report = jsonEncode(report).toJS;
  } on Object catch (error) {
    _report = jsonEncode({
      'success': false,
      'error_type': error.runtimeType.toString(),
      'stage': stage,
      if (error is StateError) 'assertion': error.message.toString(),
      if (error is YoutubeSourceException) 'source_failure': error.failure.name,
    }).toJS;
  } finally {
    unregisterRoots();
  }
}
