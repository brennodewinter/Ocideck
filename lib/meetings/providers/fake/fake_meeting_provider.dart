// De nep-adapter: elke fase van een vergadering, zonder één byte netwerk
// (`COLLABORATION.md` §7.1.5 stap 1).
//
// Waarom dit in `lib/` staat en niet in `test/`. Het is niet alleen een
// testdubbel maar het bewijs dat het contract van §7.1.1 klopt: als een
// vergadering te doorlopen valt met een adapter die niets kan, dan bevat het
// contract alles wat de schil nodig heeft en niets wat alleen ACS kan leveren.
// De eerste échte adapter erft dat bewijs.
//
// **Hij komt de deur niet uit.** `meeting_registry.dart` zet hem alleen in het
// register onder `kDebugMode`; die constante is bij het bouwen bekend, dus in
// een uitgebrachte app valt hij eruit. Een gebruiker kan hier geen vergadering
// mee "voeren" die niet bestaat.
//
// **Deterministisch betekent hier: geen klok.** De sessie stuurt niets uit
// zichzelf. Elke stap komt van [FakeMeetingSession.advance], zodat een test de
// volgorde bepaalt in plaats van eromheen te wachten. Een tijdgestuurde variant
// voor het demonstreren van de schil hoort bij de PR die die schil bouwt; hier
// zou hij alleen wisselvallige tests opleveren.
import 'dart:async';

import '../../meeting_event.dart';
import '../../meeting_failure.dart';
import '../../meeting_link.dart';
import '../../meeting_models.dart';
import '../../meeting_provider.dart';

/// De sleutel van de nep-adapter.
const MeetingProviderId fakeMeetingProviderId = MeetingProviderId('fake');

/// De host die de nep-adapter herkent.
///
/// `.invalid` is door RFC 2606 gereserveerd en lost nergens ter wereld op. Een
/// echt ogende host zou vroeg of laat in een test of een schermafdruk als
/// werkend adres gelezen worden.
const String fakeMeetingHost = 'meet.example.invalid';

/// Welk verloop de nep-adapter naspeelt.
///
/// Dit zijn geen willekeurige gevallen: het zijn de afloopen waar §19.5 een
/// echte dienst voor wil zien, en die de schil dus alle vijf moet kunnen tonen.
enum FakeMeetingScenario {
  /// Meteen binnen.
  direct,

  /// Eerst wachten op toelating, dan binnen.
  lobby,

  /// Wachten, en dan door de organisator geweigerd.
  denied,

  /// Binnen, verbinding valt weg, verbinding komt terug.
  reconnect,

  /// Binnen, en dan beëindigt de organisator de vergadering.
  endedByHost,

  /// De organisatie laat gasten zonder account niet toe.
  guestDisabled;

  /// Het pad achter `/j/` in de uitnodiging kiest het verloop; onbekend of
  /// afwezig wordt [direct].
  static FakeMeetingScenario fromPathSegment(String segment) {
    for (final scenario in FakeMeetingScenario.values) {
      if (scenario.name == segment) return scenario;
    }
    return FakeMeetingScenario.direct;
  }
}

/// Een adapter die elke fase kan doorlopen en niets aanraakt.
class FakeMeetingProvider implements MeetingProvider {
  const FakeMeetingProvider();

  @override
  MeetingProviderId get id => fakeMeetingProviderId;

  /// `spike`, en dat is geen bescheidenheid: §7.1.4 laat de schil een adapter
  /// beneden `experimental` niet als deelnamemogelijkheid aanbieden. Zo staat
  /// de nep-adapter ook op zijn eigen vrijgavelijn achter een deur.
  @override
  MeetingProviderRelease get release => MeetingProviderRelease.spike;

  @override
  Set<String> get trustedHosts => const {fakeMeetingHost};

  @override
  MeetingLinkMatch? match(Uri invitation) {
    final segments = invitation.pathSegments;
    // Alleen `/j/<verloop>` is een uitnodiging. Al het andere op deze host is
    // een gewone pagina — precies het onderscheid dat §12.1 van een echte
    // adapter vraagt, en dat een test hier zonder dienst kan naspelen.
    if (segments.length != 2 || segments.first != 'j') return null;
    return MeetingLinkMatch(
      provider: id,
      invitation: invitation,
      meetingKind: FakeMeetingScenario.fromPathSegment(segments[1]).name,
    );
  }

