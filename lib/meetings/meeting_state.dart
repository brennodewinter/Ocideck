// De toestand van één onlinevergadering, en de reducer die haar bijwerkt (§8.1).
//
// Onveranderlijk, en met opzet dom: gebeurtenissen komen binnen, een nieuwe
// toestand komt eruit, en er wordt niets opgevraagd, gewacht of aangeroepen.
// Dat maakt élke overgang toetsbaar zonder adapter, zonder netwerk en zonder
// widgetboom — de reden dat §19.1 die overgangen als eerste in de lijst zet.
//
// **Wat hier niet in mag.** Geen vergaderlink, geen toegangsbewijs, geen
// vernieuwingssleutel (T5, §8.1). Riverpod-toestand is inspecteerbaar en belandt
// zo in een diagnosevenster of een foutrapport; die drie horen in een privéveld
// van de aanroeper en worden bij het verlaten gewist.
// `meeting_privacy_boundary_test.dart` bewaakt dat dit bestand er geen `Uri` en
// geen token bij krijgt.
//
// **Twee regels waar de reducer op staat.** Een fase-overgang die niet in
// [meetingPhaseTransitions] staat, wordt genegeerd in plaats van uitgevoerd: een
// adapter die "verbonden" meldt terwijl er nooit verbinding werd gezocht, meldt
// iets wat niet gebeurd kan zijn. En een gebeurtenis die ná het einde binnenkomt
// verandert niets meer — anders laat een adapter die zijn abonnementen niet
// opruimt (§9.3) een afgelopen gesprek weer tot leven komen.
import 'meeting_event.dart';
import 'meeting_failure.dart';
import 'meeting_models.dart';

/// Schildwacht voor [MeetingState.copyWith]: onderscheidt "niet meegegeven" van
/// "uitdrukkelijk leeg".
const Object _keep = Object();

/// Alles wat de schil over het lopende gesprek weet.
class MeetingState {
  const MeetingState({
    this.provider,
    this.phase = MeetingPhase.idle,
    this.isMuted = true,
    this.isCameraEnabled = false,
    this.isScreenSharing = false,
    this.isRecordingActive = false,
    this.isTranscriptionActive = false,
    this.explicitConsentRequired = false,
    this.role = MeetingRole.unknown,
    this.providerRoleLabel,
    this.capabilities = MeetingCapabilities.none,
    this.participants = const [],
    this.dominantSpeakerId,
    this.networkQuality = MeetingNetworkQuality.unknown,
    this.failure,
    this.disconnectCode,
    this.disconnectSubcode,
  });

  /// Er loopt niets. De beginwaarde, en waar [reset] naartoe gaat.
  ///
  /// Gedempt en zonder camera, want dat zijn de standaardwaarden waarmee elke
  /// sessie begint (§6.2 stap 7) — niet iets wat de schil er later overheen
  /// legt.
  static const MeetingState idle = MeetingState();

  /// Welke adapter dit gesprek voert, zodra die gekozen is.
  final MeetingProviderId? provider;

  final MeetingPhase phase;

  /// De bevestigde stand van de eigen microfoon. De *gewenste* stand, terwijl
  /// een opdracht nog loopt, hoort bij de aanroeper (§13.2) — twee begrippen
  /// die in één veld samenvallen geven een knop die terugspringt.
  final bool isMuted;

  final bool isCameraEnabled;
  final bool isScreenSharing;

  /// Of er opgenomen wordt. Alleen gemeld, nooit door OciDeck geregeld (§15).
  final bool isRecordingActive;

  /// Of het gesprek uitgeschreven wordt.
  final bool isTranscriptionActive;

  /// Of de dienst uitdrukkelijke toestemming verlangt voordat er meegedaan mag
  /// worden.
  final bool explicitConsentRequired;

  /// De rol van de gebruiker, in aanbieder-neutrale woorden.
  final MeetingRole role;

  /// Hoe de aanbieder die rol zelf noemt — voor de diagnose. Er worden geen
  /// rechten uit afgeleid; die staan in [capabilities].
  final String? providerRoleLabel;

  final MeetingCapabilities capabilities;

  /// De deelnemers, in de volgorde waarin ze binnenkwamen.
  final List<MeetingParticipant> participants;

  /// Wie er aan het woord is, als de aanbieder dat meldt.
  final String? dominantSpeakerId;

  final MeetingNetworkQuality networkQuality;

  /// Waarom het misging, wanneer [phase] `failed` is.
  final MeetingFailure? failure;

  /// De laatst gemelde verbreekcode van de aanbieder, gefilterd. Alleen voor
  /// het diagnosevenster.
  final String? disconnectCode;
  final String? disconnectSubcode;

  /// Of er iets loopt waar de gebruiker nog bij moet kunnen — de poort waar de
  /// module-onthulling van T13 aan hangt.
  bool get isActive => phase.isSessionActive;

  /// Hoeveel deelnemers er zijn, de gebruiker meegeteld.
  int get participantCount => participants.length;

