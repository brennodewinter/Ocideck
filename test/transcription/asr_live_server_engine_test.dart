// De live-serverengine (#2525) met een fake socket: de bewijsvoering
// is wat er op de draad gaat (config, PCM-frames in volgorde, eof),
// welke consent vereist is, en hoe breuken landen — zonder dat een
// test het netwerk raakt.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_live_protocol.dart';
import 'package:ocideck/services/transcription/asr_live_server_engine.dart';
import 'package:ocideck/services/transcription/asr_live_transport.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';

/// Een socket die alles bijhoudt wat OciDeck stuurde, en waar de test
/// zelf server-frames in kan voeren.
class FakeLiveSocket implements AsrLiveSocket {
  final inbound = StreamController<Object>();
  final sentText = <String>[];
  final sentBytes = <Uint8List>[];
  var closed = false;
  int? closedWith;

  @override
  Stream<Object> get messages => inbound.stream;

  @override
  int? get closeCode => closedWith;

  @override
  void sendBytes(Uint8List frame) => sentBytes.add(frame);

  @override
  void sendText(String frame) => sentText.add(frame);

  @override
  Future<void> close() async {
    closed = true;
  }

  /// De server sluit zijn kant — alsof de socket doodging.
  Future<void> serverCloses([int code = 1000]) async {
    closedWith = code;
    await inbound.close();
  }
}

/// Een transport dat per connect een nieuwe [FakeLiveSocket] maakt —
/// de test stelt van tevoren in hoeveel hij er wil, of gooit.
class FakeLiveTransport implements AsrLiveTransport {
  final sockets = <FakeLiveSocket>[];
  Object? throwWith;
  Uri? lastUrl;
  Map<String, String>? lastHeaders;
  var connectCount = 0;

  @override
  Future<AsrLiveSocket> connect({
    required Uri url,
    required AiResolveStrategy strategy,
    Map<String, String> headers = const {},
  }) async {
    connectCount++;
    lastUrl = url;
    lastHeaders = headers;
    if (throwWith != null) throw throwWith!;
    final socket = FakeLiveSocket();
    sockets.add(socket);
    return socket;
  }
}

const profile = AsrServerProfile(
  enabled: true,
  mode: AsrServerMode.loopback,
  baseUrl: 'http://127.0.0.1:8080',
  liveUrl: 'ws://127.0.0.1:2700',
);

AsrLiveServerEngine engine(
  FakeLiveTransport transport, {
  Future<String?> Function()? apiKeyReader,
  AsrServerProfile profile = profile,
  AsrAudioReader? audioReader,
}) {
  return AsrLiveServerEngine(
    profile: profile,
    transport: transport,
    audioReader: audioReader ?? ((_) async => Uint8List(0)),
    apiKeyReader: apiKeyReader,
  );
}

const consent = ServerConsent.liveSession('127.0.0.1');
TranscriptionOptions get options =>
    const TranscriptionOptions(serverConsent: consent);

