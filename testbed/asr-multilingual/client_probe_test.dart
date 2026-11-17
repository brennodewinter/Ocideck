// Echte productieclient tegen het expliciet gestarte lokale taalwisselendpoint.
// Geen release-UI-proef en geen overgeslagen test als invoer ontbreekt.
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
  test('taalwisselupload bewaart tekst, bronklok en onzekere taaltags', () async {
    final fixture = Platform.environment['OCIDECK_LANGUAGE_FIXTURE'];
    final output = Platform.environment['OCIDECK_LANGUAGE_RESULT'];
    expect(fixture, isNotNull, reason: 'geef de gelabelde NL→EN→NL WAV op');
    expect(output, isNotNull, reason: 'bewaar de echte meetuitkomst');
    final bytes = await File(fixture!).readAsBytes();
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
    expect(caps.languageSwitching, isTrue);
    expect(caps.languages, containsAll(['nl', 'pl', 'en']));
    final watch = Stopwatch()..start();
    final result = await engine.transcribe(
      AudioRef(fixture),
      TranscriptionOptions(
        languageSwitching: true,
        serverConsent: ServerConsent(host: profile.host, audioPath: fixture),
      ),
    );
    watch.stop();
    expect(result.segments, isNotEmpty);
    expect(result.segments.map((s) => s.language), containsAll(['nl', 'en']));
    expect(result.segments.every((s) => s.languageUncertain), isTrue);
    var previous = Duration.zero;
    for (final segment in result.segments) {
      expect(segment.start! >= previous, isTrue);
      expect(segment.end! >= segment.start!, isTrue);
      previous = segment.start!;
    }
    final body = formatTranscriptBody(result.segments);
    expect(body, contains('[en?]'));
    final document = buildTranscriptMarkdown(
      const TranscriptProvenance(
        title: 'Taalwisselproef',
        sourceLabel: 'Publieke MLS/LibriSpeech-fragmenten',
        recordedAt: '2026-11-17',
        sourceKindLabel: 'bestand',
        engineLabel: 'Lokaal ASR v1-spraaksegmentendpoint',
        languageCode: 'Meerdere talen',
      ),
      body,
    );
    final temp = await Directory.systemTemp.createTemp(
      'ocideck-language-probe-',
    );
    try {
      final edited = document.replaceFirst('[nl?]', '[nl]');
      final file = File('${temp.path}/transcript.md');
      await file.writeAsBytes(MarkdownDocument.parse(edited).toBytes());
      expect(
        MarkdownDocument.parse(await file.readAsString()).toMarkdown(),
        edited,
      );
    } finally {
      await temp.delete(recursive: true);
    }
    await File(output!).writeAsString(
      '${const JsonEncoder.withIndent('  ').convert({
        'scope': 'real production HTTP client and document roundtrip; not full release UI',
        'fixture_sha256': sha256.convert(bytes).toString(),
        'elapsed_ms': watch.elapsedMilliseconds,
        'languages': result.segments.map((s) => s.language).toSet().toList(),
        'segments': [
          for (final s in result.segments) {'start': s.start!.inMicroseconds / 1000000, 'end': s.end!.inMicroseconds / 1000000, 'language': s.language, 'language_uncertain': s.languageUncertain},
        ],
        'edit_save_reopen': true,
      })}\n',
    );
  }, timeout: const Timeout(Duration(minutes: 5)));
}
