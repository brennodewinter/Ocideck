import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_failure.dart';
import 'package:ocideck/meetings/meeting_link.dart';
import 'package:ocideck/meetings/meeting_models.dart';
import 'package:ocideck/meetings/meeting_registry.dart';
import 'package:ocideck/meetings/meeting_state.dart';
import 'package:ocideck/meetings/providers/fake/fake_meeting_provider.dart';

/// §16.4: het logboek mag fase, code en aantallen dragen — nooit een naam,
/// een link of een identiteit. Elke route naar een logregel loopt langs
/// `diagnosticLabel` of `sanitizeDiagnosticCode`; dit bestand bewaakt beide.
void main() {
  const naam = 'Kim de Groot';
  const link = 'https://meet.example.invalid/j/geheim-token-abc123';

  group('sanitizeDiagnosticCode is de poort, geen opmaak', () {
    test('echte codes komen er ongeschonden doorheen', () {
      expect(sanitizeDiagnosticCode('403'), '403');
      expect(sanitizeDiagnosticCode('CALL_FAILED'), 'CALL_FAILED');
      expect(sanitizeDiagnosticCode('sub.code:12-a'), 'sub.code:12-a');
    });

    test('een zin verliest zijn spaties en zijn lengte', () {
      final result = sanitizeDiagnosticCode(
        'Meeting not found, ask the organiser to invite you again',
      );
      expect(result, isNot(contains(' ')));
      expect(result!.length, lessThanOrEqualTo(maxDiagnosticCodeLength));
    });

    test('eerst filteren, dan afkappen — niet andersom', () {
      // Zou er eerst afgekapt worden, dan bleef er een leesbaar zinsdeel
      // over. Nu blijft er hoogstens een tekenbrij zonder scheiders staan.
      final result = sanitizeDiagnosticCode('${' ' * 40}zichtbaar deel');
      expect(result, isNot(startsWith(' ')));
      expect(result, 'zichtbaardeel');
    });

    test('leeg of alleen rommel wordt null', () {
      expect(sanitizeDiagnosticCode(null), isNull);
      expect(sanitizeDiagnosticCode(''), isNull);
      expect(sanitizeDiagnosticCode('!!! ***'), isNull);
    });
  });

  group('gebeurtenislabels dragen geen inhoud', () {
    test('deelnemersgebeurtenissen noemen geen naam en geen sleutel', () {
      final participant = MeetingParticipant(
        id: 'deelnemer-123',
        displayName: naam,
      );
      for (final label in [
        MeetingParticipantJoined(participant).diagnosticLabel,
        MeetingParticipantUpdated(participant).diagnosticLabel,
        const MeetingParticipantLeft('deelnemer-123').diagnosticLabel,
        const MeetingDominantSpeakerChanged('deelnemer-123').diagnosticLabel,
      ]) {
        expect(label, isNot(contains('Kim')));
        // Ook de ondoorzichtige sleutel niet: die is per sessie stabiel en
        // dus een spoor.
        expect(label, isNot(contains('deelnemer-123')));
      }
    });

    test(
      'een verbreekmelding filtert wat de dienst in het codeveld stopte',
      () {
        final event = MeetingDisconnected(
          code: 'ended: $link',
          subcode: 'user $naam left',
        );
        expect(event.diagnosticLabel, isNot(contains('://')));
        expect(event.diagnosticLabel, isNot(contains(' geheim')));
        expect(event.diagnosticLabel, isNot(contains('Kim ')));
      },
    );

    test('een rolwissel bewaart het aanbiederlabel alleen als code', () {
      final event = MeetingRoleChanged(
        MeetingRole.presenter,
        providerLabel: 'Presenter (given by $naam)',
      );
      // De spaties en haakjes uit het meegestuurde label zijn weg; wat er
      // staat is een aaneengesloten code, geen zin.
      expect(event.diagnosticLabel, startsWith('role(presenter as='));
      expect(event.diagnosticLabel, isNot(contains('given by')));
      expect(event.diagnosticLabel, isNot(contains('(given')));
    });
  });

  group('mislukkingen en toestand', () {
    test('een mislukking draagt soort en code, nooit de melding', () {
      final failure = MeetingFailure(
        MeetingFailureKind.meetingEnded,
        provider: fakeMeetingProviderId,
        code: 'The meeting at $link has ended',
      );
      expect(failure.diagnosticLabel, startsWith('failure(meetingEnded'));
      expect(failure.diagnosticLabel, isNot(contains('://')));
      expect(failure.code, isNot(contains('/')));
    });

    test('de toestand telt deelnemers in plaats van ze te noemen', () {
      var state = MeetingState.idle
          .apply(const MeetingPhaseChanged(MeetingPhase.validating))
          .apply(const MeetingPhaseChanged(MeetingPhase.permissionPrompt))
          .apply(const MeetingPhaseChanged(MeetingPhase.preview))
          .apply(const MeetingPhaseChanged(MeetingPhase.provisioning))
          .apply(const MeetingPhaseChanged(MeetingPhase.connecting))
          .apply(const MeetingPhaseChanged(MeetingPhase.connected));
      state = state.apply(
        MeetingParticipantJoined(
          MeetingParticipant(id: 'a', displayName: naam),
        ),
      );
      expect(state.diagnosticLabel, contains('participants=1'));
      expect(state.diagnosticLabel, isNot(contains('Kim')));
    });

    test('preflight meldt herkomsten als aantal, niet als adres', () async {
      const provider = FakeMeetingProvider();
      final resolution = meetingLinkResolver.resolve(link);
      final match = (resolution as MeetingLinkRecognised).match;
      final preflight = await provider.preflight(match);
      expect(preflight.diagnosticLabel, contains('origins=1'));
      expect(preflight.diagnosticLabel, isNot(contains('geheim')));
      expect(preflight.diagnosticLabel, isNot(contains('://')));
    });
  });
}
