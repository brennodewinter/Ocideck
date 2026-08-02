// A scriptable fake behind the F1 meeting contract (`docs/design/NATIVE_CALLS.md`
// §7, phase F1: "a fake adapter, no external SDK"). It lets the contract and the
// call UI be exercised with no media stack: tests drive a session's roster, chat,
// role and connection state through the helper methods below and assert that the
// backend-agnostic surface behaves. A real adapter (Jitsi over lib/xmpp/ +
// flutter_webrtc, then MatrixRTC) replaces this behind the same interface.
//
// It lives under test/ on purpose: it is a test double, not a shipped provider,
// so no fake identities land in lib/.

import 'dart:async';

import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';

/// Recognises `https://fake.local/<room>` and joins a [FakeMeetingSession].
class FakeMeetingProvider implements MeetingProvider {
  const FakeMeetingProvider();

  @override
  String get id => 'fake';

  @override
  Set<String> get trustedHosts => const {'fake.local'};

  @override
  MeetingLinkMatch? match(Uri invitation) {
    if (invitation.host != 'fake.local') return null;
    return MeetingLinkMatch(providerId: id, invitation: invitation);
  }

  @override
  Future<MeetingPreflight> preflight(MeetingLinkMatch link) async {
    return const MeetingPreflight(
      support: MeetingSupport.nativeClient,
      capabilities: MeetingCapabilities(
        audio: true,
        video: true,
        screenShare: true,
        chat: true,
        roster: true,
      ),
      // A meeting provider never inherits an E2EE claim (NATIVE_CALLS.md §6).
      e2ee: MeetingE2eeStatus.unknown,
      identityLabel: 'guest',
      egressOrigins: ['fake.local'],
    );
  }

  @override
  Future<MeetingSession> join(MeetingJoinRequest request) async =>
      FakeMeetingSession(request);
}

/// A live fake session. Starts `connected` with only the local participant, then
/// tests script the rest via the helper methods.
class FakeMeetingSession implements MeetingSession {
  FakeMeetingSession(MeetingJoinRequest request)
    : _local = MeetingParticipant(
        id: 'local',
        displayName: request.displayName,
        role: MeetingRole.guest,
        isLocal: true,
        micMuted: request.startMuted,
        camOff: request.startCameraOff,
      );

  final _events = StreamController<MeetingEvent>.broadcast();
  final _remotes = <String, MeetingParticipant>{};

  MeetingParticipant _local;
  MeetingCapabilities _capabilities = const MeetingCapabilities(
    audio: true,
    video: true,
    screenShare: true,
    chat: true,
    roster: true,
  );
  MeetingConnectionState _connectionState = MeetingConnectionState.connected;
  bool _closed = false;

  @override
  String get providerId => 'fake';

  @override
  Stream<MeetingEvent> get events => _events.stream;

  @override
  MeetingCapabilities get capabilities => _capabilities;

  @override
  MeetingConnectionState get connectionState => _connectionState;

  @override
  MeetingRole get localRole => _local.role;

  @override
  List<MeetingParticipant> get participants => [_local, ..._remotes.values];

  @override
  Future<void> setMicrophone({required bool enabled}) async {
    _updateLocal(_local.copyWith(micMuted: !enabled));
  }

  @override
  Future<void> setCamera({required bool enabled}) async {
    _updateLocal(_local.copyWith(camOff: !enabled));
  }

  @override
  Future<void> startScreenShare() async {
    _updateLocal(_local.copyWith(isScreenShare: true));
  }

  @override
  Future<void> stopScreenShare() async {
    _updateLocal(_local.copyWith(isScreenShare: false));
  }

  @override
  Future<void> sendChat(String text) async {
    _emit(ChatReceived(participantId: _local.id, text: text));
  }

  @override
  Future<void> leave() async {
    if (_closed) return;
    _closed = true;
    _connectionState = MeetingConnectionState.disconnected;
    _events.add(
      const ConnectionStateChanged(MeetingConnectionState.disconnected),
    );
    await _events.close();
  }

  // ── test helpers ──────────────────────────────────────────────────────────

  /// A remote participant joins.
  void addRemoteParticipant(MeetingParticipant participant) {
    _remotes[participant.id] = participant;
    _emit(ParticipantJoined(participant));
  }

  /// A remote participant leaves.
  void removeRemoteParticipant(String participantId) {
    if (_remotes.remove(participantId) != null) {
      _emit(ParticipantLeft(participantId));
    }
  }

  /// A remote sends chat.
  void pushRemoteChat(String participantId, String text) {
    _emit(ChatReceived(participantId: participantId, text: text));
  }

  /// The host promotes/demotes the local user.
  void setLocalRole(MeetingRole role) {
    _updateLocal(_local.copyWith(role: role));
  }

  /// The host grants/revokes controls mid-call.
  void setCapabilities(MeetingCapabilities capabilities) {
    _capabilities = capabilities;
    _emit(CapabilitiesChanged(capabilities));
  }

  /// Drive the connection lifecycle.
  void setConnectionState(MeetingConnectionState state) {
    _connectionState = state;
    _emit(ConnectionStateChanged(state));
  }

  /// The provider signals a recording indicator change.
  void setRecording({required bool active}) {
    _emit(RecordingIndicatorChanged(active: active));
  }

  /// A recoverable error surfaces.
  void pushError(String message, {bool terminal = false}) {
    _emit(MeetingErrorEvent(message: message, terminal: terminal));
  }

  void _updateLocal(MeetingParticipant next) {
    _local = next;
    _emit(ParticipantUpdated(next));
  }

  void _emit(MeetingEvent event) {
    if (!_closed) _events.add(event);
  }
}