/// Wacht tot de engine de socket open heeft — `transcribeLive`
/// verbindt asynchroon nadat hij de stream teruggaf.
Future<FakeLiveSocket> opened(FakeLiveTransport t) async {
  for (var i = 0; i < 100 && t.sockets.isEmpty; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(t.sockets, isNotEmpty);
  return t.sockets.last;
}

AudioChunk chunk(int seed, [int offsetMs = 0]) => AudioChunk(
  bytes: Uint8List.fromList([seed, seed + 1]),
  offset: Duration(milliseconds: offsetMs),
);

/// Een minimale WAV met 4 bytes PCM — genoeg voor de definitieve pass.
Uint8List wav() {
  final b = ByteData(44 + 4);
  void tag(int off, String t) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(off + i, t.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + 4, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, 4, Endian.little);
  return b.buffer.asUint8List();
}

void main() {
  group('consent (§4.3 sessie-scope)', () {
    test('zonder consent: ConsentRequired, en geen socket', () async {
      final t = FakeLiveTransport();
      final s = engine(t).transcribeLive(const Stream.empty())!;
      await expectLater(s, emitsError(isA<ConsentRequired>()));
      expect(t.connectCount, 0);
    });

    test('een per-taakconsent dekt geen stream', () async {
      final t = FakeLiveTransport();
      final s = engine(t).transcribeLive(
        const Stream.empty(),
        options: const TranscriptionOptions(
          serverConsent: ServerConsent(host: '127.0.0.1', audioPath: '/x.wav'),
        ),
      )!;
      await expectLater(s, emitsError(isA<ConsentRequired>()));
      expect(t.connectCount, 0);
    });

    test('sessieconsent voor een andere host vertrekt niet', () async {
      final t = FakeLiveTransport();
      final s = engine(t).transcribeLive(
        const Stream.empty(),
        options: const TranscriptionOptions(
          serverConsent: ServerConsent.liveSession('10.0.0.5'),
        ),
      )!;
      await expectLater(s, emitsError(isA<ConsentRequired>()));
      expect(t.connectCount, 0);
    });
  });

  group('poort', () {
    test('uitgeschakeld profiel: EngineUnavailable, geen socket', () async {
      final t = FakeLiveTransport();
      final s = engine(
        t,
        profile: const AsrServerProfile(
          enabled: false,
          mode: AsrServerMode.loopback,
          baseUrl: 'http://127.0.0.1:8080',
          liveUrl: 'ws://127.0.0.1:2700',
        ),
      ).transcribeLive(const Stream.empty(), options: options)!;
      await expectLater(s, emitsError(isA<EngineUnavailable>()));
      expect(t.connectCount, 0);
    });
  });

  group('de draad', () {
    test(
      'config vooraf, PCM-frames in chunkvolgorde, eof bij sluiten',
      () async {
        final t = FakeLiveTransport();
        final chunks = StreamController<AudioChunk>();
        final partials = <PartialTranscript>[];
        final done = engine(
          t,
        ).transcribeLive(chunks.stream, options: options)!.listen(partials.add);

        final socket = await opened(t);
        // Config staat er vóór er audio gaat.
        expect(socket.sentText.single, buildLiveConfigFrame(sampleRate: 16000));

        chunks.add(chunk(1, 100));
        chunks.add(chunk(3, 200));
        await pumpEventQueue();
        expect(socket.sentBytes, hasLength(2));
        expect(socket.sentBytes[0], [1, 2]);
        expect(socket.sentBytes[1], [3, 4]);

        // Partial en result komen als PartialTranscript terug.
        socket.inbound.add('{"partial":"hal"}');
        socket.inbound.add(
          '{"result":[{"word":"hallo","start":0.1,"end":0.4}],'
          '"text":"hallo"}',
        );
        await pumpEventQueue();
        expect(partials.map((p) => p.text), ['hal', 'hallo']);
        expect(partials.last.offset, const Duration(milliseconds: 100));

        // Stop: het laatste wat op de draad gaat is eof — geen audio meer.
        await chunks.close();
        await pumpEventQueue();
        expect(socket.sentText.last, liveEofFrame);
        await socket.serverCloses();
        await done.asFuture<void>();
      },
    );

    test('onbekende serverframes worden genegeerd', () async {
      final t = FakeLiveTransport();
      final partials = <PartialTranscript>[];
      final errors = <Object>[];
      engine(t)
          .transcribeLive(const Stream.empty(), options: options)!
          .listen(partials.add, onError: errors.add);

      final socket = await opened(t);
      socket.inbound.add('{"vreemd":123}');
      socket.inbound.add('geen json');
      await pumpEventQueue();
      expect(partials, isEmpty);
      expect(errors, isEmpty);
      await socket.serverCloses();
    });

    test(
      'de api-sleutel gaat in de handshake-header, niet in de URL',
      () async {
        final t = FakeLiveTransport();
        engine(t, apiKeyReader: () async => 'sk-test')
            .transcribeLive(const Stream.empty(), options: options)!
            .listen((_) {});
        final socket = await opened(t);
        expect(t.lastHeaders, {'authorization': 'Bearer sk-test'});
        expect(t.lastUrl.toString(), isNot(contains('sk-test')));
        await socket.serverCloses();
      },
    );
  });

  group('breuken', () {
    test('connect mislukt: ServerRefused', () async {
      final t = FakeLiveTransport()
        ..throwWith = const AsrLiveException('verbinding mislukt');
      final s = engine(
        t,
      ).transcribeLive(const Stream.empty(), options: options)!;
      await expectLater(s, emitsError(isA<ServerRefused>()));
    });

    test(
      'server breekt vóór eof: ServerRefused, geen stille reconnect',
      () async {
        final t = FakeLiveTransport();
        final error = Completer<Object>();
        // Open chunkstroom — de server mag niet ná de eof breken, dat
        // is de normale afsluiting, maar er middenin.
        final chunks = StreamController<AudioChunk>();
        engine(t)
            .transcribeLive(chunks.stream, options: options)!
            .listen((_) {}, onError: error.complete);
        final socket = await opened(t);
        await socket.serverCloses(1006);
        expect(await error.future, isA<ServerRefused>());
        await chunks.close();
        // De engine probeert niet zelf opnieuw — herstel is een keuze van
        // de laag erboven, nooit stil.
        expect(t.connectCount, 1);
      },
    );

    test('een socketfout onderweg is ServerRefused', () async {
      final t = FakeLiveTransport();
      final error = Completer<Object>();
      final chunks = StreamController<AudioChunk>();
      engine(t)
          .transcribeLive(chunks.stream, options: options)!
          .listen((_) {}, onError: error.complete);
      final socket = await opened(t);
      socket.inbound.addError(StateError('weg'));
      expect(await error.future, isA<ServerRefused>());
      await chunks.close();
    });

    test('annuleren sluit de socket en er gaat geen audio meer heen', () async {
      final t = FakeLiveTransport();
      final chunks = StreamController<AudioChunk>();
      final s = engine(
        t,
      ).transcribeLive(chunks.stream, options: options)!.listen((_) {});
      final socket = await opened(t);
      chunks.add(chunk(7));
      await pumpEventQueue();
      final sent = socket.sentBytes.length;
      await s.cancel();
      engine(t).cancel();
      chunks.add(chunk(9));
      await pumpEventQueue();
      expect(socket.sentBytes.length, sent);
      expect(socket.closed, isTrue);
      await chunks.close();
    });
  });

  group('definitieve pass over dezelfde draad', () {
    test('WAV-PCM gaat in frames weg, resultaten worden segmenten', () async {
      final t = FakeLiveTransport();
      final progress = <double>[];
      final future = engine(t, audioReader: (_) async => wav()).transcribe(
        const AudioRef('/rec.wav'),
        TranscriptionOptions(
          serverConsent: const ServerConsent(
            host: '127.0.0.1',
            audioPath: '/rec.wav',
          ),
          onProgress: progress.add,
        ),
      );

      final socket = await opened(t);
      socket.inbound.add(
        '{"result":[{"word":"hallo","start":0.0,"end":0.5}],'
        '"text":"hallo"}',
      );
      socket.inbound.add('{"result":[],"text":"weer"}');
      // Wacht tot de engine zijn eof stuurde — daarna mag de server
      // sluiten zoals het protocol voorschrijft.
      while (!socket.sentText.contains(liveEofFrame)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await socket.serverCloses();

      final result = await future;
      expect(result.segments.map((s) => s.text), ['hallo', 'weer']);
      expect(result.segments.first.start, Duration.zero);
      expect(result.text, 'halloweer');
      expect(socket.sentText.first, buildLiveConfigFrame(sampleRate: 16000));
      expect(progress.last, 1.0);
    });

    test('sessieconsent dekt de definitieve pass op dezelfde host', () async {
      final t = FakeLiveTransport();
      final future = engine(
        t,
        audioReader: (_) async => wav(),
      ).transcribe(const AudioRef('/rec.wav'), options);
      final socket = await opened(t);
      while (!socket.sentText.contains(liveEofFrame)) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      await socket.serverCloses();
      await future;
    });

    test('taskconsent op een ander bestand is ConsentRequired', () {
      final t = FakeLiveTransport();
      expect(
        engine(t).transcribe(
          const AudioRef('/rec.wav'),
          const TranscriptionOptions(
            serverConsent: ServerConsent(
              host: '127.0.0.1',
              audioPath: '/ander.wav',
            ),
          ),
        ),
        throwsA(isA<ConsentRequired>()),
      );
      expect(t.connectCount, 0);
    });

    test('geen WAV is DecodeFailed, geen upload', () {
      final t = FakeLiveTransport();
      expect(
        engine(
          t,
          audioReader: (_) async => Uint8List.fromList('OGG'.codeUnits),
        ).transcribe(
          const AudioRef('/rec.ogg'),
          const TranscriptionOptions(
            serverConsent: ServerConsent(
              host: '127.0.0.1',
              audioPath: '/rec.ogg',
            ),
          ),
        ),
        throwsA(isA<DecodeFailed>()),
      );
    });
  });

  group('protocolproef (probeLive)', () {
    test('een antwoord in protocolvorm is bewezen live-capable', () async {
      final t = FakeLiveTransport();
      final probe = engine(t).probeLive();
      final socket = await opened(t);
      expect(socket.sentText, [
        buildLiveConfigFrame(sampleRate: 16000),
        liveEofFrame,
      ]);
      socket.inbound.add('{"result":[],"text":""}');
      final result = await probe;
      expect(result.status, AsrProbeStatus.reachable);
      expect(result.detail, liveProtocolId);
    });

    test('een socket die wel opent maar niets zegt is unreachable', () async {
      final t = FakeLiveTransport();
      final probe = engine(t).probeLive();
      final socket = await opened(t);
      socket.inbound.add('{"vreemd":1}');
      expect((await probe).status, AsrProbeStatus.unreachable);
    });

    test('connect-fout is unreachable, gate-weigering is refused', () async {
      final t = FakeLiveTransport()
        ..throwWith = const AsrLiveException('verbinding mislukt');
      expect((await engine(t).probeLive()).status, AsrProbeStatus.unreachable);

      final denied = FakeLiveTransport();
      final result = await engine(
        denied,
        profile: const AsrServerProfile(enabled: false),
      ).probeLive();
      expect(result.status, AsrProbeStatus.refused);
      expect(denied.connectCount, 0);
    });
  });
}
