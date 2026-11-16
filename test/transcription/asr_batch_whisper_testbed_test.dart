// Optionele echte whisper.cpp-serverproef (#2952). Start een lokale
// whisper-server en zet OCIDECK_BATCH_ASR_URL op diens loopbackbasis-URL.
// De opgenomen testbedfixture bevat geen gebruikersaudio.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/asr_transport_io.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';

void main() {
  final base = Platform.environment['OCIDECK_BATCH_ASR_URL'];
  test(
    'echte whisper-server accepteert vaste WAV-uploadnaam voor ieder bronpad',
    () async {
      final uri = Uri.parse(base!);
      expect(uri.host, '127.0.0.1', reason: 'uitsluitend lokaal testverkeer');
      final audio = await File(
        'testbed/vosk-asr/fixtures/test16k.wav',
      ).readAsBytes();
      for (final path in [
        r'C:\Users\Alice\Private\recording.wav',
        '/privé/音声 "test"\r\nX-Injected: secret.wav',
        'mem:fixture',
      ]) {
        final engine = AsrServerEngine(
          profile: AsrServerProfile(
            enabled: true,
            mode: AsrServerMode.loopback,
            baseUrl: base,
          ),
          transport: const IoAsrTransport(),
          audioReader: (_) async => audio,
        );
        final result = await engine.transcribe(
          AudioRef(path),
          TranscriptionOptions(
            language: 'en',
            serverConsent: ServerConsent(host: uri.host, audioPath: path),
          ),
        );
        expect(result.text.trim(), isNotEmpty);
        expect(result.segments, isNotEmpty);
      }
    },
    skip: base == null
        ? 'zet OCIDECK_BATCH_ASR_URL voor een lokale whisper-server'
        : false,
    tags: ['integration'],
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
