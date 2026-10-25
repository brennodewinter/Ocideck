// The backend-neutral meeting contract (`docs/design/NATIVE_CALLS.md` §1, §3;
// COLLABORATION.md §7.1.1). One call/presenter UI renders solely from these
// types, so a Jitsi session and a (later) MatrixRTC session are the same
// experience — the UI never learns which backend is underneath (the "one shell
// for every adapter" invariant, TEAMS_GUEST_CLIENT.md T13/T14).
//
// This file adds no dependency: it is pure Dart contracts plus small data
// classes. The first implementation behind it is a fake adapter used by tests
// (F1); real adapters (Jitsi over `lib/xmpp/` + `flutter_webrtc`, then MatrixRTC)
// arrive once the build-conditions in the chain reviews are met.
//
// Backend exclusivity (`NATIVE_CALLS.md` §1) lives one layer up: a session runs
// entirely on one family, and no code pairs a [MeetingSession] of one family with
// a `CollabTransport` of another. Nothing here couples the two.

import 'call_audio_source.dart';
import 'meeting_event.dart';
import 'meeting_media_core.dart'
    show MeetingAudioOutput, MeetingScreenSource, MeetingVideoSurface;
import 'meeting_participant.dart';
import 'meeting_provider_profile.dart';

/// How well a provider can be joined from OciDeck for a given link.
enum MeetingSupport {
  /// OciDeck speaks the provider's protocol natively (own interface).
  nativeClient,

  /// Only through the provider's own embedded/official client.
  embeddedOfficialClient,

  /// Not joinable in-app; offer the official browser page instead.
  redirectOnly,

  /// Recognised family, but this link/meeting type is not supported.
  unsupported,
}

/// Known end-to-end-encryption status of a meeting's **media**. `unknown` is a
/// first-class value: OciDeck must not claim E2EE it cannot verify, and must not
/// inherit an E2EE claim from a collaboration session (`NATIVE_CALLS.md` §6).
enum MeetingE2eeStatus { off, on, unknown }

/// A stable, machine-readable reason a join cannot proceed, shown to the user in
/// its own words by the shell (`NATIVE_CALLS.md` §7.1.1).
enum MeetingFailureReason {
  guestDisabled,
  accountRequired,
  appApprovalRequired,
  meetingTypeUnsupported,
  providerUnavailable,
}

/// The result of a pure local recognition of a pasted link against one provider.
/// Producing a match must make **no** network request (`NATIVE_CALLS.md` §7.1.6,
/// "no probing").
class MeetingLinkMatch {
  const MeetingLinkMatch({
    required this.providerId,
    required this.invitation,
    this.viaProfile,
  });

  final String providerId;

  /// The recognised invitation, already stripped of fragments/tracking params by
  /// the resolver before it reaches an adapter (`NATIVE_CALLS.md` §7.1.6).
  final Uri invitation;

  /// The user-approved profile that recognised this link, when the match did
  /// not come from a built-in trusted host. Carries the explicit trust
  /// decisions (trustedInternal, cert pin) that preflight/join need; null for
  /// built-in hosts, which use the ordinary (untrusted-internal) posture.
  final MeetingProviderProfile? viaProfile;
}

/// Typed support and policy facts resolved after the user acts, never a boolean
/// (`NATIVE_CALLS.md` §7.1.1). The join screen renders from this.
class MeetingPreflight {
  const MeetingPreflight({
    required this.support,
    required this.capabilities,
    required this.e2ee,
    this.identityLabel,
    this.egressOrigins = const <String>[],
    this.failureReason,
    this.diagnosticsDetail,
  });

  final MeetingSupport support;
  final MeetingCapabilities capabilities;
  final MeetingE2eeStatus e2ee;

  /// The identity label other participants and the provider will see (e.g. an
  /// anonymous display name), or null when not yet chosen.
  final String? identityLabel;

  /// The origins that will receive traffic, disclosed before any join.
  final List<String> egressOrigins;

  /// Set only when [support] is [MeetingSupport.unsupported] or a join is refused.
  final MeetingFailureReason? failureReason;

  /// Short, non-secret detail for diagnostics/support (e.g. "config.js HTTP
  /// 404", "websocket host refused"). Never carries credentials or full URLs
  /// with paths — adapters keep it coarse.
  final String? diagnosticsDetail;

  /// Whether a join may proceed at all from these facts.
  bool get canJoin =>
      failureReason == null &&
      (support == MeetingSupport.nativeClient ||
          support == MeetingSupport.embeddedOfficialClient);
}

/// Waarom `join` geen sessie kon leveren — getypeerd zodat de UI de reden in
/// eigen woorden toont, nooit een generieke "mislukt". Elke adapter werpt dit;
/// `detail` volgt de [MeetingPreflight.diagnosticsDetail]-contractregels
/// (grof, geen credentials, geen volledige URL's).
class MeetingJoinException implements Exception {
  const MeetingJoinException(this.reason, [this.detail]);

  final MeetingFailureReason reason;
  final String? detail;

  @override
  String toString() =>
      'join ${reason.name}${detail != null ? ': $detail' : ''}';
}

