// The provider-neutral media model the call UI renders from
// (`docs/design/NATIVE_CALLS.md` §3). It is deliberately **dependency-neutral**:
// nothing here imports `flutter_webrtc`, so the interface and the F1 fake adapter
// compile with no media stack present. A [MeetingTrack] is an opaque handle — the
// UI needs only its [MeetingTrack.id] to place and key a video tile; a later
// native adapter (F3) maps a real `flutter_webrtc` `MediaStreamTrack` onto a
// [MeetingTrack] behind this seam. Keeping the native object out of this type is
// what lets `lib/meetings/` carry no media dependency (F1).

/// A provider-neutral role. Adapters translate their backend's role vocabulary
/// onto this set and keep the original label only for diagnostics
/// (`NATIVE_CALLS.md` §6, TEAMS_GUEST_CLIENT.md T14).
enum MeetingRole { guest, attendee, presenter, moderator, organiser, unknown }

/// What a [MeetingTrack] carries. Screen share is distinct from camera video so
/// the UI can place it differently (a shared slide is not a face tile).
enum MeetingTrackKind { audio, video, screenShare }

/// An opaque handle to one live media track. The concrete media object lives in
/// whatever adapter created the track; this type intentionally holds only what
/// the UI needs — a stable [id] to key a renderer, and the [kind].
class MeetingTrack {
  const MeetingTrack({required this.id, required this.kind});

  final String id;
  final MeetingTrackKind kind;
}

/// One participant in a meeting, as the backend-agnostic UI sees them. Both the
/// Jitsi and the (later) MatrixRTC adapter fill exactly this shape; the UI renders
/// a tile per participant and never learns which backend produced it.
class MeetingParticipant {
  const MeetingParticipant({
    required this.id,
    required this.displayName,
    required this.role,
    this.isLocal = false,
    this.audio,
    this.video,
    this.micMuted = false,
    this.camOff = false,
    this.isDominantSpeaker = false,
    this.isScreenShare = false,
  });

  /// Stable within the session (an adapter-assigned participant id).
  final String id;
  final String displayName;
  final MeetingRole role;

  /// True for the local user's own tile.
  final bool isLocal;

  final MeetingTrack? audio;
  final MeetingTrack? video;

  final bool micMuted;
  final bool camOff;
  final bool isDominantSpeaker;

  /// True when this participant's video tile is a shared screen, not a camera.
  final bool isScreenShare;

  /// A copy with live-state fields changed. Adapters build the next participant
  /// state from the previous one when a mute/role/speaker change arrives. Track
  /// add/remove is expressed through the event stream, not here, so the nullable
  /// track fields are carried through unchanged rather than clearable.
  MeetingParticipant copyWith({
    String? displayName,
    MeetingRole? role,
    bool? micMuted,
    bool? camOff,
    bool? isDominantSpeaker,
    bool? isScreenShare,
    MeetingTrack? audio,
    MeetingTrack? video,
  }) {
    return MeetingParticipant(
      id: id,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      isLocal: isLocal,
      audio: audio ?? this.audio,
      video: video ?? this.video,
      micMuted: micMuted ?? this.micMuted,
      camOff: camOff ?? this.camOff,
      isDominantSpeaker: isDominantSpeaker ?? this.isDominantSpeaker,
      isScreenShare: isScreenShare ?? this.isScreenShare,
    );
  }
}

/// What the UI may render controls for. The call UI shows a control **only** when
/// its capability is present; it never imitates a control the adapter cannot
/// perform. Capabilities are live state — a host may grant or revoke them mid-call
/// (delivered via a capabilities-changed event), and the UI adds/removes controls
/// accordingly (`NATIVE_CALLS.md` §1, §6). It lives here, beside the participant
/// model, so the event layer can carry it without depending on the provider layer.
class MeetingCapabilities {
  const MeetingCapabilities({
    this.audio = false,
    this.video = false,
    this.screenShare = false,
    this.chat = false,
    this.roster = false,
  });

  final bool audio;
  final bool video;
  final bool screenShare;
  final bool chat;
  final bool roster;
}
