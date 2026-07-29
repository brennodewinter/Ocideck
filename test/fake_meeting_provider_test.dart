import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_failure.dart';
import 'package:ocideck/meetings/meeting_link.dart';
import 'package:ocideck/meetings/meeting_models.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/meetings/meeting_registry.dart';
import 'package:ocideck/meetings/meeting_state.dart';
import 'package:ocideck/meetings/providers/fake/fake_meeting_provider.dart';

/// De nep-adapter doorloopt elk verloop deterministisch, en zijn draaiboeken
/// houden zich aan de fasetabel — wat de reducer weigert, krijgt een echte
/// adapter straks ook fout (`COLLABORATION.md` §7.1.5 stap 1).
void main() {
  const provider = FakeMeetingProvider();

  MeetingLinkMatch matchFor(FakeMeetingScenario scenario) {
    final resolution = meetingLinkResolver.resolve(
      'https://$fakeMeetingHost/j/${scenario.name}',
    );
    return (resolution as MeetingLinkRecognised).match;
  }

  Future<FakeMeetingSession> joined(
    FakeMeetingScenario scenario, {
    String displayName = 'Tester',
  }) async {
    final session = await provider.join(
      MeetingJoinRequest(link: matchFor(scenario), displayName: displayName),
    );
    return session as FakeMeetingSession;
  }

  group('herkenning', () {
    test('alleen /j/<verloop> is een uitnodiging', () {
      expect(provider.match(Uri.parse('https://$fakeMeetingHost/')), isNull);
      expect(
        provider.match(Uri.parse('https://$fakeMeetingHost/hulp/pagina')),
        isNull,
      );
      final match = provider.match(
        Uri.parse('https://$fakeMeetingHost/j/lobby'),
      );
      expect(match, isNotNull);
      expect(match!.provider, fakeMeetingProviderId);
      expect(match.meetingKind, 'lobby');
    });

    test('een onbekend verloop wordt direct', () {
      expect(
        FakeMeetingScenario.fromPathSegment('bestaatniet'),
        FakeMeetingScenario.direct,
      );
    });

    test(
      'het register kent hem alleen als debug-adapter, nooit als aanbod',
      () {
        // Onder flutter test draait de debugbouw, dus hij is er.
        expect(
          meetingProviders.map((p) => p.id),
          contains(fakeMeetingProviderId),
        );
        // Maar aangeboden wordt een spike-adapter niet (§7.1.4).
        expect(
          offerableMeetingProviders.map((p) => p.id),
          isNot(contains(fakeMeetingProviderId)),
        );
        expect(provider.release, MeetingProviderRelease.spike);
        expect(meetingProviderById(fakeMeetingProviderId), isNotNull);
        expect(
          meetingProviderById(const MeetingProviderId('bestaatniet')),
          isNull,
        );
      },
    );
  });

  group('preflight', () {
    test(
      'meldt de wachtruimte vooraf, zodat wachten geen storing lijkt (T15)',
      () async {
        final lobby = await provider.preflight(
          matchFor(FakeMeetingScenario.lobby),
        );
        expect(lobby.lobbyExpected, isTrue);
        expect(lobby.canJoin, isTrue);
        final direct = await provider.preflight(
          matchFor(FakeMeetingScenario.direct),
        );
        expect(direct.lobbyExpected, isFalse);
        // Eerlijk over versleuteling: onbekend is het antwoord (T9).
        expect(direct.encryption, MeetingEncryptionClaim.unknown);
        expect(
          direct.egressOrigins.single.toString(),
          'https://$fakeMeetingHost',
        );
      },
    );

    test(
      'gasten geweigerd is een preflight-feit, geen verrassing achteraf',
      () async {
        final preflight = await provider.preflight(
          matchFor(FakeMeetingScenario.guestDisabled),
        );
        expect(
          preflight.failure!.kind,
          MeetingFailureKind.anonymousJoinDisabled,
        );
        expect(preflight.canJoin, isFalse);
      },
    );
  });

  group('de draaiboeken, afgespeeld door de reducer', () {
    /// Speel [scenario] af en geef elke tussenstand terug. Dat de reducer geen
    /// enkele stap weigert, ís de toets: het draaiboek houdt zich aan §8.1.
    Future<List<MeetingState>> play(FakeMeetingScenario scenario) async {
      final session = await joined(scenario);
      var state = MeetingState.idle
          .apply(const MeetingPhaseChanged(MeetingPhase.validating))
          .apply(const MeetingPhaseChanged(MeetingPhase.permissionPrompt))
          .apply(const MeetingPhaseChanged(MeetingPhase.preview))
          .apply(const MeetingPhaseChanged(MeetingPhase.provisioning));
      final states = <MeetingState>[];
      session.events.listen((event) {
        final next = state.apply(event);
        expect(
          identical(next, state) &&
              event is MeetingPhaseChanged &&
              event.phase != state.phase,
          isFalse,
          reason:
              'de reducer weigerde ${event.diagnosticLabel} in fase '
              '${state.phase.name} — het draaiboek van $scenario overtreedt '
              'de fasetabel',
        );
        state = next;
        states.add(next);
      });
      session.advanceAll();
      await session.dispose();
      await pumpEventQueue();
      return states;
    }

    test('direct: meteen binnen, met rechten, rol en deelnemers', () async {
      final states = await play(FakeMeetingScenario.direct);
      final last = states.last;
      expect(last.phase, MeetingPhase.connected);
      expect(last.capabilities.canShareScreen, isTrue);
      expect(last.role, MeetingRole.guest);
      expect(last.participantCount, 2);
      expect(last.participants.where((p) => p.isSelf).length, 1);
      expect(last.networkQuality, MeetingNetworkQuality.good);
    });

    test('lobby: eerst wachten op toelating, dan binnen', () async {
      final states = await play(FakeMeetingScenario.lobby);
      expect(
        states.map((s) => s.phase),
        containsAllInOrder([
          MeetingPhase.connecting,
          MeetingPhase.lobby,
          MeetingPhase.connected,
        ]),
      );
    });

    test('geweigerd: de wachtruimte eindigt in failed mét reden', () async {
      final states = await play(FakeMeetingScenario.denied);
      final last = states.last;
      expect(last.phase, MeetingPhase.failed);
      expect(last.failure!.kind, MeetingFailureKind.lobbyDenied);
      expect(last.failure!.provider, fakeMeetingProviderId);
      // En de wachtruimte is er wél geweest.
      expect(states.map((s) => s.phase), contains(MeetingPhase.lobby));
    });

    test('herverbinden: weggevallen en teruggekomen, zonder einde', () async {
      final states = await play(FakeMeetingScenario.reconnect);
      expect(
        states.map((s) => s.phase),
        containsAllInOrder([
          MeetingPhase.connected,
          MeetingPhase.reconnecting,
          MeetingPhase.connected,
        ]),
      );
      expect(states.last.networkQuality, MeetingNetworkQuality.good);
    });

    test(
      'beëindigd door de organisator: opname gemeld, code bewaard',
      () async {
        final states = await play(FakeMeetingScenario.endedByHost);
        final last = states.last;
        expect(last.phase, MeetingPhase.ended);
        expect(last.disconnectCode, '5854');
        // De opname is onderweg gemeld; aan het einde is die stand gewist.
        expect(states.any((s) => s.isRecordingActive), isTrue);
        expect(last.isRecordingActive, isFalse);
        expect(last.participants, isEmpty);
      },
    );

    test('gasten geweigerd: verbinding gezocht, getypeerd gefaald', () async {
      final states = await play(FakeMeetingScenario.guestDisabled);
      expect(states.last.phase, MeetingPhase.failed);
      expect(
        states.last.failure!.kind,
        MeetingFailureKind.anonymousJoinDisabled,
      );
      expect(states.last.failure!.code, '403');
    });
  });

  group('de sessie als contract', () {
    test(
      'rechten vóór knoppen: zonder toezegging gebeurt er niets (T12)',
      () async {
        final session = await joined(FakeMeetingScenario.direct);
        final received = <MeetingEvent>[];
        session.events.listen(received.add);
        // Nog geen stap gedaan: geen rechten, dus geen gebeurtenis.
        await session.setMicrophone(true);
        await session.setCamera(true);
        await session.startScreenShare();
        await pumpEventQueue();
        expect(received, isEmpty);
        // Na het draaiboek zijn de rechten er en werken de knoppen wél.
        session.advanceAll();
        await session.setMicrophone(true);
        await pumpEventQueue();
        expect(received.whereType<MeetingLocalMuteChanged>().length, 1);
        expect(session.capabilities.canUseMicrophone, isTrue);
        expect(session.role, MeetingRole.guest);
        await session.dispose();
      },
    );

    test('leave maakt het draaiboek af en speelt de rest niet meer', () async {
      final session = await joined(FakeMeetingScenario.lobby);
      final phases = <MeetingPhase>[];
      session.events.listen((event) {
        if (event is MeetingPhaseChanged) phases.add(event.phase);
      });
      session.advance(); // connecting
      session.advance(); // lobby
      expect(session.pendingSteps, greaterThan(0));
      await session.leave();
      expect(session.pendingSteps, 0);
      // Nog eens weggaan doet niets meer: idempotent (§6.5).
      await session.leave();
      expect(session.advance(), isFalse);
      await pumpEventQueue();
      expect(phases, [
        MeetingPhase.connecting,
        MeetingPhase.lobby,
        MeetingPhase.leaving,
        MeetingPhase.ended,
      ]);
      await session.dispose();
      await session.dispose();
    });

    test('de weergavenaam wordt aan de uitgaande kant gesnoeid', () async {
      final session = await joined(
        FakeMeetingScenario.direct,
        displayName: 'Kim\u202E\nde Groot${'!' * 100}',
      );
      MeetingParticipant? self;
      session.events.listen((event) {
        if (event is MeetingParticipantJoined && event.participant.isSelf) {
          self = event.participant;
        }
      });
      session.advanceAll();
      await pumpEventQueue();
      expect(self, isNotNull);
      expect(self!.displayName.contains('\u202E'), isFalse);
      expect(self!.displayName.contains('\n'), isFalse);
      expect(self!.displayName.length, lessThanOrEqualTo(maxDisplayNameLength));
      await session.dispose();
    });
  });
}
