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

import 'meeting_event.dart';
import 'meeting_participant.dart';

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
  const MeetingLinkMatch({required this.providerId, required this.invitation});

  final String providerId;

  /// The recognised invitation, already stripped of fragments/tracking params by
  /// the resolver before it reaches an adapter (`NATIVE_CALLS.md` §7.1.6).
  final Uri invitation;
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

  /// Whether a join may proceed at all from these facts.
  bool get canJoin =>
      failureReason == null &&
      (support == MeetingSupport.nativeClient ||
          support == MeetingSupport.embeddedOfficialClient);
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

  Future<void> setMicrophone({required bool enabled});
  Future<void> setCamera({required bool enabled});
  Future<void> startScreenShare();
  Future<void> stopScreenShare();
  Future<void> sendChat(String text);

  /// Leave and release all resources. Idempotent; closes [events].
  Future<void> leave();
}
