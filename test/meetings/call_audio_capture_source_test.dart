// De callaudiobron als CaptureSource (#2529). Beoordeeld aan wat de
// pipeline garandeert: één afspeelbare mix, losse bronfiles, provenance
// in sources.json, stilte voor een gemute/weggevallen bron en een
// idempotente stop die alles flusht.
//
// De mixer pace't ticks tegen `clock.now()`; elke test draait daarom
// onder `withClock` met een klok die alleen beweegt als de test hem
// vooruit zet — deterministisch, geen real-time racen.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:clock/clock.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/call_audio_capture_source.dart';
import 'package:ocideck/meetings/call_audio_source.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/wav_sink.dart';
import 'package:ocideck/services/web_asset_store.dart';

import 'fakes/fake_meeting_provider.dart';

const _wholeCall = CallAudioCaptureFact(localOutbound: true, remote: true);

/// De testklok: alles dat de bron aan tijd meet leest dit, en niets
/// beweegt hem behalve de test zelf.
var _now = DateTime.utc(2026, 1, 1, 9);

Future<T> _at<T>(Future<T> Function() body) =>
    withClock(Clock(() => _now), body);

void _advance(Duration d) => _now = _now.add(d);

void main() {
  late Directory tmp;

  setUp(() async {
    _now = DateTime.utc(2026, 1, 1, 9);
    tmp = await Directory.systemTemp.createTemp('callaudio-test');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test(
    'probe volgt de sessiecapability — stil, zonder tap te openen',
    () async {
      final session = await _session(wholeCall: false);
      final source = _source(session);
      expect(await source.probe(), CaptureAvailability.unavailable);
      expect(session.captureStarts, 0);

      session.setCapabilities(
        const MeetingCapabilities(audio: true, callAudio: _wholeCall),
      );
      expect(await source.probe(), CaptureAvailability.available);
      expect(session.captureStarts, 0);
    },
  );

  test(
    'start weigert een verkeerde bronsoort en een sessie zonder tap',
    () async {
      final session = await _session();
      final source = _source(session);
      expect(
        () => source.start(_request(tmp.path, {CaptureSourceKind.microphone})),
        throwsA(isA<UnsupportedSource>()),
      );
      final blinde = await _session(wholeCall: false);
      expect(
        () => _source(blinde).start(_request(tmp.path)),
        throwsA(isA<SourceUnavailable>()),
      );
    },
  );

  test(
    'twee bronnen worden één mix plus eigen files, met provenance',
    () => _at(() async {
      final session = await _session();
      final capture = await _source(session).start(_request(tmp.path));
      // Beide brokken vóór elke kloktijd: de slot-tick van stop() legt
      // ze naast elkaar in dezelfde mix-tick.
      session.captureController!.add(_chunk('a-local', fill: 1000));
      session.captureController!.add(_chunk('b-remote', fill: 2000));
      await _flush();
      final audio = await capture.stop();

      expect(audio.kinds, {CaptureSourceKind.callAudio});
      expect(audio.durablePath, p.join(tmp.path, 'recording.wav'));
      expect(audio.duration, isNot(Duration.zero));

      final mix = await File(p.join(tmp.path, 'recording.wav')).readAsBytes();
      final local = await File(
        p.join(tmp.path, 'call-localOutbound-0.wav'),
      ).readAsBytes();
      final remote = await File(
        p.join(tmp.path, 'call-remote-1.wav'),
      ).readAsBytes();
      for (final f in [mix, local, remote]) {
        expect(f.length, 44 + callAudioTickBytes);
        expect(String.fromCharCodes(f.sublist(0, 4)), 'RIFF');
        expect(String.fromCharCodes(f.sublist(8, 12)), 'WAVE');
      }
      // Elke slice is zijn eigen bron; de mix is hun som.
      expect(_sample(local, 0), 1000);
      expect(_sample(remote, 0), 2000);
      expect(_sample(mix, 0), 3000);

      final manifest =
          jsonDecode(
                await File(p.join(tmp.path, 'sources.json')).readAsString(),
              )
              as Map<String, dynamic>;
      final bronnen = manifest['sources'] as List<dynamic>;
      expect(bronnen, hasLength(2));
      expect(
        bronnen.map((b) => (b as Map)['trackId']),
        containsAll(<String>['a-local', 'b-remote']),
      );
      expect(bronnen.map((b) => (b as Map)['frames']), containsAll([1, 1]));
    }),
  );

  test(
    'de mix clamp op 16-bit, nooit een wrap-around',
    () => _at(() async {
      final session = await _session();
      final capture = await _source(session).start(_request(tmp.path));
      session.captureController!.add(_chunk('a-local', fill: 30000));
      session.captureController!.add(_chunk('b-remote', fill: 30000));
      await _flush();
      await capture.stop();
      final mix = await File(p.join(tmp.path, 'recording.wav')).readAsBytes();
      expect(_sample(mix, 0), 32767);
    }),
  );

  test(
    'een gemute lokale bron levert geen file en geen samples',
    () => _at(() async {
      final session = await _session(startMuted: true);
      final capture = await _source(session).start(_request(tmp.path));
      session.captureController!.add(_chunk('a-local', fill: 1000));
      session.captureController!.add(_chunk('b-remote', fill: 2000));
      await _flush();
      await capture.stop();
      expect(
        File(p.join(tmp.path, 'call-localOutbound-0.wav')).existsSync(),
        isFalse,
      );
      final mix = await File(p.join(tmp.path, 'recording.wav')).readAsBytes();
      expect(_sample(mix, 0), 2000);
    }),
  );

  test(
    'een track die ná het begin joint krijgt zijn eigen bronfile',
    () => _at(() async {
      final session = await _session();
      final capture = await _source(session).start(_request(tmp.path));
      session.captureController!.add(_chunk('a-local', fill: 1000));
      await _flush(); // eerst leveren, pas dan de klok vooruit
      _advance(const Duration(milliseconds: 40));
      session.captureController!.add(_chunk('c-remote', fill: 500));
      await _flush();
      await capture.stop();
      expect(File(p.join(tmp.path, 'call-remote-1.wav')).existsSync(), isTrue);
      final manifest =
          jsonDecode(
                await File(p.join(tmp.path, 'sources.json')).readAsString(),
              )
              as Map<String, dynamic>;
      expect((manifest['sources'] as List).length, 2);
    }),
  );

  test(
    'een bron zonder levering vult zijn gat met stilte — de tijdlijn loopt',
    () => _at(() async {
      final session = await _session();
      final capture = await _source(session).start(_request(tmp.path));
      // Een halve tick echte data van A, daarna drie seconden niets —
      // langer dan de starvatiegrens.
      session.captureController!.add(_chunk('a-local', fill: 1000, bytes: 320));
      await _flush();
      _advance(const Duration(seconds: 3));
      // B's brok trekt de drain; A is starving en vult met stilte.
      session.captureController!.add(_chunk('b-remote', fill: 2000));
      await _flush();
      await capture.stop();

      final local = await File(
        p.join(tmp.path, 'call-localOutbound-0.wav'),
      ).readAsBytes();
      expect(local.length, 44 + callAudioTickBytes);
      expect(_sample(local, 0), 1000);
      // De eerste 320 bytes zijn echt; daarna stilte, niet herhaalde
      // samples of verloren tijd.
      expect(_sample(local, 200), 0);
    }),
  );

  test(
    'een eindigende bronstroom meldt sourceLost; wat er stond is bewaard',
    () => _at(() async {
      final session = await _session();
      final capture = await _source(session).start(_request(tmp.path));
      final causes = <CaptureEndCause>[];
      final sub = capture.ended!.listen(causes.add);
      session.captureController!.add(_chunk('a-local', fill: 1000));
      await _flush();
      await session.captureController!.close();
      await _flush();
      expect(causes, [CaptureEndCause.sourceLost]);
      final audio = await capture.stop();
      expect(audio.durablePath, isNotEmpty);
      expect(File(p.join(tmp.path, 'recording.wav')).lengthSync(), 44 + 640);
      await sub.cancel();
    }),
  );

  test(
    'stop is idempotent en levert twee keer hetzelfde resultaat',
    () => _at(() async {
      final session = await _session();
      final capture = await _source(session).start(_request(tmp.path));
      session.captureController!.add(_chunk('a-local', fill: 42));
      await _flush();
      final a = await capture.stop();
      final b = await capture.stop();
      expect(a.durablePath, b.durablePath);
      expect(a.duration, b.duration);
    }),
  );

  test(
    'zonder stagingmap eindigt de mix als mem:-asset met manifest (web)',
    () => _at(() async {
      final session = await _session();
      final capture = await _source(session).start(_request(null));
      session.captureController!.add(_chunk('a-local', fill: 1000));
      session.captureController!.add(_chunk('b-remote', fill: 2000));
      await _flush();
      final audio = await capture.stop();

      expect(audio.durablePath, startsWith('mem:'));
      final wav = WebAssetStore.bytesFor(audio.durablePath)!;
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(wav.length, 44 + callAudioTickBytes);
      expect(_sample(wav, 0), 3000);
      // Geen bronfiles in het beperkte geheugen — alleen de mix plus het
      // manifest als tweede asset.
    }),
  );

  test(
    'liveChunks levert dezelfde bytes als de duurzame mix',
    () => _at(() async {
      final session = await _session();
      final capture = await _source(session).start(_request(tmp.path));
      final live = <Uint8List>[];
      final sub = capture.liveChunks!.listen((c) => live.add(c.bytes));
      session.captureController!.add(_chunk('a-local', fill: 777));
      await _flush();
      // Tijd voorbij de eerste tick: de drain mag één tick uitsturen.
      _advance(const Duration(milliseconds: 30));
      session.captureController!.add(_chunk('b-remote', fill: 111));
      await _flush();
      await capture.stop();
      await sub.cancel();
      expect(live, hasLength(1));
      // liveChunks zijn kale PCM (de offset zit in het AudioChunk); de
      // duurzame file heeft er de WAV-header bij.
      expect(
        ByteData.sublistView(live.first).getInt16(0, Endian.little),
        777 + 111,
      );
      final onDisk = await File(
        p.join(tmp.path, 'recording.wav'),
      ).readAsBytes();
      expect(live.first, onDisk.sublist(44));
    }),
  );
}

/// De chunk- en drain-callbacks draaien op microtasks; één echte stap
/// event-loop is genoeg — de klok zelf staat bevroren.
Future<void> _flush() => Future<void>.delayed(const Duration(milliseconds: 10));

int _sample(List<int> wav, int index) => ByteData.sublistView(
  Uint8List.fromList(wav),
).getInt16(44 + index * 2, Endian.little);

var _chunkSeq = 0;

CallAudioChunk _chunk(
  String trackId, {
  CallAudioRole? role,
  int fill = 0,
  int bytes = callAudioTickBytes,
}) {
  final pcm = Uint8List(bytes);
  final view = ByteData.sublistView(pcm);
  for (var i = 0; i + 1 < bytes; i += 2) {
    view.setInt16(i, fill, Endian.little);
  }
  return CallAudioChunk(
    participantId: trackId.endsWith('local') ? 'ik' : 'zij',
    role:
        role ??
        (trackId.endsWith('local')
            ? CallAudioRole.localOutbound
            : CallAudioRole.remote),
    trackId: trackId,
    at: DateTime.utc(2026, 10, 26).add(Duration(milliseconds: _chunkSeq++ * 5)),
    pcm: pcm,
    sampleRateHz: recordingSampleRate,
  );
}

CallAudioCaptureSource _source(FakeMeetingSession session) =>
    // freeBytes geïnjecteerd: de echte meting raakt een platform channel
    // en dat bestaat in een test niet — de broncode krijgt netto dezelfde
    // "platform zegt niets"-uitkomst.
    CallAudioCaptureSource(session: session, freeBytes: (_) async => null);

Future<FakeMeetingSession> _session({
  bool wholeCall = true,
  bool startMuted = false,
}) async {
  const provider = FakeMeetingProvider();
  final match = provider.match(Uri.parse('https://fake.local/r'))!;
  final session =
      await provider.join(
            MeetingJoinRequest(
              link: match,
              displayName: 'Me',
              startMuted: startMuted,
            ),
          )
          as FakeMeetingSession;
  session.captureController = StreamController<CallAudioChunk>();
  session.setCapabilities(
    MeetingCapabilities(
      audio: true,
      callAudio: wholeCall ? _wholeCall : unavailableCallAudio,
    ),
  );
  return session;
}

CaptureRequest _request(String? stagingDir, [Set<CaptureSourceKind>? kinds]) =>
    CaptureRequest(
      kinds: kinds ?? {CaptureSourceKind.callAudio},
      consent: const RecordingConsent(participantNoticeAcknowledged: true),
      stagingDir: stagingDir,
    );
