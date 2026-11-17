// Gecompileerde webclient met echte transport-, CORS- en documentmodelgrenzen.
// Dit is geen volledige release-UI-proef; er wordt geen bestandskiezer nagebootst.
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

@JS('ocideckLanguageProbeResult')
external set _report(JSString value);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Center(child: Text('Running explicit ASR transport probe')),
    ),
  );
  try {
    final response = await web.window
        .fetch('/fixtures/nl-en-nl.wav'.toJS)
        .toDart;
    if (!response.ok) throw StateError('fixture unavailable');
    final bytes = (await response.arrayBuffer().toDart).toDart.asUint8List();
    final path = WebAssetStore.put(bytes, name: 'mixed-languages.wav');
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
    if (!caps.languageSwitching) {
      throw StateError('no language switching capability');
    }
    final watch = Stopwatch()..start();
    final result = await engine.transcribe(
      AudioRef(path),
      TranscriptionOptions(
        languageSwitching: true,
        serverConsent: ServerConsent(host: profile.host, audioPath: path),
      ),
    );
    watch.stop();
    final languages = result.segments.map((s) => s.language).toSet();
    final body = formatTranscriptBody(result.segments);
    final model = MarkdownDocument.parse(body);
    final success =
        languages.contains('nl') &&
        languages.contains('en') &&
        result.text.toLowerCase().contains('heaven') &&
        result.segments.every((s) => s.end != null && s.languageUncertain) &&
        MarkdownDocument.parse(model.toMarkdown()).toMarkdown() == body;
    _report = jsonEncode({
      'success': success,
      'scope':
          'compiled production web transport/CORS and document model; not full release UI or file-save proof',
      'elapsed_ms': watch.elapsedMilliseconds,
      'segments': result.segments.length,
      'languages': languages.toList(),
      'english_marker_preserved': result.text.toLowerCase().contains('heaven'),
      'document_model_roundtrip': true,
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
