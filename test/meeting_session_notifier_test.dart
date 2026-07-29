import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_failure.dart';
import 'package:ocideck/meetings/meeting_link.dart';
import 'package:ocideck/meetings/meeting_models.dart';
import 'package:ocideck/meetings/meeting_state.dart';
import 'package:ocideck/meetings/providers/fake/fake_meeting_provider.dart';
import 'package:ocideck/state/meeting_session_provider.dart';

/// De sessienotifier: de volgorde van §6.2, de opdrachtenrij van §8.2 en het
/// opruimen van §6.5 — gedreven door de nep-adapter, zonder één byte netwerk.
void main() {
  late ProviderContainer container;
  late MeetingSessionNotifier notifier;

  MeetingState state() => container.read(meetingSessionProvider);

  setUp(() {
    container = ProviderContainer();
    addTearDown(container.dispose);
    notifier = container.read(meetingSessionProvider.notifier);
  });

  /// Doorloop §6.2 tot en met join en geef de nep-sessie terug.
  Future<FakeMeetingSession> join(
    FakeMeetingScenario scenario, {
    String displayName = 'Tester',
  }) async {
    final resolution = notifier.resolveLink(
      'https://$fakeMeetingHost/j/${scenario.name}',
    );
    expect(resolution, isA<MeetingLinkRecognised>());
    notifier.requestDevicePermission();
    notifier.devicesReady();
    await notifier.join(displayName: displayName);
    expect(notifier.session, isNotNull);
    return notifier.session! as FakeMeetingSession;
  }

  /// Laat de gebeurtenissen van de stroom bij de notifier aankomen.
  Future<void> settle() => pumpEventQueue();

  group('herkennen', () {
    test('een afgewezen link is een getypeerde afloop, geen uitzondering', () {
      notifier.resolveLink('geen link');
      expect(state().phase, MeetingPhase.failed);
      expect(state().failure!.kind, MeetingFailureKind.invalidLink);
    });

    test('een onbekende aanbieder heet ook zo', () {
      notifier.resolveLink('https://vreemd.example/vergadering');
      expect(state().phase, MeetingPhase.failed);
      expect(state().failure!.kind, MeetingFailureKind.unknownProvider);
    });

    test('een herkende link laat de fase op validating staan: de volgende '
        'stap is van de gebruiker (§6.2)', () {
      notifier.resolveLink('https://$fakeMeetingHost/j/direct');
      expect(state().phase, MeetingPhase.validating);
      expect(state().failure, isNull);
    });
  });

  group('preflight', () {
    test('zonder herkende link is er niets te vragen', () async {
      expect(await notifier.preflight(), isNull);
    });

    test('met een herkende link komen de feiten van de adapter', () async {
      notifier.resolveLink('https://$fakeMeetingHost/j/lobby');
      final preflight = await notifier.preflight();
      expect(preflight!.lobbyExpected, isTrue);
    });
  });

  group('meedoen', () {
    test('join buiten de volgorde van §6.2 doet niets', () async {
      // Nog niets herkend: geen link, geen sessie.
      await notifier.join(displayName: 'Tester');
      expect(notifier.session, isNull);
      // Herkend maar zonder preview: de fasetabel houdt het tegen.
      notifier.resolveLink('https://$fakeMeetingHost/j/direct');
      await notifier.join(displayName: 'Tester');
      expect(notifier.session, isNull);
      expect(state().phase, MeetingPhase.validating);
    });

    test('de gelukkige reis: herkennen, preview, meedoen, binnen', () async {
      final session = await join(FakeMeetingScenario.direct);
      expect(state().phase, MeetingPhase.provisioning);
      expect(state().provider, fakeMeetingProviderId);
      session.advanceAll();
      await settle();
      expect(state().phase, MeetingPhase.connected);
      expect(state().participantCount, 2);
      expect(state().role, MeetingRole.guest);
    });

    test('wachten op toelating is een fase, geen scherm (T15)', () async {
      final session = await join(FakeMeetingScenario.lobby);
      session.advance(); // connecting
      session.advance(); // lobby
      await settle();
      expect(state().phase, MeetingPhase.lobby);
      expect(state().phase.isConnecting, isTrue);
      session.advanceAll();
      await settle();
      expect(state().phase, MeetingPhase.connected);
    });

    test(
      'geweigerd uit de wachtruimte: failed mét reden, en reset ruimt op',
      () async {
        final session = await join(FakeMeetingScenario.denied);
        session.advanceAll();
        await settle();
        expect(state().phase, MeetingPhase.failed);
        expect(state().failure!.kind, MeetingFailureKind.lobbyDenied);
        // De afloop blijft staan tot de gebruiker hem wegklikt (T13)...
        expect(state().isActive, isTrue);
        // ...en pas reset maakt de weg vrij voor een nieuwe poging.
        notifier.reset();
        expect(state(), same(MeetingState.idle));
        final tweede = notifier.resolveLink(
          'https://$fakeMeetingHost/j/direct',
        );
        expect(tweede, isA<MeetingLinkRecognised>());
      },
    );

    test('herverbinden komt en gaat langs de gebeurtenissen', () async {
      final session = await join(FakeMeetingScenario.reconnect);
      session.advanceAll();
      await settle();
      expect(state().phase, MeetingPhase.connected);
      expect(state().networkQuality, MeetingNetworkQuality.good);
    });

    test('een adapter die zijn stroom sluit zonder afscheid beëindigt het '
        'gesprek netjes', () async {
      final session = await join(FakeMeetingScenario.direct);
      session.advance(); // connecting
      await settle();
      await session.dispose();
      await settle();
      expect(state().phase, MeetingPhase.ended);
    });
  });

  group('de opdrachtenrij (§8.2)', () {
    test(
      'twee snelle klikken vallen samen tot de laatst gewenste stand',
      () async {
        final session = await join(FakeMeetingScenario.direct);
        session.advanceAll();
        await settle();
        expect(state().isMuted, isTrue);

        final observed = <bool>[];
        container.listen(
          meetingSessionProvider.select((s) => s.isMuted),
          (_, next) => observed.add(next),
        );
        // Aan en meteen weer uit, zonder te wachten: één opdracht, met de
        // laatste waarde. De microfoon mag dus nooit even "aan" flitsen.
        final eerste = notifier.setMicrophone(true);
        final tweede = notifier.setMicrophone(false);
        await eerste;
        await tweede;
        await settle();
        expect(state().isMuted, isTrue);
        expect(observed, isNot(contains(false)));
      },
    );

    test('camera en schermdelen lopen door dezelfde rij', () async {
      final session = await join(FakeMeetingScenario.direct);
      session.advanceAll();
      await settle();
      await notifier.setCamera(true);
      await notifier.setScreenShare(true);
      await settle();
      expect(state().isCameraEnabled, isTrue);
      expect(state().isScreenSharing, isTrue);
      await notifier.setScreenShare(false);
      await settle();
      expect(state().isScreenSharing, isFalse);
    });

    test('zonder sessie doet een opdracht niets en breekt er niets', () async {
      await notifier.setMicrophone(true);
      await notifier.setCamera(true);
      await notifier.setScreenShare(true);
      await notifier.submitRecordingConsent(true);
      expect(state(), same(MeetingState.idle));
    });
  });

  group('verlaten (§6.5)', () {
    test('leave is idempotent en ruimt de sessie op', () async {
      final session = await join(FakeMeetingScenario.lobby);
      session.advance(); // connecting
      session.advance(); // lobby
      await settle();
      await notifier.leave();
      await notifier.leave();
      await settle();
      expect(state().phase, MeetingPhase.ended);
      expect(notifier.session, isNull);
      // De uitnodiging is gewist: opnieuw meedoen kan pas na een nieuwe link.
      notifier.reset();
      await notifier.join(displayName: 'Tester');
      expect(notifier.session, isNull);
    });

    test('uitdrukkelijke toestemming gaat langs de sessie (§15)', () async {
      final session = await join(FakeMeetingScenario.direct);
      session.advanceAll();
      await settle();
      await notifier.submitRecordingConsent(true);
      await settle();
      expect(state().explicitConsentRequired, isFalse);
    });
  });
}