  /// Eén regel voor het lokale logboek: fase, aantallen en schakelaars — nooit
  /// een naam, een sleutel of een link (§16.4).
  String get diagnosticLabel =>
      'meeting(phase=${phase.name} provider=${provider?.value ?? '-'} '
      'participants=$participantCount muted=$isMuted cam=$isCameraEnabled '
      'share=$isScreenSharing rec=$isRecordingActive '
      'transcript=$isTranscriptionActive network=${networkQuality.name}'
      '${failure == null ? '' : ' ${failure!.diagnosticLabel}'})';

  /// Drie velden hier mógen leeg worden gemaakt: niemand is aan het woord, de
  /// rol heeft geen aanbiederlabel, er is geen mislukking meer. Voor die drie
  /// kan `null` niet tegelijk "laat staan" en "maak leeg" betekenen, dus staat
  /// er een schildwacht ([_keep]) als standaardwaarde. De rest van de velden
  /// kan niet leeg zijn en houdt de gewone `?? this.`-vorm.
  MeetingState copyWith({
    MeetingProviderId? provider,
    MeetingPhase? phase,
    bool? isMuted,
    bool? isCameraEnabled,
    bool? isScreenSharing,
    bool? isRecordingActive,
    bool? isTranscriptionActive,
    bool? explicitConsentRequired,
    MeetingRole? role,
    Object? providerRoleLabel = _keep,
    MeetingCapabilities? capabilities,
    List<MeetingParticipant>? participants,
    Object? dominantSpeakerId = _keep,
    MeetingNetworkQuality? networkQuality,
    Object? failure = _keep,
    String? disconnectCode,
    String? disconnectSubcode,
  }) => MeetingState(
    provider: provider ?? this.provider,
    phase: phase ?? this.phase,
    isMuted: isMuted ?? this.isMuted,
    isCameraEnabled: isCameraEnabled ?? this.isCameraEnabled,
    isScreenSharing: isScreenSharing ?? this.isScreenSharing,
    isRecordingActive: isRecordingActive ?? this.isRecordingActive,
    isTranscriptionActive: isTranscriptionActive ?? this.isTranscriptionActive,
    explicitConsentRequired:
        explicitConsentRequired ?? this.explicitConsentRequired,
    role: role ?? this.role,
    providerRoleLabel: providerRoleLabel == _keep
        ? this.providerRoleLabel
        : providerRoleLabel as String?,
    capabilities: capabilities ?? this.capabilities,
    participants: participants ?? this.participants,
    dominantSpeakerId: dominantSpeakerId == _keep
        ? this.dominantSpeakerId
        : dominantSpeakerId as String?,
    networkQuality: networkQuality ?? this.networkQuality,
    failure: failure == _keep ? this.failure : failure as MeetingFailure?,
    disconnectCode: disconnectCode ?? this.disconnectCode,
    disconnectSubcode: disconnectSubcode ?? this.disconnectSubcode,
  );

  /// Verwerk [event] en geef de nieuwe toestand.
  ///
  /// Geeft `this` terug wanneer de gebeurtenis niet mag landen — een verboden
  /// fase-overgang, of iets wat binnenkomt terwijl er niets (meer) loopt. Dat
  /// is bewust stil: een adapter die te laat is levert geen fout op voor de
  /// gebruiker, hij levert gewoon niets op.
  MeetingState apply(MeetingEvent event) {
    if (event is MeetingPhaseChanged) return _applyPhase(event);
    // Alles wat geen fase is, gaat over een lopend gesprek. Is er geen gesprek
    // (meer), dan is het een naloper van een adapter die zijn abonnementen niet
    // heeft opgeruimd (§9.3).
    if (!_acceptsSessionEvents) return this;
    return switch (event) {
      // Al afgehandeld hierboven; de switch moet hem noemen om dicht te zijn.
      MeetingPhaseChanged() => this,
      MeetingCapabilitiesChanged(:final capabilities) => copyWith(
        capabilities: capabilities,
      ),
      MeetingRoleChanged(:final role, :final providerLabel) => _withRole(
        role,
        providerLabel,
      ),
      MeetingLocalMuteChanged(:final isMuted) => copyWith(isMuted: isMuted),
      MeetingLocalVideoChanged(:final isEnabled) => copyWith(
        isCameraEnabled: isEnabled,
      ),
      MeetingScreenShareChanged(:final isSharing) => copyWith(
        isScreenSharing: isSharing,
      ),
      MeetingParticipantJoined(:final participant) => _withParticipant(
        participant,
      ),
      MeetingParticipantUpdated(:final participant) => _updateParticipant(
        participant,
      ),
      MeetingParticipantLeft(:final participantId) => _withoutParticipant(
        participantId,
      ),
      MeetingDominantSpeakerChanged(:final participantId) =>
        _withDominantSpeaker(participantId),
      MeetingRecordingChanged(:final isActive) => copyWith(
        isRecordingActive: isActive,
      ),
      MeetingTranscriptionChanged(:final isActive) => copyWith(
        isTranscriptionActive: isActive,
      ),
      MeetingExplicitConsentChanged(:final isRequired) => copyWith(
        explicitConsentRequired: isRequired,
      ),
      MeetingNetworkQualityChanged(:final quality) => copyWith(
        networkQuality: quality,
      ),
      MeetingDisconnected(:final code, :final subcode) => copyWith(
        disconnectCode: code,
        disconnectSubcode: subcode,
      ),
    };
  }

