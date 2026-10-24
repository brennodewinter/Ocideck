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
import 'package:logger/logger.dart';

import '../utils/log.dart';
import 'meeting_media_core.dart';
import 'meeting_participant.dart';
import 'meeting_provider.dart' show MeetingE2eeStatus;

/// The production [MeetingMediaCore]. No branching logic — only the libwebrtc
/// calls the seam promises.
class WebrtcMediaCore implements MeetingMediaCore {
  WebrtcMediaCore({TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform {
    // Pin het libwebrtc-logniveau (F3.4c-review, #2535): op 'error' komen SDP,
    // adressen en sleutelmateriaal niet in logs terecht, en de meldingen die er
    // wél zijn lopen via onze eigen logError — nooit via een default console
    // printer. De severity is een constante zodat een test de pin kan bewaken.
    Helper.setLogger(
      Logger(printer: SimplePrinter(), output: _OciWebrtcLogOutput()),
      webrtcLogSeverity,
    );
  }

  /// Het vastgezette libwebrtc-logniveau. Niet instelbaar maken: 'verbose' of
  /// 'info' zou volledige SDP en ICE-adressen in logs zetten.
  static const webrtcLogSeverity = 'error';

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
  final _localLostOut = StreamController<String>.broadcast();
  var _liveness = MeetingMediaLiveness.connecting;
  final _localTracks = <String, MediaStreamTrack>{};
  final _remoteStreams = <String, MediaStream>{};
  final _renderers = <RTCVideoRenderer>[];
  final _dataChannels = <_WebrtcDataChannel>[];
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
  Stream<String> get localTrackLost => _localLostOut.stream;

  @override
  MeetingMediaLiveness get currentLiveness => _liveness;

  void _onTrack(RTCTrackEvent event) {
    if (_closed) return;
    if (_remoteTrackCount >= _maxRemoteTracks) return;
    _remoteTrackCount++;
    // De stream bewaren we voor de renderer — een track zonder stream kan de
    // UI niet tonen (attachVideo geeft dan null, fail-closed).
    if (event.streams.isNotEmpty && event.track.id != null) {
      _remoteStreams[event.track.id!] = event.streams.first;
    }
    _remote.add(_remoteTrackOf(event.track, active: true));
    event.track.onEnded = () {
      _remote.add(_remoteTrackOf(event.track, active: false));
    };
  }

  void _onRemoveStream(MediaStream stream) {
    for (final track in stream.getTracks()) {
      _remoteStreams.remove(track.id);
      _remote.add(_remoteTrackOf(track, active: false));
    }
  }

  MeetingRemoteTrack _remoteTrackOf(
    MediaStreamTrack track, {
    required bool active,
  }) => MeetingRemoteTrack(
    track: MeetingTrack(
      id: track.id ?? '',
      kind: track.kind == 'audio'
          ? MeetingTrackKind.audio
          : MeetingTrackKind.video,
    ),
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
    // Bronverlies (mic/cam fysiek weg, permissie ingetrokken) meldt de track
    // zelf — de adapter zet daarna SourceInfo en de participant bij (#2535).
    track.onEnded = () {
      _localTracks.remove(track.id);
      if (!_localLostOut.isClosed) _localLostOut.add(track.id ?? '');
    };
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
        // Call-audio: echo-onderdrukking, ruisonderdrukking en gain-aansturing
        // zijn de verwerkingsdefaults die een vergadering verwacht (#2535).
        final s = await navigator.mediaDevices.getUserMedia(const {
          'audio': {
            'echoCancellation': true,
            'noiseSuppression': true,
            'autoGainControl': true,
          },
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
  Future<MeetingVideoSurface?> attachVideo(String trackId) async {
    if (_closed) return null;
    // Remote stream, of onze eigen camerastream voor de self-view — beide op
    // track-id. Onbekend/eindig → null, nooit een nepvlak (#2535).
    final stream =
        _remoteStreams[trackId] ??
        (_localTracks[trackId] != null && _localTracks[trackId]!.kind == 'video'
            ? _camStream
            : null);
    if (stream == null) return null;
    final renderer = RTCVideoRenderer();
    try {
      await renderer.initialize();
      renderer.srcObject = stream;
    } catch (e) {
      logWarning('WebrtcConnection.attachVideo', e);
      await renderer.dispose();
      return null;
    }
    _renderers.add(renderer);
    return _WebrtcVideoSurface(renderer);
  }

  @override
  Future<List<MeetingAudioOutput>> audioOutputs() async {
    try {
      final devices = await Helper.audiooutputs;
      return [
        for (final d in devices)
          MeetingAudioOutput(id: d.deviceId, label: d.label),
      ];
    } on Exception catch (e) {
      logWarning('WebrtcConnection.audioOutputs', e);
      return const [];
    }
  }

  @override
  Future<void> selectAudioOutput(String deviceId) async {
    try {
      await Helper.selectAudioOutput(deviceId);
    } on Exception catch (e) {
      // Best-effort: platform zonder audio-outputkeuze → OS-default geldt.
      logWarning('WebrtcConnection.selectAudioOutput', e);
    }
  }

  /// Het kanaal wordt aangemaakt zodra de pc bestaat; libwebrtc opent het
  /// zodra DTLS/SCTP staat. De adapter mag dit dus vóór ICE-live aanroepen.
  /// 15s begrensd — een channel die nooit opent betekent een kapot
  /// mediapad, en de caller mag dan eerlijk falen i.p.v. eeuwig hangen.
  @override
  Future<MeetingDataChannel> openDataChannel(String label) async {
    if (_closed) throw StateError('connection gesloten');
    final channel = _WebrtcDataChannel(
      await _pc.createDataChannel(label, RTCDataChannelInit()),
    );
    _dataChannels.add(channel);
    await channel.opened.timeout(const Duration(seconds: 15));
    return channel;
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
    _remoteStreams.clear();
    for (final renderer in _renderers) {
      try {
        await renderer.dispose();
      } on Exception catch (e) {
        logWarning('WebrtcConnection.close: renderer', e);
      }
    }
    _renderers.clear();
    for (final channel in _dataChannels) {
      await channel.close();
    }
    _dataChannels.clear();
    try {
      await _pc.close();
    } on Exception catch (e) {
      logWarning('WebrtcConnection.close: pc sluiten', e);
    }
    if (!_remote.isClosed) await _remote.close();
    if (!_livenessOut.isClosed) await _livenessOut.close();
    if (!_localLostOut.isClosed) await _localLostOut.close();
  }
}

/// De echte texture die [attachVideo] teruggeeft — beheert één
/// `RTCVideoRenderer`; de UI rendert `Texture(textureId: …)`.
class _WebrtcVideoSurface implements MeetingVideoSurface {
  _WebrtcVideoSurface(this._renderer);

  final RTCVideoRenderer _renderer;
  var _disposed = false;

  @override
  int get textureId => _renderer.textureId ?? -1;

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _renderer.dispose();
    } on Exception catch (e) {
      logWarning('WebrtcVideoSurface.dispose', e);
    }
  }
}

/// Eén SCTP-datachannel — bij Jitsi de EndpointMessageTransport waarover
/// de bridge-messages lopen. Alleen tekst: een binair frame is hier geen
/// protocol en wordt genegeerd.
class _WebrtcDataChannel implements MeetingDataChannel {
  _WebrtcDataChannel(this._channel) {
    _channel.onDataChannelState = (state) {
      if (_opened.isCompleted) return;
      switch (state) {
        case RTCDataChannelState.RTCDataChannelOpen:
          _opened.complete();
        case RTCDataChannelState.RTCDataChannelClosing ||
            RTCDataChannelState.RTCDataChannelClosed:
          _opened.completeError(StateError('datachannel sloot voor open'));
        default:
          break;
      }
    };
    _channel.onMessage = (msg) {
      if (!msg.isBinary && !_messages.isClosed) _messages.add(msg.text);
    };
  }

  final RTCDataChannel _channel;
  final _messages = StreamController<String>.broadcast();
  final _opened = Completer<void>();
  var _closed = false;

  /// Resolves zodra het kanaal echt open staat — [openDataChannel] wacht
  /// hierop, begrensd.
  Future<void> get opened => _opened.future;

  @override
  Stream<String> get messages => _messages.stream;

  @override
  Future<void> send(String text) => _channel.send(RTCDataChannelMessage(text));

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    try {
      await _channel.close();
    } on Exception catch (e) {
      logWarning('WebrtcDataChannel.close', e);
    }
    if (!_messages.isClosed) await _messages.close();
  }
}

/// libwebrtc-meldingen (severity 'error') gaan via de eigen log-pipeline —
/// nooit via een console-printer waar SDP of adressen kunnen belanden (#2535).
class _OciWebrtcLogOutput extends LogOutput {
  @override
  void output(OutputEvent event) {
    for (final line in event.lines) {
      logWarning('libwebrtc', line);
    }
  }
}
