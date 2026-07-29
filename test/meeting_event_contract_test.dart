import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_failure.dart';
import 'package:ocideck/meetings/meeting_models.dart';
import 'package:ocideck/meetings/meeting_state.dart';

/// Het gesloten eventcontract van §8.3: elke gebeurtenis heeft een logregel,
/// landt zonder uitzondering in de reducer, en de boom is dicht — wat hier
/// niet staat, bestaat niet.
void main() {
  /// Eén exemplaar van elk blad van de sealed boom. Wie een gebeurtenis
  /// toevoegt, komt langs deze lijst (de reducer-switch dwingt dat af) en
  /// langs `meeting_log_redaction_test.dart`.
  final specimens = <MeetingEvent>[
    const MeetingPhaseChanged(MeetingPhase.connecting),
    MeetingPhaseChanged(
      MeetingPhase.failed,
      failure: MeetingFailure(MeetingFailureKind.unknown),
    ),
    const MeetingCapabilitiesChanged(MeetingCapabilities.none),
    MeetingRoleChanged(MeetingRole.attendee, providerLabel: 'attendee'),
    const MeetingLocalMuteChanged(isMuted: false),
    const MeetingLocalVideoChanged(isEnabled: true),
    const MeetingScreenShareChanged(isSharing: true),
    MeetingParticipantJoined(
      MeetingParticipant(id: 'a', displayName: 'Deelnemer'),
    ),
    MeetingParticipantUpdated(
      MeetingParticipant(id: 'a', displayName: 'Deelnemer'),
    ),
    const MeetingParticipantLeft('a'),
    const MeetingDominantSpeakerChanged('a'),
    const MeetingDominantSpeakerChanged(null),
    const MeetingRecordingChanged(isActive: true),
    const MeetingTranscriptionChanged(isActive: true),
    const MeetingExplicitConsentChanged(isRequired: true),
    const MeetingNetworkQualityChanged(MeetingNetworkQuality.degraded),
    MeetingDisconnected(code: '480', subcode: '5854'),
  ];

  test('elke gebeurtenis levert zijn eigen logregel', () {
    for (final event in specimens) {
      expect(
        event.diagnosticLabel,
        isNotEmpty,
        reason: '${event.runtimeType} hoort een diagnosticLabel te hebben',
      );
      // De regel begint met een herkenbare, stabiele naam — geen toString
      // van een object. Haakjes zijn er alleen als er iets in staat.
      expect(
        RegExp(r'^[a-z][a-zA-Z]*(\(.*\))?$').hasMatch(event.diagnosticLabel),
        isTrue,
        reason:
            '${event.runtimeType} geeft een onherkenbare logregel: '
            '${event.diagnosticLabel}',
      );
    }
  });

  test('elke gebeurtenis landt zonder uitzondering, in elke fase', () {
    // De reducer mag weigeren (dat is zijn werk), maar nooit gooien: een
    // adapter die te laat of te vroeg is levert niets op, geen crash.
    var connected = MeetingState.idle;
    for (final phase in [
      MeetingPhase.validating,
      MeetingPhase.permissionPrompt,
      MeetingPhase.preview,
      MeetingPhase.provisioning,
      MeetingPhase.connecting,
      MeetingPhase.connected,
    ]) {
      connected = connected.apply(MeetingPhaseChanged(phase));
    }
    final ended = connected.apply(
      const MeetingPhaseChanged(MeetingPhase.ended),
    );
    for (final state in [MeetingState.idle, connected, ended]) {
      for (final event in specimens) {
        expect(() => state.apply(event), returnsNormally);
      }
    }
  });

  test('een mislukte fase en zijn reden reizen samen', () {
    // Twee losse gebeurtenissen zouden een tussenmoment scheppen waarin de
    // schil "mislukt" toont zonder te weten waarom; daarom draagt de
    // fasegebeurtenis de reden zelf.
    final event = MeetingPhaseChanged(
      MeetingPhase.failed,
      failure: MeetingFailure(MeetingFailureKind.serviceUnavailable),
    );
    expect(event.diagnosticLabel, contains('phase(failed)'));
    expect(event.diagnosticLabel, contains('serviceUnavailable'));
  });
}
