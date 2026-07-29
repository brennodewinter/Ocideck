// De getypeerde gebeurtenissen die een adapter naar de schil stuurt (§8.3).
//
// Eén gesloten `sealed` boom, en dat is de hele truc: de reducer in
// `meeting_state.dart` moet elk geval afhandelen, dus een adapter kan geen
// gebeurtenis verzinnen die stilletjes nergens landt. Wat er hier niet in staat,
// bestaat niet.
//
// **Wat er nooit in een gebeurtenis zit.** Geen vergaderlink, geen token, geen
// ruw SDK-object en geen uitzonderingstekst (T7, T11, §16.4). Een adapter
// vertaalt zijn eigen wereld naar déze DTO's; wat hij niet kwijt kan, hoort de
// schil ook niet te weten.
//
// **[MeetingEvent.diagnosticLabel] is de enige route naar het logboek.** §16.4
// laat fase, code, subcode, mogelijkheden en *aantallen* toe, en verbiedt namen
// en identiteiten — óók de ondoorzichtige deelnemer-id, want die is per sessie
// stabiel en dus een spoor. Elke gebeurtenis levert daarom zelf zijn logregel;
// wie iets nieuws toevoegt komt langs deze getter en langs
// `meeting_log_redaction_test.dart`.
//
// Afwijking van §8.3, hardop: elke klasse krijgt hier het voorvoegsel
// `Meeting`. Het ontwerp schrijft `ParticipantJoined`, `RecordingChanged`,
// `LocalMuteChanged`; dat zijn te algemene namen voor één gedeelde Dart-ruimte
// waarin straks ook samenwerking zijn eigen deelnemers en opnames krijgt
// (`COLLABORATION.md`). De begrippen en de velden zijn ongewijzigd.
import 'meeting_failure.dart';
import 'meeting_models.dart';

/// Iets wat er in een sessie gebeurde.
sealed class MeetingEvent {
  const MeetingEvent();

  /// Eén regel voor het lokale logboek, zonder inhoud (§16.4).
  String get diagnosticLabel;
}

/// De fase veranderde. Draagt de [failure] mee wanneer de nieuwe fase
/// [MeetingPhase.failed] is — die twee horen bij elkaar en mogen niet als twee
/// losse gebeurtenissen aankomen, want dan bestaat er een tussenmoment waarin
/// de schil "mislukt" toont zonder te weten waarom.
final class MeetingPhaseChanged extends MeetingEvent {
  const MeetingPhaseChanged(this.phase, {this.failure});

  final MeetingPhase phase;
  final MeetingFailure? failure;

  @override
  String get diagnosticLabel => failure == null
      ? 'phase(${phase.name})'
      : 'phase(${phase.name}) ${failure!.diagnosticLabel}';
}

/// De rechten veranderden — een bevordering, een degradatie, of een organisator
/// die het delen van het scherm intrekt terwijl het gesprek loopt.
final class MeetingCapabilitiesChanged extends MeetingEvent {
  const MeetingCapabilitiesChanged(this.capabilities);

  final MeetingCapabilities capabilities;

  @override
  String get diagnosticLabel =>
      'capabilities(mic=${capabilities.canUseMicrophone} '
      'cam=${capabilities.canUseCamera} '
      'share=${capabilities.canShareScreen} '
      'roster=${capabilities.canSeeRoster})';
}

/// De rol van de gebruiker veranderde.
///
/// [providerLabel] bewaart hoe de aanbieder die rol zélf noemt, voor de
/// diagnose. Rechten volgen er niet uit: die komen uit
/// [MeetingCapabilitiesChanged] en nergens anders.
final class MeetingRoleChanged extends MeetingEvent {
  MeetingRoleChanged(this.role, {String? providerLabel})
    : providerLabel = sanitizeDiagnosticCode(providerLabel);

  final MeetingRole role;
  final String? providerLabel;

  @override
  String get diagnosticLabel => providerLabel == null
      ? 'role(${role.name})'
      : 'role(${role.name} as=$providerLabel)';
}

/// De eigen microfoon ging aan of uit.
final class MeetingLocalMuteChanged extends MeetingEvent {
  const MeetingLocalMuteChanged({required this.isMuted});

  final bool isMuted;

  @override
  String get diagnosticLabel => 'localMute($isMuted)';
}

