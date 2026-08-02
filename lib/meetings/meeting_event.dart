// The typed events a [MeetingSession] emits (`docs/design/NATIVE_CALLS.md` §3,
// §6). The call UI is driven entirely by these plus [MeetingCapabilities] and the
// participant list; it never reaches into an adapter's backend. The hierarchy is
// `sealed` so a `switch` over it is exhaustive — adding an event without handling
// it everywhere is a compile error, not a silent gap (same discipline as
// `deck_op.dart`'s `DeckOp`).
//
// Fine-grained per-track add/remove is deliberately folded into
// [ParticipantUpdated] for now: a participant carries its current tracks, so the
// UI re-renders that tile from the updated participant. A separate track-level
// event can be added later behind this same sealed seam if an adapter needs it.

import 'meeting_participant.dart';

/// A live change in a meeting, delivered in order on [MeetingSession.events].
sealed class MeetingEvent {
  const MeetingEvent();
}

/// A participant joined the meeting.
class ParticipantJoined extends MeetingEvent {
  const ParticipantJoined(this.participant);

  final MeetingParticipant participant;
}

/// The participant [participantId] left the meeting.
class ParticipantLeft extends MeetingEvent {
  const ParticipantLeft(this.participantId);

  final String participantId;
}

/// A participant's live state changed (mute, camera, role, dominant speaker, or
/// its tracks). Carries the full new [MeetingParticipant] so the UI replaces the
/// tile wholesale rather than diffing fields.
class ParticipantUpdated extends MeetingEvent {
  const ParticipantUpdated(this.participant);

  final MeetingParticipant participant;
}

/// The session's connection state changed (see [MeetingConnectionState]).
class ConnectionStateChanged extends MeetingEvent {
  const ConnectionStateChanged(this.state);

  final MeetingConnectionState state;
}

/// The controls the host currently grants changed mid-call. The UI adds or
/// removes controls from the new [capabilities] without ending the session
/// (`NATIVE_CALLS.md` §1, §6).
class CapabilitiesChanged extends MeetingEvent {
  const CapabilitiesChanged(this.capabilities);

  final MeetingCapabilities capabilities;
}

/// A chat message arrived from [participantId].
class ChatReceived extends MeetingEvent {
  const ChatReceived({required this.participantId, required this.text});

  final String participantId;
  final String text;
}

/// The recording/transcription indicator changed. The UI must surface this; the
/// provider's own consent flow is authoritative (`NATIVE_CALLS.md` §7.1.6).
class RecordingIndicatorChanged extends MeetingEvent {
  const RecordingIndicatorChanged({required this.active});

  final bool active;
}

/// A recoverable or terminal error the UI should surface. [terminal] true means
/// the session has ended and will emit nothing further.
class MeetingErrorEvent extends MeetingEvent {
  const MeetingErrorEvent({required this.message, this.terminal = false});

  final String message;
  final bool terminal;
}

/// The connection lifecycle of a [MeetingSession]. Reported both as a getter and
/// via [ConnectionStateChanged] events so late subscribers can read the current
/// value without replaying the stream.
enum MeetingConnectionState {
  idle,
  connecting,
  connected,
  reconnecting,
  disconnected,
  failed,
}