/// Everything an adapter needs to join. Defaults come from OciDeck, never from the
/// invitation — the resolver strips fragment overrides so a crafted link cannot
/// unmute the user or preset a camera (`NATIVE_CALLS.md` §7.1.6).
class MeetingJoinRequest {
  const MeetingJoinRequest({
    required this.link,
    required this.displayName,
    this.startMuted = true,
    this.startCameraOff = true,
  });

  final MeetingLinkMatch link;
  final String displayName;
  final bool startMuted;
  final bool startCameraOff;
}

/// Recognises and joins one family of external/self-operated meetings. Adapters
/// supply facts (recognition, capabilities, egress, role) and never their own
/// screens.
abstract interface class MeetingProvider {
  /// A stable id for this provider family (e.g. `jitsi`).
  String get id;

  /// Hosts this provider recognises without a user-approved profile (the built-in
  /// public deployments, `NATIVE_CALLS.md` §5). Matched suffix-safe by the caller.
  Set<String> get trustedHosts;

  /// Pure local recognition — must make **no** network request. Returns null when
  /// this provider does not recognise [invitation].
  MeetingLinkMatch? match(Uri invitation);

  /// Resolve capabilities and policy facts. Called only after an explicit user
  /// action (the disclosure/consent step), never during recognition.
  Future<MeetingPreflight> preflight(MeetingLinkMatch link);

  /// Create one session. The caller owns it root-scoped (a call survives a deck
  /// tab switch, `NATIVE_CALLS.md` §9), never deck/tab-scoped.
  Future<MeetingSession> join(MeetingJoinRequest request);
}

/// One live meeting the UI drives. Backend-agnostic: the UI reads
/// [capabilities]/[participants]/[connectionState] and the [events] stream, and
/// calls the intent methods; it never knows the provider underneath.
abstract interface class MeetingSession {
  /// The id of the [MeetingProvider] that created this session.
  String get providerId;

  /// Typed events, delivered in order. A late subscriber can read the current
  /// [participants]/[capabilities]/[connectionState] without replaying the stream.
  Stream<MeetingEvent> get events;

  /// The controls the UI may currently render (live state).
  MeetingCapabilities get capabilities;

  /// The current connection lifecycle state.
  MeetingConnectionState get connectionState;

  /// The local user's current role (live state; a host may change it mid-call).
  MeetingRole get localRole;

  /// A snapshot of the current roster, including the local participant.
  List<MeetingParticipant> get participants;

  /// De media-E2EE-status van deze sessie zoals de medialaag die rapporteert —
  /// `off`/`unknown`/`on`, nooit een claim die niet geverifieerd is (#2535).
  MeetingE2eeStatus get mediaE2ee;

  /// De werkelijke media-egress: de SFU/TURN-bestemmingen die de gevalideerde
  /// signalling overdroeg (de JVB uit de Jingle-transport, eventuele ICE-
  /// servers). Leeg zolang er geen mediapad is — de UI toont dit eerlijk
  /// naast [mediaE2ee] (#2535).
  List<String> get mediaEgressOrigins;

  /// Render de videotrack van een deelnemer als Flutter-texture, of null als
  /// er geen renderbaar beeld is (geen track, track geëindigd, platform
  /// zonder video). Werkt ook voor de lokale participant (self-view). De UI
  /// disposet het opgeleverde [MeetingVideoSurface] bij een track-wissel of
  /// als de tegel verdwijnt (#2535).
  Future<MeetingVideoSurface?> videoSurfaceFor(String participantId);

  /// De audio-uitvoerbestemmingen die het apparaat nu kent — leeg zonder
  /// mediapad of platformondersteuning; dan verbergt de UI de picker (#2535).
  Future<List<MeetingAudioOutput>> audioOutputs();

  /// Kies waar de call-audio heen gaat (best-effort; een verdwenen id faalt
  /// stil en de OS-default geldt).
  Future<void> selectAudioOutput(String deviceId);

  Future<void> setMicrophone({required bool enabled});
  Future<void> setCamera({required bool enabled});

  /// De deelbare schermbronnen voor de kiezer (#2537). Leeg waar de browser
  /// of het OS zelf kiest — dan is [startScreenShare] zonder sourceId de
  /// route.
  Future<List<MeetingScreenSource>> screenShareSources();

  /// Start het delen van [sourceId] (uit [screenShareSources]; null waar de
  /// browser zelf kiest). Weigering, annuleren of bronverlies komt als een
  /// [MeetingErrorEvent] op [events]; de call blijft intact.
  Future<void> startScreenShare({String? sourceId, String? sourceLabel});

  /// De label van de bron die nu live wordt gedeeld — null als er niets
  /// deelt. De UI toont die naast de deelknop (#2537).
  String? get screenShareLabel;

  /// Stop het delen. Idempotent — zonder lopende share een no-op.
  Future<void> stopScreenShare();

  /// De hele-call-audiotap (#2527). Leeg zolang [MeetingCapabilities.callAudio]
  /// geen whole-call is — een track-id of een provider-lampje start hier
  /// niets. Een capability die whole-call claimt zonder tap faalt hard.
  Stream<CallAudioChunk> startCallAudioCapture();

  /// Stop de tap. Idempotent — zonder lopende tap een no-op.
  Future<void> stopCallAudioCapture();

  Future<void> sendChat(String text);

  /// Leave and release all resources. Idempotent; closes [events].
  Future<void> leave();
}
