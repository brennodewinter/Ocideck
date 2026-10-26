// Integratietoets van de live-ASR-serverroute tegen de lokale Vosk-
// testbed (`testbed/vosk-asr/`, #2525). Dit is de acceptatie die unit-
// tests niet kunnen zijn: een ÉCHTE WebSocket naar een échte
// ASR-server — de protocolproef, partiële hypothesen tijdens de stroom,
// de definitieve uitslag over dezelfde WAV, en einde zonder extra
// audiopakketten na `{"eof" : 1}`.
//
// Gated achter OCIDECK_ASR_INTEGRATION=1; de stack moet draaien:
//   testbed/vosk-asr/fetch-model.sh && docker compose -f
//   testbed/vosk-asr/docker-compose.yml up -d
// Run: OCIDECK_ASR_INTEGRATION=1 make test-asr-integration
//
// De testbed staat op loopback, dus het profiel is `loopback` met een
// letterlijk adres — `localhost` is een naam en gaat langs DNS.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_live_protocol.dart';
import 'package:ocideck/services/transcription/asr_live_server_engine.dart';
import 'package:ocideck/services/transcription/asr_live_transport_io.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';

const _liveUrl = 'ws://127.0.0.1:2700';
const _wavPath = 'testbed/vosk-asr/fixtures/test16k.wav';

bool get _enabled => Platform.environment['OCIDECK_ASR_INTEGRATION'] == '1';

AsrLiveServerEngine engine(Uint8List wavBytes) => AsrLiveServerEngine(
  profile: const AsrServerProfile(
    enabled: true,
    mode: AsrServerMode.loopback,
    baseUrl: 'http://127.0.0.1:2700',
    liveUrl: _liveUrl,
  ),
  transport: const IoAsrLiveTransport(),
  audioReader: (_) async => wavBytes,
);

/// De WAV als opeenvolgende live-chunks — hetzelfde aard als wat een
/// capture levert: 0,2 s per blok (6400 bytes aan 16 kHz s16le mono).
Stream<AudioChunk> liveChunks(Uint8List pcm) async* {
  const frameBytes = 6400;
  const bytesPerSecond = 32000;
  for (var off = 0; off < pcm.length; off += frameBytes) {
    final end = (off + frameBytes).clamp(0, pcm.length);
    yield AudioChunk(
      bytes: Uint8List.sublistView(pcm, off, end),
      offset: Duration(microseconds: (off * 1000000) ~/ bytesPerSecond),
    );
  }
}

void main() {
  if (!_enabled) {
    test(
      'ASR live testbed integration (skipped — set OCIDECK_ASR_INTEGRATION=1)',
      () {},
      tags: ['integration'],
    );
    return;
  }

  late Uint8List wavBytes;
  late Uint8List pcm;

  setUpAll(() {
    wavBytes = File(_wavPath).readAsBytesSync();
    final data = wavPcmData(wavBytes);
    expect(data, isNotNull, reason: 'de fixture is een leesbare WAV');
    pcm = data!;
  });

  test(
    'de capability-proef bewijst vosk-ws-1 op de echte server',
    () async {
      final probe = await engine(wavBytes).probeLive();
      expect(probe.status, AsrProbeStatus.reachable);
      expect(probe.detail, liveProtocolId);
    },
    tags: ['integration'],
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'live: partiële hypothesen tijdens de stroom, einde na eof',
    () async {
      final partials = await engine(wavBytes)
          .transcribeLive(
            liveChunks(pcm),
            options: const TranscriptionOptions(
              serverConsent: ServerConsent.liveSession('127.0.0.1'),
            ),
          )!
          .toList();

      // De echte server antwoordt met hypothesen — minstens één draagt
      // echte tekst (de clip bevat gesproken Engels).
      final withText = partials.where((p) => p.text.trim().isNotEmpty);
      expect(
        withText,
        isNotEmpty,
        reason: 'een live-server levert tekst tijdens de stroom',
      );
      for (final p in withText) {
        // ignore: avoid_print — bewijsoutput van de integratietoets.
        print('partial: ${p.text}');
      }
    },
    tags: ['integration'],
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'definitief: dezelfde WAV levert een echt transcript',
    () async {
      final result = await engine(wavBytes).transcribe(
        const AudioRef(_wavPath),
        const TranscriptionOptions(
          serverConsent: ServerConsent(host: '127.0.0.1', audioPath: _wavPath),
        ),
      );
      final text = result.segments.map((s) => s.text).join(' ').trim();
      expect(text, isNotEmpty, reason: 'de server transcribeert de clip');
      // Woordtijden uit `words:true` — de engine claimt ze, dus de echte
      // server moet ze leveren.
      expect(
        result.segments.any((s) => s.start != null),
        isTrue,
        reason: 'woorden met tijdstempels',
      );
      // ignore: avoid_print — bewijsoutput van de integratietoets.
      print('definitief: $text');
    },
    tags: ['integration'],
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