/// De eigen camera ging aan of uit.
final class MeetingLocalVideoChanged extends MeetingEvent {
  const MeetingLocalVideoChanged({required this.isEnabled});

  final bool isEnabled;

  @override
  String get diagnosticLabel => 'localVideo($isEnabled)';
}

/// Het delen van het scherm begon of stopte — ook wanneer de browser of de
/// gebruiker het buiten OciDeck om afbrak (§21, fase 4).
final class MeetingScreenShareChanged extends MeetingEvent {
  const MeetingScreenShareChanged({required this.isSharing});

  final bool isSharing;

  @override
  String get diagnosticLabel => 'screenShare($isSharing)';
}

/// Er kwam iemand bij.
final class MeetingParticipantJoined extends MeetingEvent {
  const MeetingParticipantJoined(this.participant);

  final MeetingParticipant participant;

  @override
  String get diagnosticLabel => 'participantJoined';
}

/// Iemands toestand veranderde: gedempt, aan het woord, camera aan, andere rol.
final class MeetingParticipantUpdated extends MeetingEvent {
  const MeetingParticipantUpdated(this.participant);

  final MeetingParticipant participant;

  @override
  String get diagnosticLabel => 'participantUpdated';
}

/// Iemand ging weg. Draagt alleen de sleutel — de rest van de gegevens hoort
/// dan al weg te zijn.
final class MeetingParticipantLeft extends MeetingEvent {
  const MeetingParticipantLeft(this.participantId);

  final String participantId;

  @override
  String get diagnosticLabel => 'participantLeft';
}

/// Wie er nu aan het woord is, of `null` wanneer dat niemand is. Niet elke
/// aanbieder meldt dit; de schil mag er dus niets op bouwen wat zonder deze
/// gebeurtenis stukgaat.
final class MeetingDominantSpeakerChanged extends MeetingEvent {
  const MeetingDominantSpeakerChanged(this.participantId);

  final String? participantId;

  @override
  String get diagnosticLabel =>
      'dominantSpeaker(${participantId == null ? 'none' : 'set'})';
}

/// De opname begon of stopte (§15). Een verplichte melding, geen detail: de
/// schil zet hier een blijvende banier op.
final class MeetingRecordingChanged extends MeetingEvent {
  const MeetingRecordingChanged({required this.isActive});

  final bool isActive;

  @override
  String get diagnosticLabel => 'recording($isActive)';
}

/// Het uitschrijven van het gesprek begon of stopte (§15).
final class MeetingTranscriptionChanged extends MeetingEvent {
  const MeetingTranscriptionChanged({required this.isActive});

  final bool isActive;

  @override
  String get diagnosticLabel => 'transcription($isActive)';
}

/// De vergadering vraagt uitdrukkelijk toestemming voordat er verder
/// meegedaan mag worden (§15). Weggaan blijft altijd mogelijk zonder die
/// toestemming te geven.
final class MeetingExplicitConsentChanged extends MeetingEvent {
  const MeetingExplicitConsentChanged({required this.isRequired});

  final bool isRequired;

  @override
  String get diagnosticLabel => 'explicitConsent($isRequired)';
}

/// De verbindingskwaliteit veranderde. Het `CallDiagnosticChanged` uit §8.3,
/// teruggebracht tot wat een gebruiker eraan heeft.
final class MeetingNetworkQualityChanged extends MeetingEvent {
  const MeetingNetworkQualityChanged(this.quality);

  final MeetingNetworkQuality quality;

  @override
  String get diagnosticLabel => 'network(${quality.name})';
}

/// De verbinding werd verbroken, met de code van de aanbieder erbij.
///
/// Dit is niet hetzelfde als de fase: dit zegt wát de dienst meldde, de fase
/// zegt wat OciDeck ervan maakt. De codes zijn gefilterd
/// ([sanitizeDiagnosticCode]) zodat er geen melding meelift.
final class MeetingDisconnected extends MeetingEvent {
  MeetingDisconnected({String? code, String? subcode})
    : code = sanitizeDiagnosticCode(code),
      subcode = sanitizeDiagnosticCode(subcode);

  final String? code;
  final String? subcode;

  @override
  String get diagnosticLabel =>
      'disconnected(code=${code ?? '-'} sub=${subcode ?? '-'})';
}
