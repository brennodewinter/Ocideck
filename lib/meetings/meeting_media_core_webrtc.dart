// The one real `flutter_webrtc` binding (F3, ketenkeuring
// `assurance/ketenkeuring-flutter-webrtc.md`). It touches libwebrtc through
// platform channels, so it cannot run in a headless test VM — it is verified on a
// device, live, not by a unit test. For that reason it is the sole media file in
// `tool/coverage_summary.dart`'s `uncoveredBaseline` (an untestable native-media
// binding, the same reason a platform `_io` half sits there). Every testable
// decision — the E2EE fact, the egress policy, the Jingle/SDP translation —
// lives in `meeting_media_core.dart` and `jitsi_*.dart` and is covered there;
// this file holds only the direct libwebrtc calls, kept deliberately thin.
//
// The model follows the wire: the JVB offers audio/video/data over one BUNDLE
// transport; we answer sendrecv on two pre-created transceivers, so a track
// that arrives LATER (camera switched on mid-call) needs only
// `sender.replaceTrack` — no re-offer, no renegotiation. That is exactly what
// lib-jitsi-meet does; the focus learns the new source via `source-add`, which
// the adapter sends (this file never touches XMPP).

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../utils/log.dart';
import 'meeting_media_core.dart';
import 'meeting_participant.dart';
import 'meeting_provider.dart' show MeetingE2eeStatus;

/// The production [MeetingMediaCore]. No branching logic — only the libwebrtc
/// calls the seam promises.
class WebrtcMediaCore implements MeetingMediaCore {
  WebrtcMediaCore({TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform;

  final TargetPlatform _platform;

  @override
  MeetingE2eeStatus get mediaE2ee => mediaE2eeFor(_platform);

  @override
  Future<bool> selfTest() async {
    // Bring up a throwaway peer connection with no ICE servers to confirm
    // libwebrtc loaded on this device, then tear it down. This reaches NO network,
    // and that invariant rests on four things — changing ANY one starts ICE
    // gathering, and with it `.local` mDNS multicast on the LAN, even with no ICE
    // servers: the empty `iceServers`, no `iceCandidatePoolSize` (default 0), no
    // offer (`createOffer`/`setLocalDescription`), and no track/transceiver/
    // datachannel. Keep selfTest a bare create-and-close (this file is in
    // uncoveredBaseline, so no test guards the invariant — this comment is it).
    try {
      final pc = await createPeerConnection(const {'iceServers': <Object>[]});
      await pc.close();
      return true;
    } catch (e) {
      logWarning('WebrtcMediaCore.selfTest: media stack unavailable', e);
      return false;
    }
  }

  @override
  Future<MeetingMediaConnection> openConnection({
    List<MeetingIceServer> iceServers = const [],
  }) async {
    // BUNDLE is vereist (de signalling-laag weigert alles anders), rtcp-mux
    // staat in het Jitsi-offer altijd aan.
    final pc = await createPeerConnection(<String, Object>{
      'iceServers': [
        for (final s in iceServers)
          <String, Object?>{
            'urls': s.url,
            if (s.username != null) 'username': s.username,
            if (s.credential != null) 'credential': s.credential,
          },
      ],
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
    });
    // Twee sendrecv-transceivers vóór de remote offer: audio en video
    // corresponderen dan met de eerste twee m-lines van de JVB. Een latere
    // track koppelt aan de bestaande transceiver — geen heronderhandeling.
    final audio = await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
    );
    final video = await pc.addTransceiver(
      kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
      init: RTCRtpTransceiverInit(direction: TransceiverDirection.SendRecv),
    );
    return _WebrtcConnection(pc, audio, video);
  }

  @override
  Future<void> dispose() async {}
}

class _WebrtcConnection implements MeetingMediaConnection {
  _WebrtcConnection(this._pc, this._audioTr, this._videoTr) {
    _pc
      ..onTrack = _onTrack
      ..onRemoveStream = _onRemoveStream
      ..onIceConnectionState = _onIceState;
  }

  final RTCPeerConnection _pc;
  final RTCRtpTransceiver _audioTr;
  final RTCRtpTransceiver _videoTr;
  final _remote = StreamController<MeetingRemoteTrack>.broadcast();
  final _livenessOut = StreamController<MeetingMediaLiveness>.broadcast();
  var _liveness = MeetingMediaLiveness.connecting;
  final _localTracks = <String, MediaStreamTrack>{};
  MediaStream? _micStream;
  MediaStream? _camStream;
  var _closed = false;

  static const _maxRemoteTracks = 64;
  var _remoteTrackCount = 0;

  @override
  Stream<MeetingRemoteTrack> get remoteTracks => _remote.stream;

  @override
  Stream<MeetingMediaLiveness> get liveness => _livenessOut.stream;

  @override
  MeetingMediaLiveness get currentLiveness => _liveness;

  void _onTrack(RTCTrackEvent event) {
    if (_closed) return;
    if (_remoteTrackCount >= _maxRemoteTracks) return;
    _remoteTrackCount++;
    final streamId = event.streams.isNotEmpty
        ? event.streams.first.id
        : event.track.id;
    _remote.add(_remoteTrackOf(event.track, streamId, active: true));
    event.track.onEnded = () {
      _remote.add(_remoteTrackOf(event.track, streamId, active: false));
    };
  }