  @override
  Future<MeetingPreflight> preflight(MeetingLinkMatch link) async {
    final scenario = _scenarioOf(link);
    return MeetingPreflight(
      provider: id,
      support: MeetingSupportLevel.nativeClient,
      identity: MeetingIdentityKind.anonymousDisplayName,
      // Een nep-adapter weet niets over versleuteling, en dat is precies het
      // eerlijke antwoord dat T9 verlangt.
      encryption: MeetingEncryptionClaim.unknown,
      capabilities: _fullCapabilities,
      lobbyExpected:
          scenario == FakeMeetingScenario.lobby ||
          scenario == FakeMeetingScenario.denied,
      egressOrigins: [Uri.parse('https://$fakeMeetingHost')],
      failure: scenario == FakeMeetingScenario.guestDisabled
          ? MeetingFailure(
              MeetingFailureKind.anonymousJoinDisabled,
              provider: id,
              code: '403',
            )
          : null,
    );
  }

  @override
  Future<MeetingSession> join(MeetingJoinRequest request) async =>
      FakeMeetingSession(_scenarioOf(request.link), request.displayName);

  FakeMeetingScenario _scenarioOf(MeetingLinkMatch link) {
    final segments = link.invitation.pathSegments;
    return segments.length == 2
        ? FakeMeetingScenario.fromPathSegment(segments[1])
        : FakeMeetingScenario.direct;
  }
}

/// Alles mag. De nep-adapter kent geen beleid, dus hij hoort er ook geen te
/// verzinnen.
const MeetingCapabilities _fullCapabilities = MeetingCapabilities(
  canUseMicrophone: true,
  canUseCamera: true,
  canShareScreen: true,
  canSeeRoster: true,
);

/// De sleutel van de gebruiker zelf in de deelnemerslijst van de nep-adapter.
const String fakeSelfParticipantId = 'fake-self';

/// De sleutel van de tegenspeler die in elk geslaagd verloop meedoet.
const String fakeHostParticipantId = 'fake-host';

/// De naam van die tegenspeler.
///
/// Een const en niet een literal op de plek zelf. Een deelnemersnaam is
/// gegevens en geen interfacetekst — bij een echte adapter komt hij van de
/// dienst — maar de poort voor hardgecodeerde tekst kan dat verschil niet zien
/// zodra de schil zo'n naam in een `Text` zet. Eén benoemde plek met deze
/// uitleg is beter dan een literal die later stil een overtreding wordt.
const String fakeHostDisplayName = 'Organisator';

/// Een gesprek dat stap voor stap gestuurd wordt.
class FakeMeetingSession implements MeetingSession {
  FakeMeetingSession(this.scenario, String displayName)
    : _displayName = sanitizeDisplayName(displayName) {
    _pending.addAll(_scriptFor(scenario, _displayName));
  }

  final FakeMeetingScenario scenario;
  final String _displayName;

  final StreamController<MeetingEvent> _controller =
      StreamController<MeetingEvent>();
  final List<MeetingEvent> _pending = [];

  MeetingCapabilities _capabilities = MeetingCapabilities.none;
  MeetingRole _role = MeetingRole.unknown;
  bool _left = false;
  bool _disposed = false;

  @override
  MeetingProviderId get provider => fakeMeetingProviderId;

  @override
  Stream<MeetingEvent> get events => _controller.stream;

  @override
  MeetingCapabilities get capabilities => _capabilities;

  @override
  MeetingRole get role => _role;

  /// Hoeveel stappen er nog in het draaiboek staan.
  int get pendingSteps => _pending.length;

  /// Doe de volgende stap. Geeft `false` wanneer het draaiboek leeg is of de
  /// sessie al voorbij is.
  bool advance() {
    if (_pending.isEmpty || _disposed) return false;
    _emit(_pending.removeAt(0));
    return true;
  }

  /// Speel het hele draaiboek af.
  void advanceAll() {
    while (advance()) {}
  }

  @override
  Future<void> setMicrophone(bool enabled) async {
    // Rechten vóór knoppen (T12): wat niet mag, gebeurt niet — en er komt geen
    // gebeurtenis, dus de schil ziet zijn knop niet stiekem omspringen.
    if (!_capabilities.canUseMicrophone) return;
    _emit(MeetingLocalMuteChanged(isMuted: !enabled));
  }

  @override
  Future<void> setCamera(bool enabled) async {
    if (!_capabilities.canUseCamera) return;
    _emit(MeetingLocalVideoChanged(isEnabled: enabled));
  }

  @override
  Future<void> startScreenShare() async {
    if (!_capabilities.canShareScreen) return;
    _emit(const MeetingScreenShareChanged(isSharing: true));
  }

