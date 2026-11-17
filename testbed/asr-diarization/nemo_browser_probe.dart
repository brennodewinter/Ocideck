// Echte gecompileerde webclient tegen het expliciete lokale diariseringsendpoint.
// Dit is transport/CORS/documentmodelbewijs, geen volledige release-UI-proef.
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/services/transcription/asr_audio_source.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/transcript_document.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/web_asset_store.dart';

@JS('ocideckDiarizationProbeResult')
external set _report(JSString value);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(
        child: Text('Running explicit diarization transport probe'),
      ),
    ),
  );
  try {
    final response = await web.window.fetch('/fixtures/audio.wav'.toJS).toDart;
    if (!response.ok) {
      throw StateError('Fixture unavailable');
    }
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    final path = WebAssetStore.put(bytes, name: 'speaker-probe.wav');
    const profile = AsrServerProfile(
      enabled: true,
      mode: AsrServerMode.loopback,
      baseUrl: 'https://127.0.0.1:8443',
      batchProtocol: AsrBatchProtocol.ocideckV1,
    );
    final engine = AsrServerEngine(
      profile: profile,
      transport: createAsrTransport(),
      audioReader: readAsrAudio,
    );
    final caps = await engine.capabilities();
    if (!caps.diarization) {
      throw StateError('No diarization capability');
    }
    final watch = Stopwatch()..start();
    final result = await engine.transcribe(
      AudioRef(path),
      TranscriptionOptions(
        language: 'nl',
        diarize: true,
        serverConsent: ServerConsent(host: profile.host, audioPath: path),
      ),
    );
    watch.stop();
    final early = result.segments
        .where((s) => s.start! < const Duration(seconds: 15))
        .expand((s) => s.speakerIds)
        .toSet();
    final middle = result.segments
        .where(
          (s) =>
              s.start! >= const Duration(milliseconds: 16490) &&
              s.end! <= const Duration(milliseconds: 34640),
        )
        .expand((s) => s.speakerIds)
        .toSet();
    final returning = result.segments
        .where((s) => s.start! >= const Duration(milliseconds: 35640))
        .expand((s) => s.speakerIds)
        .toSet();
    final consistent =
        early.length == 1 &&
        middle.length == 1 &&
        returning.length == 1 &&
        returning.contains(early.single) &&
        middle.intersection(early).isEmpty;
    final body = formatTranscriptBody(
      result.segments,
    ).replaceAll('Spreker 1', 'Alice');
    final document = MarkdownDocument.parse(body);
    final roundtrip =
        MarkdownDocument.parse(document.toMarkdown()).toMarkdown() == body;
    final success =
        consistent &&
        roundtrip &&
        body.contains('Alice (?)') &&
        result.segments.every((s) => s.end != null && s.speakerUncertain);
    _report = jsonEncode({
      'success': success,
      'scope':
          'compiled production web transport/CORS and document model; not full release UI or file-save proof',
      'elapsed_ms': watch.elapsedMilliseconds,
      'segments': result.segments.length,
      'known_aba_ids_consistent': consistent,
      'document_rename_model_roundtrip': roundtrip,
      'unknown_segments': result.segments
          .where((s) => s.speakerIds.isEmpty)
          .length,
      'file_save_reopen_proven': false,
    }).toJS;
  } on Object catch (error) {
    _report = jsonEncode({
      'success': false,
      'error_type': '${error.runtimeType}',
      'error': '$error',
    }).toJS;
  } finally {
    WebAssetStore.clear();
  }
}
