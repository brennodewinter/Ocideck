import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_failure.dart';
import 'package:ocideck/meetings/meeting_models.dart';
import 'package:ocideck/meetings/meeting_state.dart';

/// De reducer van `meeting_state.dart`: elke overgang toetsbaar zonder
/// adapter, zonder netwerk en zonder widgetboom (TEAMS_GUEST_CLIENT.md §8.1).
void main() {
  MeetingState at(MeetingPhase phase) {
    var state = MeetingState.idle;
    const route = {
      MeetingPhase.idle: <MeetingPhase>[],
      MeetingPhase.validating: [MeetingPhase.validating],
      MeetingPhase.connected: [
        MeetingPhase.validating,
        MeetingPhase.permissionPrompt,
        MeetingPhase.preview,
        MeetingPhase.provisioning,
        MeetingPhase.connecting,
        MeetingPhase.connected,
      ],
      MeetingPhase.lobby: [
        MeetingPhase.validating,
        MeetingPhase.permissionPrompt,
        MeetingPhase.preview,
        MeetingPhase.provisioning,
        MeetingPhase.connecting,
        MeetingPhase.lobby,
      ],
    };
    for (final step in route[phase]!) {
      state = state.apply(MeetingPhaseChanged(step));
    }
    expect(state.phase, phase, reason: 'route naar $phase hoort te kloppen');
    return state;
  }

  group('de fasetabel', () {
    test('het diagram van §8.1 is de tabel, stap voor stap', () {
      // De volledige geslaagde reis, plus de wachtruimte.
      expect(
        MeetingPhase.idle.canTransitionTo(MeetingPhase.validating),
        isTrue,
      );
      expect(
        MeetingPhase.connecting.canTransitionTo(MeetingPhase.lobby),
        isTrue,
      );
      expect(
        MeetingPhase.connecting.canTransitionTo(MeetingPhase.connected),
        isTrue,
      );
      expect(
        MeetingPhase.lobby.canTransitionTo(MeetingPhase.connected),
        isTrue,
      );
      expect(
        MeetingPhase.connected.canTransitionTo(MeetingPhase.reconnecting),
        isTrue,
      );
      expect(
        MeetingPhase.reconnecting.canTransitionTo(MeetingPhase.connected),
        isTrue,
      );
    });

    test('wat het ontwerp uitsluit, staat er ook echt niet in', () {
      expect(MeetingPhase.lobby.canTransitionTo(MeetingPhase.preview), isFalse);
      expect(
        MeetingPhase.connected.canTransitionTo(MeetingPhase.connecting),
        isFalse,
      );
      expect(
        MeetingPhase.idle.canTransitionTo(MeetingPhase.connected),
        isFalse,
      );
      expect(MeetingPhase.ended.canTransitionTo(MeetingPhase.failed), isFalse);
    });

    test('uit elke levende fase is verlaten bereikbaar (§17)', () {
      for (final phase in MeetingPhase.values) {
        if (phase == MeetingPhase.idle ||
            phase == MeetingPhase.leaving ||
            phase == MeetingPhase.ended ||
            phase == MeetingPhase.failed) {
          continue;
        }
        expect(
          phase.canTransitionTo(MeetingPhase.leaving),
          isTrue,
          reason: 'vanuit $phase moet verlaten kunnen',
        );
      }
    });

    test('terminale fasen gaan alleen terug naar idle — de reset', () {
      expect(meetingPhaseTransitions[MeetingPhase.ended], {MeetingPhase.idle});
      expect(meetingPhaseTransitions[MeetingPhase.failed], {MeetingPhase.idle});
    });

    test('blijven staan mag altijd; de poort en het lampje kloppen', () {
      for (final phase in MeetingPhase.values) {
        expect(phase.canTransitionTo(phase), isTrue);
      }
      expect(MeetingPhase.idle.isSessionActive, isFalse);
      // Ook een afgelopen of mislukt gesprek telt als actief: de gebruiker
      // moet de afloop nog kunnen lezen (T13).
      expect(MeetingPhase.failed.isSessionActive, isTrue);
      expect(MeetingPhase.ended.isSessionActive, isTrue);
      expect(MeetingPhase.lobby.isConnecting, isTrue);
      expect(MeetingPhase.reconnecting.isConnecting, isTrue);
      expect(MeetingPhase.connected.isConnecting, isFalse);
    });
  });

  group('de reducer weigert wat niet gebeurd kan zijn', () {
    test('een verboden fase-overgang wordt genegeerd, niet uitgevoerd', () {
      final state = MeetingState.idle.apply(
        const MeetingPhaseChanged(MeetingPhase.connected),
      );
      expect(state.phase, MeetingPhase.idle);
    });

    test('gebeurtenissen na het einde veranderen niets meer', () {
      var state = at(MeetingPhase.connected);
      state = state.apply(const MeetingPhaseChanged(MeetingPhase.ended));
      final after = state
          .apply(const MeetingLocalMuteChanged(isMuted: false))
          .apply(MeetingParticipantJoined(_participant('spook')))
          .apply(const MeetingRecordingChanged(isActive: true));
      expect(after.isMuted, isTrue);
      expect(after.participants, isEmpty);
      expect(after.isRecordingActive, isFalse);
    });

    test('gebeurtenissen vóór het begin landen ook niet', () {
      final state = MeetingState.idle.apply(
        const MeetingLocalVideoChanged(isEnabled: true),
      );
      expect(state.isCameraEnabled, isFalse);
    });
  });

  group('mislukking en afloop', () {
    test('failed draagt zijn reden mee in dezelfde gebeurtenis', () {
      final state = at(MeetingPhase.lobby).apply(
        MeetingPhaseChanged(
          MeetingPhase.failed,
          failure: MeetingFailure(MeetingFailureKind.lobbyDenied),
        ),
      );
      expect(state.phase, MeetingPhase.failed);
      expect(state.failure!.kind, MeetingFailureKind.lobbyDenied);
    });

    test('een fase die doorgaat wist een oude reden', () {
      var state = at(MeetingPhase.validating);
      state = state.apply(
        MeetingPhaseChanged(
          MeetingPhase.permissionPrompt,
          failure: MeetingFailure(MeetingFailureKind.unknown),
        ),
      );
      // De gebeurtenis droeg er ten onrechte een mee; hij blijft staan.
      expect(state.failure, isNotNull);
      state = state.apply(const MeetingPhaseChanged(MeetingPhase.preview));
      expect(state.failure, isNull);
    });

    test('het einde wist deelnemers en rechten, maar niet de reden (§6.5)', () {
      var state = at(MeetingPhase.connected)
          .apply(
            const MeetingCapabilitiesChanged(
              MeetingCapabilities(canUseMicrophone: true),
            ),
          )
          .apply(MeetingParticipantJoined(_participant('a')))
          .apply(MeetingDisconnected(code: '5854'));
      state = state.apply(
        MeetingPhaseChanged(
          MeetingPhase.failed,
          failure: MeetingFailure(MeetingFailureKind.meetingEnded),
        ),
      );
      expect(state.participants, isEmpty);
      expect(state.capabilities, MeetingCapabilities.none);
      expect(state.failure!.kind, MeetingFailureKind.meetingEnded);
      expect(state.disconnectCode, '5854');
    });

    test('reset is de enige weg terug naar niets', () {
      final ended = at(
        MeetingPhase.connected,
      ).apply(const MeetingPhaseChanged(MeetingPhase.ended));
      expect(ended.isActive, isTrue);
      expect(ended.reset(), same(MeetingState.idle));
    });
  });

  group('deelnemers', () {
    test('toevoegen, bijwerken en weggaan, op sleutel en nooit op naam', () {
      var state = at(MeetingPhase.connected)
          .apply(MeetingParticipantJoined(_participant('a', name: 'Kim')))
          .apply(MeetingParticipantJoined(_participant('b', name: 'Kim')));
      expect(state.participantCount, 2);

      // Een dubbele joined-melding overschrijft in plaats van te dupliceren.
      state = state.apply(
        MeetingParticipantJoined(_participant('a', name: 'Kim B.')),
      );
      expect(state.participantCount, 2);
      expect(state.participants.first.displayName, 'Kim B.');

      // Bijwerken van een onbekende sleutel doet niets.
      state = state.apply(
        MeetingParticipantUpdated(_participant('c', name: 'Spook')),
      );
      expect(state.participantCount, 2);

      state = state.apply(const MeetingParticipantLeft('a'));
      expect(state.participants.map((p) => p.id), ['b']);
    });

    test('wie weggaat is niet langer aan het woord', () {
      var state = at(MeetingPhase.connected)
          .apply(MeetingParticipantJoined(_participant('a')))
          .apply(const MeetingDominantSpeakerChanged('a'));
      expect(state.dominantSpeakerId, 'a');
      state = state.apply(const MeetingParticipantLeft('a'));
      expect(state.dominantSpeakerId, isNull);
    });
  });

  group('losse schakelaars en de weergavenaam-grens', () {
    test('elke melding landt op zijn eigen veld', () {
      final state = at(MeetingPhase.connected)
          .apply(const MeetingLocalMuteChanged(isMuted: false))
          .apply(const MeetingLocalVideoChanged(isEnabled: true))
          .apply(const MeetingScreenShareChanged(isSharing: true))
          .apply(const MeetingRecordingChanged(isActive: true))
          .apply(const MeetingTranscriptionChanged(isActive: true))
          .apply(const MeetingExplicitConsentChanged(isRequired: true))
          .apply(
            const MeetingNetworkQualityChanged(MeetingNetworkQuality.degraded),
          )
          .apply(MeetingRoleChanged(MeetingRole.presenter, providerLabel: 'p'));
      expect(state.isMuted, isFalse);
      expect(state.isCameraEnabled, isTrue);
      expect(state.isScreenSharing, isTrue);
      expect(state.isRecordingActive, isTrue);
      expect(state.isTranscriptionActive, isTrue);
      expect(state.explicitConsentRequired, isTrue);
      expect(state.networkQuality, MeetingNetworkQuality.degraded);
      expect(state.role, MeetingRole.presenter);
      expect(state.providerRoleLabel, 'p');
    });

    test(
      'een vijandige weergavenaam wordt gesnoeid vóór hij de toestand raakt',
      () {
        final nasty = 'A\u202Edrent\nB${'x' * 200}';
        final participant = MeetingParticipant(id: 'a', displayName: nasty);
        expect(participant.displayName.contains('\u202E'), isFalse);
        expect(participant.displayName.contains('\n'), isFalse);
        expect(
          participant.displayName.length,
          lessThanOrEqualTo(maxDisplayNameLength),
        );
        // En hetzelfde geldt aan de uitgaande kant: zie MeetingJoinRequest in
        // fake_meeting_provider_test.dart.
        expect(sanitizeDisplayName('  Kim   de   Groot  '), 'Kim de Groot');
        expect(sanitizeDisplayName('\u200B\u200B'), isEmpty);
      },
    );
  });

  group('rechten', () {
    test('verlaten is geen gunst van de aanbieder', () {
      expect(MeetingCapabilities.none.allows(MeetingControl.leave), isTrue);
      expect(
        MeetingCapabilities.none.allows(MeetingControl.microphone),
        isFalse,
      );
      const alles = MeetingCapabilities(
        canUseMicrophone: true,
        canUseCamera: true,
        canShareScreen: true,
        canSeeRoster: true,
      );
      for (final control in MeetingControl.values) {
        expect(alles.allows(control), isTrue);
      }
      expect(alles.copyWith(canShareScreen: false).canShareScreen, isFalse);
      expect(alles.copyWith(), alles);
    });
  });
}

MeetingParticipant _participant(String id, {String name = 'Deelnemer'}) =>
    MeetingParticipant(id: id, displayName: name);