  @override
  Future<void> stopScreenShare() async {
    _emit(const MeetingScreenShareChanged(isSharing: false));
  }

  @override
  Future<void> submitRecordingConsent(bool consent) async {
    _emit(MeetingExplicitConsentChanged(isRequired: !consent));
  }

  @override
  Future<void> leave() async {
    if (_left) return;
    _left = true;
    // Wat er nog in het draaiboek stond, gebeurt niet meer. Een adapter die na
    // het weggaan zijn oude stappen alsnog afmaakt is precies de naloper die
    // §9.3 en de reducer proberen te voorkomen.
    _pending.clear();
    _emit(const MeetingPhaseChanged(MeetingPhase.leaving));
    _emit(const MeetingPhaseChanged(MeetingPhase.ended));
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _pending.clear();
    await _controller.close();
  }

  void _emit(MeetingEvent event) {
    if (_disposed || _controller.isClosed) return;
    // De sessie houdt zijn eigen kijk op rechten en rol bij, want [capabilities]
    // en [role] zijn deel van het contract en moeten kloppen met wat er zojuist
    // is uitgestuurd.
    if (event is MeetingCapabilitiesChanged) _capabilities = event.capabilities;
    if (event is MeetingRoleChanged) _role = event.role;
    _controller.add(event);
  }
}

/// Het draaiboek per verloop.
///
/// De volgorde volgt het diagram in §8.1 en houdt zich aan
/// [meetingPhaseTransitions]: een draaiboek dat de reducer zou laten weigeren,
/// is een draaiboek dat de echte adapter straks ook fout krijgt.
List<MeetingEvent> _scriptFor(
  FakeMeetingScenario scenario,
  String displayName,
) {
  final self = MeetingParticipant(
    id: fakeSelfParticipantId,
    displayName: displayName,
    role: MeetingRole.guest,
    isSelf: true,
  );
  final host = MeetingParticipant(
    id: fakeHostParticipantId,
    displayName: fakeHostDisplayName,
    role: MeetingRole.organiser,
    isMuted: false,
  );
  final admitted = <MeetingEvent>[
    const MeetingPhaseChanged(MeetingPhase.connected),
    const MeetingCapabilitiesChanged(_fullCapabilities),
    MeetingRoleChanged(MeetingRole.guest, providerLabel: 'external'),
    MeetingParticipantJoined(self),
    MeetingParticipantJoined(host),
    const MeetingNetworkQualityChanged(MeetingNetworkQuality.good),
  ];
  return switch (scenario) {
    FakeMeetingScenario.direct => [
      const MeetingPhaseChanged(MeetingPhase.connecting),
      ...admitted,
    ],
    FakeMeetingScenario.lobby => [
      const MeetingPhaseChanged(MeetingPhase.connecting),
      const MeetingPhaseChanged(MeetingPhase.lobby),
      ...admitted,
    ],
    FakeMeetingScenario.denied => [
      const MeetingPhaseChanged(MeetingPhase.connecting),
      const MeetingPhaseChanged(MeetingPhase.lobby),
      MeetingPhaseChanged(
        MeetingPhase.failed,
        failure: MeetingFailure(
          MeetingFailureKind.lobbyDenied,
          provider: fakeMeetingProviderId,
          code: 'denied',
        ),
      ),
    ],
    FakeMeetingScenario.reconnect => [
      const MeetingPhaseChanged(MeetingPhase.connecting),
      ...admitted,
      const MeetingNetworkQualityChanged(MeetingNetworkQuality.bad),
      const MeetingPhaseChanged(MeetingPhase.reconnecting),
      const MeetingPhaseChanged(MeetingPhase.connected),
      const MeetingNetworkQualityChanged(MeetingNetworkQuality.good),
    ],
    FakeMeetingScenario.endedByHost => [
      const MeetingPhaseChanged(MeetingPhase.connecting),
      ...admitted,
      const MeetingRecordingChanged(isActive: true),
      MeetingDisconnected(code: '5854'),
      const MeetingPhaseChanged(MeetingPhase.ended),
    ],
    FakeMeetingScenario.guestDisabled => [
      const MeetingPhaseChanged(MeetingPhase.connecting),
      MeetingPhaseChanged(
        MeetingPhase.failed,
        failure: MeetingFailure(
          MeetingFailureKind.anonymousJoinDisabled,
          provider: fakeMeetingProviderId,
          code: '403',
        ),
      ),
    ],
  };
}