  void _onRemoveStream(MediaStream stream) {
    for (final track in stream.getTracks()) {
      _remote.add(_remoteTrackOf(track, stream.id, active: false));
    }
  }

  MeetingRemoteTrack _remoteTrackOf(
    MediaStreamTrack track,
    String? msid, {
    required bool active,
  }) => MeetingRemoteTrack(
    track: MeetingTrack(
      id: track.id ?? '',
      kind: track.kind == 'audio'
          ? MeetingTrackKind.audio
          : MeetingTrackKind.video,
    ),
    msid: msid,
    active: active,
  );

  void _onIceState(RTCIceConnectionState state) {
    final next = switch (state) {
      RTCIceConnectionState.RTCIceConnectionStateConnected ||
      RTCIceConnectionState.RTCIceConnectionStateCompleted =>
        MeetingMediaLiveness.live,
      RTCIceConnectionState.RTCIceConnectionStateDisconnected =>
        MeetingMediaLiveness.disrupted,
      RTCIceConnectionState.RTCIceConnectionStateFailed =>
        MeetingMediaLiveness.dead,
      RTCIceConnectionState.RTCIceConnectionStateClosed =>
        MeetingMediaLiveness.closed,
      _ => MeetingMediaLiveness.connecting,
    };
    if (next == _liveness) return;
    _liveness = next;
    if (!_livenessOut.isClosed) _livenessOut.add(next);
  }

  /// Koppel een nieuwe lokale track aan de vaste transceiver. `addTrack`
  /// vult de eerste vrije sender van die soort — na het antwoord valt terug
  /// op `replaceTrack`, zodat er nooit een extra m-line ontstaat (Jitsi
  /// kent vaste contents: audio/video/data).
  Future<({String trackId, int? ssrc})?> _addLocal(
    String kind,
    Future<MediaStream> Function() acquire,
  ) async {
    if (_closed) return null;
    final MediaStream stream;
    try {
      stream = await acquire();
    } catch (e) {
      // Geen apparaat of permissie — eerlijk receive-only, nooit veinzen.
      logWarning('WebrtcConnection.addLocal($kind): geen device', e);
      return null;
    }
    final tracks = kind == 'audio'
        ? stream.getAudioTracks()
        : stream.getVideoTracks();
    if (tracks.isEmpty) return null;
    final track = tracks.first;
    try {
      if (_answered) {
        await (kind == 'audio' ? _audioTr : _videoTr).sender.replaceTrack(
          track,
        );
      } else {
        await _pc.addTrack(track, stream);
      }
    } catch (e) {
      logWarning('WebrtcConnection.addLocal($kind): koppelen faalde', e);
      return null;
    }
    _localTracks[track.id ?? ''] = track;
    return (trackId: track.id ?? '', ssrc: await _senderSsrc(kind));
  }

  /// De ssrc van de sender op onze transceiver — die meldt de adapter aan de
  /// focus via source-add.
  Future<int?> _senderSsrc(String kind) async {
    try {
      final sender = (kind == 'audio' ? _audioTr : _videoTr).sender;
      for (final enc
          in sender.parameters.encodings ?? const <RTCRtpEncoding>[]) {
        if (enc.ssrc != null) return enc.ssrc;
      }
    } on Exception catch (e) {
      logWarning('WebrtcConnection.senderSsrc', e);
    }
    return null;
  }

  var _answered = false;

  @override
  Future<({String trackId, int? ssrc})?> addLocalAudio() =>
      _addLocal('audio', () async {
        final s = await navigator.mediaDevices.getUserMedia(const {
          'audio': true,
          'video': false,
        });
        return _micStream = s;
      });

  @override
  Future<({String trackId, int? ssrc})?> addLocalVideo() =>
      _addLocal('video', () async {
        final s = await navigator.mediaDevices.getUserMedia(const {
          'audio': false,
          'video': {'width': 1280, 'height': 720},
        });
        return _camStream = s;
      });

  @override
  Future<void> setLocalTrackEnabled(
    String trackId, {
    required bool enabled,
  }) async {
    final track = _localTracks[trackId];
    if (track != null) track.enabled = enabled;
  }

  @override
  Future<void> applyRemoteOffer(String sdp) =>
      _pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));

  @override
  Future<String> completeAnswer() async {
    final answer = await _pc.createAnswer(const {});
    await _pc.setLocalDescription(answer);
    _answered = true;
    final sdp = answer.sdp;
    if (sdp == null) {
      throw StateError('libwebrtc gaf een antwoord zonder sdp');
    }
    return sdp;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    for (final track in _localTracks.values) {
      track.enabled = false;
      try {
        await track.stop();
      } on Exception catch (e) {
        logWarning('WebrtcConnection.close: track stoppen', e);
      }
    }
    _localTracks.clear();
    for (final stream in [_micStream, _camStream]) {
      try {
        await stream?.dispose();
      } on Exception catch (e) {
        logWarning('WebrtcConnection.close: stream afsluiten', e);
      }
    }
    _micStream = null;
    _camStream = null;
    try {
      await _pc.close();
    } on Exception catch (e) {
      logWarning('WebrtcConnection.close: pc sluiten', e);
    }
    if (!_remote.isClosed) await _remote.close();
    if (!_livenessOut.isClosed) await _livenessOut.close();
  }
}
