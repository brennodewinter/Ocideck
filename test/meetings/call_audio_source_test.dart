import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/call_audio_source.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_participant.dart';

void main() {
  test('de capability volgt het bewezen platform, niet de binding-wens', () {
    final fact = callAudioCaptureOfCurrentBinding();
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.macOS) {
      // Darwin-sink en Web Audio zijn gebouwd — de claim bestaat.
      expect(fact.wholeCall, isTrue);
      expect(fact.denial, isNull);
    } else {
      expect(fact, unavailableCallAudio);
      expect(fact.wholeCall, isFalse);
      expect(fact.denial, CallAudioDenial.noPerSourceTap);
    }
  });

  test('een track-id en een opname-lampje starten geen opname', () async {
    const track = MeetingTrack(
      id: 'opaque-track',
      kind: MeetingTrackKind.audio,
    );
    const lamp = RecordingIndicatorChanged(active: true);
    final chunks = await openCallAudioCapture(
      callAudioCaptureOfCurrentBinding(),
      const Stream<CallAudioTrackTap>.empty(),
    ).toList();
    expect(chunks, isEmpty);
    expect(track.kind, MeetingTrackKind.audio);
    expect(lamp.active, isTrue);
  });

  test('alleen de microfoon is geen hele call', () async {
    const micOnly = CallAudioCaptureFact(
      localOutbound: true,
      remote: false,
      denial: CallAudioDenial.remoteMissing,
    );
    expect(micOnly.wholeCall, isFalse);
    expect(
      await openCallAudioCapture(
        micOnly,
        const Stream<CallAudioTrackTap>.empty(),
      ).toList(),
      isEmpty,
    );
  });

  test('een wholeCall-claim met taps levert chunks per bron', () async {
    const fact = CallAudioCaptureFact(localOutbound: true, remote: true);
    final taps = Stream<CallAudioTrackTap>.fromIterable([
      _tap('lokaal-1', CallAudioRole.localOutbound),
      _tap('remote-1', CallAudioRole.remote),
    ]);
    final chunks = await openCallAudioCapture(fact, taps).toList();
    expect(chunks, hasLength(2));
    expect(chunks[0].role, CallAudioRole.localOutbound);
    expect(chunks[0].trackId, 'lokaal-1');
    expect(chunks[1].role, CallAudioRole.remote);
    expect(chunks.every((c) => c.sampleRateHz == 16000), isTrue);
    expect(chunks.every((c) => c.pcm.isNotEmpty), isTrue);
  });

  test('een remote track die later joint tapt gewoon mee', () async {
    const fact = CallAudioCaptureFact(localOutbound: true, remote: true);
    final taps = Stream<CallAudioTrackTap>.multi((ctrl) {
      ctrl.add(_tap('lokaal-1', CallAudioRole.localOutbound));
      Future<void>.delayed(const Duration(milliseconds: 30)).then((_) {
        ctrl.add(_tap('remote-late', CallAudioRole.remote));
        ctrl.close();
      });
    });
    final chunks = await openCallAudioCapture(fact, taps).toList();
    expect(
      chunks.map((c) => c.trackId),
      containsAll(['lokaal-1', 'remote-late']),
    );
  });

  group('callPcmFrame16k', () {
    test('16k mono passeert ongemoeid', () {
      final pcm = _s16([1, -1, 1000, -1000]);
      final f = callPcmFrame16k(pcm, 16000, 1);
      expect(f.sampleRateHz, 16000);
      expect(_backToS16(f.pcm), [1, -1, 1000, -1000]);
    });

    test('48k mono wordt driemaal zo kort', () {
      // 9 samples van 48k -> 3 van 16k; constante bron blijft constant.
      final pcm = _s16(List.filled(9, 300));
      final f = callPcmFrame16k(pcm, 48000, 1);
      expect(f.sampleRateHz, 16000);
      expect(f.pcm.lengthInBytes, 6);
      expect(_backToS16(f.pcm), [300, 300, 300]);
    });

    test('stereo 48k downmixt naar mono 16k', () {
      // Links 1000 / rechts 0 -> mono ~500.
      final pcm = _s16([1000, 0, 1000, 0, 1000, 0]);
      final f = callPcmFrame16k(pcm, 48000, 2);
      expect(f.sampleRateHz, 16000);
      final v = _backToS16(f.pcm);
      expect(v.length, 1);
      expect(v[0], inInclusiveRange(499, 501));
    });

    test('44.1k resampled naar 16k zonder te klakken', () {
      // 441 samples -> 160; rustig signaal blijft rustig.
      final pcm = _s16(List.filled(441, -200));
      final f = callPcmFrame16k(pcm, 44100, 1);
      expect(f.pcm.lengthInBytes, 160 * 2);
      expect(_backToS16(f.pcm).every((v) => v == -200), isTrue);
    });
  });

  test(
    'de poort laat remote door, gemute lokaal niet, en telt niet dubbel',
    () {
      const fact = CallAudioCaptureFact(localOutbound: true, remote: true);
      final gate = CallAudioGate(fact);
      final t0 = DateTime.utc(2026, 10, 25, 12);
      final local = _chunk(CallAudioRole.localOutbound, t0, 'ik');
      final remote = _chunk(CallAudioRole.remote, t0, 'zij');

      expect(gate.consider(local, localMuted: true), isNull);
      expect(gate.consider(local, localMuted: false), same(local));
      expect(gate.consider(local, localMuted: false), isNull);
      expect(
        gate.consider(
          _chunk(
            CallAudioRole.localOutbound,
            t0.add(const Duration(milliseconds: 20)),
            'ik',
          ),
          localMuted: false,
        ),
        isNotNull,
      );
      expect(gate.consider(remote, localMuted: true), same(remote));
      expect(
        gate.consider(
          _chunk(CallAudioRole.remote, t0, 'zij'),
          localMuted: false,
        ),
        isNull,
      );
    },
  );

  test('een niet-beschikbare capability laat geen enkel brok door', () {
    final gate = CallAudioGate(unavailableCallAudio);
    final chunk = _chunk(
      CallAudioRole.remote,
      DateTime.utc(2026, 10, 25, 12),
      'zij',
    );
    expect(gate.consider(chunk, localMuted: false), isNull);
  });
}

CallAudioTrackTap _tap(String trackId, CallAudioRole role) {
  return CallAudioTrackTap(
    trackId: trackId,
    role: role,
    frames: Stream<CallPcmFrame>.fromIterable([
      CallPcmFrame(pcm: _s16([100]), sampleRateHz: 16000),
    ]),
  );
}

CallAudioChunk _chunk(CallAudioRole role, DateTime at, String who) {
  return CallAudioChunk(
    participantId: who,
    role: role,
    trackId: '$who-audio',
    at: at,
    pcm: Uint8List.fromList(const [1, 0]),
    sampleRateHz: 16000,
  );
}

Uint8List _s16(List<int> samples) {
  final out = Uint8List(samples.length * 2);
  final bd = out.buffer.asByteData();
  for (var i = 0; i < samples.length; i++) {
    bd.setInt16(i * 2, samples[i], Endian.little);
  }
  return out;
}

List<int> _backToS16(Uint8List pcm) {
  final bd = pcm.buffer.asByteData();
  return [
    for (var i = 0; i < pcm.lengthInBytes; i += 2)
      bd.getInt16(i, Endian.little),
  ];
}
