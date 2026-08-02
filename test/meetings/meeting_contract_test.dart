// Exercises the backend-neutral meeting contract (`docs/design/NATIVE_CALLS.md`
// §1, §3) through the F1 fake adapter. The point of these tests is the invariant
// that the UI-facing surface — recognition, preflight facts, the roster, the
// event stream and the intent methods — behaves the same regardless of backend:
// the fake stands in for a real Jitsi/MatrixRTC session, and the same assertions
// will hold against those adapters later.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';

import 'fakes/fake_meeting_provider.dart';

void main() {
  group('recognition and preflight', () {
    const provider = FakeMeetingProvider();

    test('match recognises its own host and rejects others (no network)', () {
      expect(
        provider.match(Uri.parse('https://fake.local/room-1'))?.providerId,
        'fake',
      );
      expect(provider.match(Uri.parse('https://example.com/room-1')), isNull);
    });

    test(
      'preflight returns typed facts, and never inherits an E2EE claim',
      () async {
        final match = provider.match(Uri.parse('https://fake.local/r'))!;
        final pre = await provider.preflight(match);
        expect(pre.support, MeetingSupport.nativeClient);
        expect(pre.capabilities.audio, isTrue);
        expect(pre.capabilities.roster, isTrue);
        expect(pre.e2ee, MeetingE2eeStatus.unknown);
        expect(pre.identityLabel, 'guest');
        expect(pre.egressOrigins, contains('fake.local'));
        expect(pre.canJoin, isTrue);
      },
    );

    test('an unsupported/refused preflight cannot join', () {
      const pre = MeetingPreflight(
        support: MeetingSupport.unsupported,
        capabilities: MeetingCapabilities(),
        e2ee: MeetingE2eeStatus.unknown,
        failureReason: MeetingFailureReason.meetingTypeUnsupported,
      );
      expect(pre.canJoin, isFalse);
    });
  });

  group('a session drives the backend-agnostic surface', () {
    late FakeMeetingSession session;
    late List<MeetingEvent> events;
    late StreamSubscription<MeetingEvent> sub;

    setUp(() async {
      const provider = FakeMeetingProvider();
      final match = provider.match(Uri.parse('https://fake.local/r'))!;
      final joined = await provider.join(
        MeetingJoinRequest(link: match, displayName: 'Me'),
      );
      session = joined as FakeMeetingSession;
      events = <MeetingEvent>[];
      sub = session.events.listen(events.add);
    });

    tearDown(() async {
      await sub.cancel();
    });

    test(
      'starts connected with only the local participant, muted by default',
      () {
        expect(session.providerId, 'fake');
        expect(session.connectionState, MeetingConnectionState.connected);
        expect(session.participants.map((p) => p.id), ['local']);
        expect(session.localRole, MeetingRole.guest);
        final local = session.participants.single;
        expect(local.isLocal, isTrue);
        expect(local.micMuted, isTrue);
        expect(local.camOff, isTrue);
      },
    );

    test(
      'mic/camera/screen-share mutate the local tile and emit updates',
      () async {
        await session.setMicrophone(enabled: true);
        await session.setCamera(enabled: true);
        await session.startScreenShare();
        await session.stopScreenShare();
        await pumpEventQueue();

        final local = session.participants.firstWhere((p) => p.isLocal);
        expect(local.micMuted, isFalse);
        expect(local.camOff, isFalse);
        expect(local.isScreenShare, isFalse);
        expect(events.whereType<ParticipantUpdated>().length, 4);
      },
    );

    test(
      'remote join/leave and chat flow through the roster and events',
      () async {
        session.addRemoteParticipant(
          const MeetingParticipant(
            id: 'r1',
            displayName: 'Ada',
            role: MeetingRole.attendee,
            video: MeetingTrack(id: 't-r1-v', kind: MeetingTrackKind.video),
          ),
        );
        session.pushRemoteChat('r1', 'hello');
        await session.sendChat('hi');
        await pumpEventQueue();

        expect(
          session.participants.map((p) => p.id),
          containsAll(['local', 'r1']),
        );
        expect(
          events.whereType<ParticipantJoined>().single.participant.id,
          'r1',
        );
        final chats = events.whereType<ChatReceived>().toList();
        expect(chats.map((c) => c.participantId), ['r1', 'local']);

        session.removeRemoteParticipant('r1');
        await pumpEventQueue();
        expect(session.participants.map((p) => p.id), ['local']);
        expect(events.whereType<ParticipantLeft>().single.participantId, 'r1');
      },
    );

    test(
      'role, capabilities, connection, recording and error changes surface',
      () async {
        session.setLocalRole(MeetingRole.presenter);
        session.setCapabilities(const MeetingCapabilities(audio: true));
        session.setConnectionState(MeetingConnectionState.reconnecting);
        session.setRecording(active: true);
        session.pushError('brief blip');
        await pumpEventQueue();

        expect(session.localRole, MeetingRole.presenter);
        expect(session.capabilities.audio, isTrue);
        expect(session.capabilities.video, isFalse);
        expect(session.connectionState, MeetingConnectionState.reconnecting);
        expect(
          events.whereType<CapabilitiesChanged>().single.capabilities.audio,
          isTrue,
        );
        expect(
          events.whereType<RecordingIndicatorChanged>().single.active,
          isTrue,
        );
        expect(
          events.whereType<MeetingErrorEvent>().single.message,
          'brief blip',
        );
      },
    );

    test('leave disconnects and closes the event stream', () async {
      var done = false;
      final watcher = session.events.listen(null, onDone: () => done = true);
      await session.leave();
      await pumpEventQueue();

      expect(session.connectionState, MeetingConnectionState.disconnected);
      expect(
        events.whereType<ConnectionStateChanged>().last.state,
        MeetingConnectionState.disconnected,
      );
      expect(done, isTrue);
      await watcher.cancel();
    });
  });

  group('the sealed event hierarchy is exhaustive', () {
    // The compiler forces this switch to cover every MeetingEvent; the test also
    // exercises every event type's constructor. Adding an event without a case
    // here is a compile error, not a silent gap.
    String label(MeetingEvent event) => switch (event) {
      ParticipantJoined() => 'joined',
      ParticipantLeft() => 'left',
      ParticipantUpdated() => 'updated',
      ConnectionStateChanged() => 'connection',
      CapabilitiesChanged() => 'capabilities',
      ChatReceived() => 'chat',
      RecordingIndicatorChanged() => 'recording',
      MeetingErrorEvent() => 'error',
    };

    test('every event maps to a distinct label', () {
      const local = MeetingParticipant(
        id: 'local',
        displayName: 'Me',
        role: MeetingRole.guest,
      );
      final all = <MeetingEvent>[
        const ParticipantJoined(local),
        const ParticipantLeft('r1'),
        ParticipantUpdated(local.copyWith(micMuted: true)),
        const ConnectionStateChanged(MeetingConnectionState.connecting),
        const CapabilitiesChanged(MeetingCapabilities(chat: true)),
        const ChatReceived(participantId: 'r1', text: 'hi'),
        const RecordingIndicatorChanged(active: true),
        const MeetingErrorEvent(message: 'boom', terminal: true),
      ];
      expect(all.map(label).toSet().length, all.length);
    });
  });
}
