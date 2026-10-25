import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/call_audio_source.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_participant.dart';

void main() {
  test('de huidige binding levert geen hele-call-tap', () {
    final fact = callAudioCaptureOfCurrentBinding();
    expect(fact, unavailableCallAudio);
    expect(fact.wholeCall, isFalse);
    expect(fact.denial, CallAudioDenial.noPerSourceTap);
  });

  test('een track-id en een opname-lampje starten geen opname', () async {
    const track = MeetingTrack(
      id: 'opaque-track',
      kind: MeetingTrackKind.audio,
    );
    const lamp = RecordingIndicatorChanged(active: true);
    // Geen van beide is een argument van de tap. Alleen het capability-feit
    // beslist, en dat feit is hier niet beschikbaar.
    final chunks = await openCallAudioCapture(
      callAudioCaptureOfCurrentBinding(),
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
    expect(await openCallAudioCapture(micOnly).toList(), isEmpty);
  });

  test('een wholeCall-claim zonder tap faalt hard', () {
    const claimed = CallAudioCaptureFact(localOutbound: true, remote: true);
    expect(claimed.wholeCall, isTrue);
    expect(() => openCallAudioCapture(claimed), throwsStateError);
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