  /// Terug naar niets. De schil roept dit aan wanneer de gebruiker de afloop
  /// van een afgelopen of mislukt gesprek heeft gezien; pas daarna verdwijnt de
  /// module weer als hij uit staat (T13).
  MeetingState reset() => idle;

  /// Of gebeurtenissen over een lopend gesprek nog iets mogen veranderen.
  ///
  /// `idle` valt erbuiten omdat er dan niets begonnen is, en `ended`/`failed`
  /// omdat er niets meer is. Wat er tussen die twee ligt, telt.
  bool get _acceptsSessionEvents =>
      phase != MeetingPhase.idle &&
      phase != MeetingPhase.ended &&
      phase != MeetingPhase.failed;

  MeetingState _withRole(MeetingRole role, String? providerLabel) =>
      copyWith(role: role, providerRoleLabel: providerLabel);

  MeetingState _withDominantSpeaker(String? participantId) =>
      copyWith(dominantSpeakerId: participantId);

  MeetingState _applyPhase(MeetingPhaseChanged event) {
    if (!phase.canTransitionTo(event.phase)) return this;
    if (event.phase == MeetingPhase.idle) return idle;
    final ending =
        event.phase == MeetingPhase.ended || event.phase == MeetingPhase.failed;
    if (!ending) {
      // De mislukking gaat mee wanneer de gebeurtenis er een draagt, en wordt
      // anders gewist: een oude reden die blijft plakken achter een fase die
      // wél doorging, leest als een gesprek dat mislukte terwijl het loopt.
      return copyWith(phase: event.phase, failure: event.failure);
    }
    // Klaar. De deelnemerslijst, de rechten en de opnamestand horen dan weg te
    // zijn: §6.5 wil dat er bij het verlaten niets van het gesprek in het
    // geheugen achterblijft, en andermans namen zijn daar het duidelijkste
    // voorbeeld van. De reden waaróm het eindigde blijft juist wél staan — die
    // moet de gebruiker nog kunnen lezen.
    return MeetingState(
      provider: provider,
      phase: event.phase,
      role: role,
      providerRoleLabel: providerRoleLabel,
      failure: event.failure ?? failure,
      disconnectCode: disconnectCode,
      disconnectSubcode: disconnectSubcode,
    );
  }

  /// Voeg een deelnemer toe, of werk hem bij wanneer de adapter hem twee keer
  /// meldt — dat gebeurt echt, bijvoorbeeld wanneer de bestaande lijst en de
  /// eerste `joined`-gebeurtenis elkaar overlappen bij het verbinden (§13.1).
  MeetingState _withParticipant(MeetingParticipant participant) {
    final index = participants.indexWhere((p) => p.id == participant.id);
    final next = [...participants];
    if (index >= 0) {
      next[index] = participant;
    } else {
      next.add(participant);
    }
    return copyWith(participants: next);
  }

  /// Werk een bekende deelnemer bij. Een onbekende sleutel doet niets: er is
  /// geen route waarlangs iemand zonder `joined` in de lijst hoort te komen, en
  /// hem hier alsnog toevoegen zou dat gat verbergen.
  MeetingState _updateParticipant(MeetingParticipant participant) {
    final index = participants.indexWhere((p) => p.id == participant.id);
    if (index < 0) return this;
    final next = [...participants];
    next[index] = participant;
    return copyWith(participants: next);
  }

  MeetingState _withoutParticipant(String participantId) {
    if (!participants.any((p) => p.id == participantId)) return this;
    return MeetingState(
      provider: provider,
      phase: phase,
      isMuted: isMuted,
      isCameraEnabled: isCameraEnabled,
      isScreenSharing: isScreenSharing,
      isRecordingActive: isRecordingActive,
      isTranscriptionActive: isTranscriptionActive,
      explicitConsentRequired: explicitConsentRequired,
      role: role,
      providerRoleLabel: providerRoleLabel,
      capabilities: capabilities,
      participants: [
        for (final p in participants)
          if (p.id != participantId) p,
      ],
      // Wie weg is, is niet meer aan het woord. Zonder dit blijft de tegel van
      // een vertrokken deelnemer oplichten.
      dominantSpeakerId: dominantSpeakerId == participantId
          ? null
          : dominantSpeakerId,
      networkQuality: networkQuality,
      failure: failure,
      disconnectCode: disconnectCode,
      disconnectSubcode: disconnectSubcode,
    );
  }
}
