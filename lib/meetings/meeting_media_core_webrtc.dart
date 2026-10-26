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
import 'call_audio_source.dart';
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
    // Géén eigen transceivers vóór de offer: op deze binding associeert de
    // remote offer ze niet met de m-lines (die krijgen dan eigen recvonly-
    // transceivers en de onze staan wees, #2541). De offer maakt ze zelf;
    // `completeAnswer` zet hun richting op SendRecv vóór het antwoord.
    return _WebrtcConnection(pc);
  }

  @override
  Future<void> dispose() async {}
}

class _WebrtcConnection implements MeetingMediaConnection {
  _WebrtcConnection(this._pc) {
    _pc
      ..onTrack = _onTrack
      ..onRemoveStream = _onRemoveStream
      ..onIceConnectionState = _onIceState;
  }

  final RTCPeerConnection _pc;
  // De transceivers die de remote offer aanmaakte — gevuld in
  // `completeAnswer`, waar hun richting op SendRecv gaat (#2541).
  RTCRtpTransceiver? _audioTr;
  RTCRtpTransceiver? _videoTr;
  final _remote = StreamController<MeetingRemoteTrack>.broadcast();
  final _livenessOut = StreamController<MeetingMediaLiveness>.broadcast();
  final _localLostOut = StreamController<String>.broadcast();
  var _liveness = MeetingMediaLiveness.connecting;
  final _localTracks = <String, MediaStreamTrack>{};
  final _remoteStreams = <String, MediaStream>{};
  // Remote audiotracks voor de call-tap (#2527): de map is de snapshot bij
  // start; [_audioTapOut] meldt tracks die later bijkomen.
  final _remoteAudioTracks = <String, MediaStreamTrack>{};
  final _audioTapOut = StreamController<MediaStreamTrack>.broadcast();
  final _renderers = <RTCVideoRenderer>[];
  final _dataChannels = <_WebrtcDataChannel>[];
  MediaStream? _micStream;
  MediaStream? _camStream;
  String? _cameraTrackId;
  MediaStream? _screenStream;
  String? _screenTrackId;
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
    if (event.track.kind == 'audio' && event.track.id != null) {
      _remoteAudioTracks[event.track.id!] = event.track;
      _audioTapOut.add(event.track);
    }
    event.track.onEnded = () {
      _remoteAudioTracks.remove(event.track.id);
      _remote.add(_remoteTrackOf(event.track, active: false));
    };
  }

  void _onRemoveStream(MediaStream stream) {
    for (final track in stream.getTracks()) {
      _remoteStreams.remove(track.id);
      _remoteAudioTracks.remove(track.id);
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
    Future<MediaStream> Function() acquire, {
    bool attachToSender = true,
  }) async {
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
      final tr = kind == 'audio' ? _audioTr : _videoTr;
      // attachToSender=false: de camera aanzetten tijdens schermdelen mag
      // het scherm niet van de sender wippen — de track bestaat dan al en
      // komt bij het stoppen van delen vanzelf op de sender.
      if (tr != null && attachToSender) {
        await tr.sender.replaceTrack(track);
      } else if (tr == null) {
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
    final src = await _senderSource(kind);
    return src == null ? null : (src.ssrcs.isEmpty ? null : src.ssrcs.first);
  }

  /// De verzend-bron op één lezing, uit drie bronnen van steeds levensechter
  /// waarheid: `sender.parameters` (op web een live getter; in de native
  /// binding een creatie-cache — #2541), dan de `a=ssrc:`-regels uit de
  /// lokale SDP van het antwoord (de onderhandelde waarheid), dan de
  /// `outbound-rtp`-stats (de wire-waarheid ná replaceTrack mid-call —
  /// die ssrc staat in géén SDP). `sender.track` is de track die er NU op
  /// ligt: tijdens schermdelen is dat het scherm, niet de camera (#2537).
  Future<MeetingLocalSource?> _senderSource(String kind) async {
    final tr = kind == 'audio' ? _audioTr : _videoTr;
    final sender = tr?.sender;
    final track = sender?.track;
    // parameters is op web een live getter; de native binding bewaakt een
    // creatie-cache, dus een lege lijst is daar geen teken van "geen ssrc".
    if (sender != null && track != null) {
      final paramSsrcs = <int>[];
      try {
        for (final enc
            in sender.parameters.encodings ?? const <RTCRtpEncoding>[]) {
          final ssrc = enc.ssrc;
          if (ssrc != null && ssrc != 0) paramSsrcs.add(ssrc);
        }
      } on Exception catch (e) {
        logWarning('WebrtcConnection.senderSsrc', e);
      }
      if (paramSsrcs.isNotEmpty) {
        return MeetingLocalSource(
          msid: '${_sendStream(kind)?.id ?? ''} ${track.id ?? ''}'.trim(),
          ssrcs: paramSsrcs,
        );
      }
    }
    // addTrack op deze binding bindt niet altijd aan _audioTr/_videoTr —
    // sender.track kan dus null zijn terwijl de m-sectie wél een verzend-
    // ssrc kent. De a=ssrc-regels in het antwoord zijn de aankondig-waarheid.
    final fromSdp = await _sdpSource(kind);
    if (fromSdp != null) {
      return MeetingLocalSource(
        msid: fromSdp.msid.isNotEmpty ? fromSdp.msid : _localMsid(kind, track),
        ssrcs: fromSdp.ssrcs,
        fidPairs: fromSdp.fidPairs,
      );
    }
    // Een post-onderhandeling-ssrc (camera aan via replaceTrack) staat in
    // géén SDP — de wire-waarheid zit in de outbound-rtp stats.
    return _statsSource(kind, _localMsid(kind, track));
  }

  String _localMsid(String kind, MediaStreamTrack? track) =>
      '${_sendStream(kind)?.id ?? ''} ${track?.id ?? ''}'.trim();

  /// De `a=ssrc:`-, `a=ssrc-group:FID`- en `a=msid:`-regels uit de m-sectie
  /// van [kind] in de lokale SDP — de ssrc('s) die de andere kant in de
  /// source-add verwacht. Null zolang er geen antwoord of geen verzend-
  /// ssrc in die sectie staat (bijv. camera later pas gekoppeld).
  Future<MeetingLocalSource?> _sdpSource(String kind) async {
    final RTCSessionDescription? desc;
    try {
      desc = await _pc.getLocalDescription();
    } on Exception catch (e) {
      logWarning('WebrtcConnection.sdpSource', e);
      return null;
    }
    return meetingLocalSourceFromSdp(desc?.sdp, kind);
  }

  /// De ssrc waarop libwebrtc NU echt RTP stuurt — de `outbound-rtp`-stats
  /// van [kind]. Dit is de enige bron die een ssrc kent die pas ná de
  /// onderhandeling ontstond (camera aan via `replaceTrack`, #2541).
  Future<MeetingLocalSource?> _statsSource(String kind, String msid) async {
    try {
      for (final report in await _pc.getStats()) {
        // Nieuwe bindings rapporteren 'outbound-rtp'; de Darwin-binding
        // gebruikt het legacy `statisticsWithCompletionHandler` met type
        // 'ssrc' voor beide richtingen — 'bytesSent' markeert de zendkant
        // (#2541).
        final outbound =
            report.type == 'outbound-rtp' ||
            (report.type == 'ssrc' &&
                report.values.keys.any((k) => '$k'.endsWith('Sent')));
        if (!outbound) continue;
        final values = report.values;
        final mediaKind = values['mediaType'] ?? values['kind'];
        if (mediaKind != kind) continue;
        final ssrc = int.tryParse('${values['ssrc']}');
        if (ssrc != null && ssrc != 0) {
          return MeetingLocalSource(msid: msid, ssrcs: [ssrc]);
        }
      }
    } on Exception catch (e) {
      logWarning('WebrtcConnection.statsSource', e);
    }
    return null;
  }

  /// De stream die op de sender van [kind] ligt — tijdens schermdelen is
  /// de video-sender het scherm, dus levert de msid dan de schermstream.
  MediaStream? _sendStream(String kind) => kind == 'audio'
      ? _micStream
      : (_screenTrackId != null ? _screenStream : _camStream);

  @override
  Future<MeetingLocalSource?> localSource(
    String kind, {
    bool singleAttempt = false,
  }) async {
    if (_closed) return null;
    // libwebrtc wijst de verzend-ssrc pas toe zodra de track echt gaat
    // zenden — vlak na addTrack/replaceTrack kent geen van de drie
    // bronnen hem nog (#2541). Begrensd pollen; nooit oneindig wachten.
    for (var i = 0; i < (singleAttempt ? 1 : 40) && !_closed; i++) {
      final src = await _senderSource(kind);
      if (src != null) return src;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    logWarning(
      'WebrtcConnection.localSource($kind): geen ssrc na 4s',
      await _sourceDiagnostics(kind),
    );
    return null;
  }

  /// Wat de drie bronroutes zagen toen ze allemaal leeg bleven — de binding
  /// rapporteert ssrc's afwijkend per platform (#2541), dus de mislukking
  /// moet zichzelf kunnen verklaren zonder debugger.
  Future<String> _sourceDiagnostics(String kind) async {
    final parts = <String>[];
    try {
      final sdp = (await _pc.getLocalDescription())?.sdp;
      parts.add('sdp=${sdp == null ? 'null' : '${sdp.length}c'}');
      if (sdp != null) {
        var inSection = false;
        var ssrcLines = 0;
        final dirs = <String>[];
        for (final raw in sdp.split('\n')) {
          final line = raw.trim();
          if (line.startsWith('m=')) {
            inSection = line.startsWith('m=$kind ');
          } else if (inSection && line.startsWith('a=ssrc:')) {
            ssrcLines++;
          }
          if (line.startsWith('a=send') ||
              line.startsWith('a=recv') ||
              line.startsWith('a=inactive')) {
            dirs.add(line.substring(2));
          }
        }
        parts.add('ssrc-regels=$ssrcLines dir=[${dirs.join(',')}]');
      }
    } on Exception {
      parts.add('sdp-fout');
    }
    try {
      final tr = kind == 'audio' ? _audioTr : _videoTr;
      TransceiverDirection? dir, cur;
      try {
        dir = await tr?.getDirection();
        cur = await tr?.getCurrentDirection();
      } on Exception {
        // richting onleesbaar op deze binding — dan blijft null staan
      }
      parts.add('tr(mid=${tr?.mid} dir=$dir cur=$cur)');
      final all = await _pc.getTransceivers();
      parts.add(
        'transceivers=[${all.map((t) => '${t.mid}:${t.sender.track != null}').join(',')}]',
      );
    } on Exception {
      parts.add('tr-fout');
    }
    try {
      final types = <String>{};
      final mediaKeys = <String>{};
      for (final r in await _pc.getStats()) {
        types.add(r.type);
        if (r.type == 'ssrc' || r.type == 'outbound-rtp') {
          mediaKeys.addAll(r.values.keys.map((k) => '$k'));
        }
      }
      parts.add('stats=[${types.join(',')}]');
      if (mediaKeys.isNotEmpty) {
        parts.add('media-keys=[${mediaKeys.join(',')}]');
      }
    } on Exception {
      parts.add('stats-fout');
    }
    return parts.join(' ');
  }

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
  Future<({String trackId, int? ssrc})?> addLocalVideo({
    bool attachToSender = true,
  }) =>
      _addLocal('video', attachToSender: attachToSender, () async {
        final s = await navigator.mediaDevices.getUserMedia(const {
          'audio': false,
          'video': {'width': 1280, 'height': 720},
        });
        return _camStream = s;
      }).then((attached) {
        if (attached != null) _cameraTrackId = attached.trackId;
        return attached;
      });

  @override
  Future<List<MeetingScreenSource>> screenSources() async {
    // Web laat de browser zelf een kiezer zien — daar is geen eigen lijst.
    if (kIsWeb) return const [];
    try {
      return [
        for (final s in await desktopCapturer.getSources(
          types: const [SourceType.Screen, SourceType.Window],
          thumbnailSize: ThumbnailSize(240, 135),
        ))
          MeetingScreenSource(
            id: s.id,
            label: s.name,
            isWindow: s.type == SourceType.Window,
            thumbnail: s.thumbnail,
          ),
      ];
    } on Exception catch (e) {
      logWarning('WebrtcConnection.screenSources', e);
      return const [];
    }
  }

  @override
  Future<({String trackId, int? ssrc})?> addLocalScreen({
    String? sourceId,
  }) async {
    if (_closed) return null;
    final MediaStream stream;
    try {
      stream = await navigator.mediaDevices.getDisplayMedia(<String, dynamic>{
        'audio': false,
        'video': sourceId == null
            ? true // browser: de kiezer van de browser zelf
            : <String, Object>{
                // De bron uit onze eigen kiezer gaat mee als deviceId —
                // geen deviceId zou hier het hele scherm pakken.
                'deviceId': <String, Object>{'exact': sourceId},
                'mandatory': <String, Object>{
                  'frameRate': 15,
                  // Scherm en venster verschillen in resolutie; laat het OS
                  // de maat kiezen — een geforceerde 1280x720 levert een
                  // uitgerekt beeld op.
                },
              },
      });
    } on Exception catch (e) {
      // Geen toestemming, geen bron of de gebruiker annuleerde — allemaal
      // dezelfde eerlijke afloop: er deelt niets, de call blijft intact.
      logWarning('WebrtcConnection.addLocalScreen', e);
      return null;
    }
    final tracks = stream.getVideoTracks();
    if (tracks.isEmpty) {
      await stream.dispose();
      return null;
    }
    final track = tracks.first;
    try {
      // Altijd replaceTrack op de vaste video-transceiver: de m-line en de
      // aangekondigde bron <nick>-v0 blijven gelijk, alleen de inhoud
      // wisselt. Dat is hoe lib-jitsi-meet delen neerlegt — geen extra
      // m-line, geen nieuwe bron.
      await _videoTr?.sender.replaceTrack(track);
    } on Exception catch (e) {
      await track.stop();
      await stream.dispose();
      logWarning('WebrtcConnection.addLocalScreen: koppelen faalde', e);
      return null;
    }
    _screenStream = stream;
    _screenTrackId = track.id;
    _localTracks[track.id ?? ''] = track;
    track.onEnded = () {
      _localTracks.remove(track.id);
      // De share-velden blijven staan tot [stopScreenShare] opruimt — de
      // adapter hoort het verlies via localTrackLost en zet dan de camera
      // terug op de sender; zelf opruimen zou die terugzet overslaan.
      if (!_localLostOut.isClosed) _localLostOut.add(track.id ?? '');
    };
    return (trackId: track.id ?? '', ssrc: await _senderSsrc('video'));
  }

  @override
  Future<void> stopScreenShare() async {
    final trackId = _screenTrackId;
    final stream = _screenStream;
    if (trackId == null && stream == null) return;
    _screenTrackId = null;
    _screenStream = null;
    _localTracks.remove(trackId);
    // De camera terug op de sender als die track er nog is; anders
    // loskoppelen — een sender zonder track stuurt niets.
    final cam = _cameraTrackId == null ? null : _localTracks[_cameraTrackId];
    try {
      await _videoTr?.sender.replaceTrack(cam);
    } on Exception catch (e) {
      logWarning('WebrtcConnection.stopScreenShare: terugzetten faalde', e);
    }
    final track = stream?.getVideoTracks().firstOrNull;
    track?.onEnded = null;
    if (track != null) {
      try {
        await track.stop();
      } on Exception catch (e) {
        logWarning('WebrtcConnection.stopScreenShare: track', e);
      }
    }
    try {
      await stream?.dispose();
    } on Exception catch (e) {
      logWarning('WebrtcConnection.stopScreenShare: stream', e);
    }
  }

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
    // Remote stream, de schermdeel-stream voor de self-view, of de eigen
    // camerastream — allemaal op track-id. Onbekend/eindig → null, nooit een
    // nepvlak (#2535).
    final stream =
        _remoteStreams[trackId] ??
        (trackId == _screenTrackId ? _screenStream : null) ??
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

  @override
  CallAudioCaptureFact get callAudioCapture =>
      callAudioCaptureOfCurrentBinding();

  /// De hele-call-tap (#2527): een stroom taps — eerst de snapshot van de
  /// tracks die er nu zijn, daarna iedere remote audiotrack die later
  /// bijkomt. `openCallAudioCapture` voegt alleen tijdstip en bron toe.
  @override
  Stream<CallAudioChunk> startCallAudioCapture() =>
      openCallAudioCapture(callAudioCapture, _audioTaps());

  Stream<CallAudioTrackTap> _audioTaps() {
    // `seen` dedupt snapshot en live-stroom: een track die tijdens het
    // openen arriveert zit in allebei en mag maar één tap krijgen. De
    // broadcast-subscription staat synchroon in de multi-executor, dus er
    // is geen raam tussen snapshot en live waarin een track verloren gaat.
    final seen = <String>{};
    return Stream.multi((controller) async {
      for (final t in _localTracks.values) {
        if (t.kind == 'audio' && seen.add(t.id ?? '')) {
          controller.addSync(_tapOf(t, CallAudioRole.localOutbound));
        }
      }
      for (final t in _remoteAudioTracks.values) {
        if (seen.add(t.id ?? '')) {
          controller.addSync(_tapOf(t, CallAudioRole.remote));
        }
      }
      await controller.addStream(
        _audioTapOut.stream
            .where((t) => seen.add(t.id ?? ''))
            .map((t) => _tapOf(t, CallAudioRole.remote)),
      );
    });
  }

  /// Post-mute-contract van #2527: een uitgezette track levert géén frames.
  /// libwebrtc/Webaudio kan na `enabled=false` nog stilte sturen — die is
  /// opname-waardeloos en hoort niet in de stroom; de gebruiker ziet in de
  /// provider nog steeds `localMuted` als extra hek.
  CallAudioTrackTap _tapOf(MediaStreamTrack t, CallAudioRole role) =>
      CallAudioTrackTap(
        trackId: t.id ?? '',
        role: role,
        frames: audioTrackFrames(t)
            .where((f) => t.enabled)
            .map((f) => callPcmFrame16k(f.pcm, f.sampleRate, f.channels)),
      );

  @override
  Future<void> stopCallAudioCapture() async {}

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
  Future<void> applyRemoteOffer(String sdp) async {
    await _pc.setRemoteDescription(RTCSessionDescription(sdp, 'offer'));
    // De offer maakt zelf een transceiver per m-line — die staan standaard
    // op recvonly. Onze kant wil óók kunnen zenden: pak die geassocieerde
    // transceivers (niet-lege mid, de wezen raken nooit de wire) en zet
    // hun richting vóór het antwoord op SendRecv (#2541).
    for (final tr in await _pc.getTransceivers()) {
      if (tr.mid.isEmpty) continue;
      final kind = tr.receiver.track?.kind;
      if (kind == 'audio' && _audioTr == null) {
        _audioTr = tr;
      } else if (kind == 'video' && _videoTr == null) {
        _videoTr = tr;
      }
    }
    await _audioTr?.setDirection(TransceiverDirection.SendRecv);
    await _videoTr?.setDirection(TransceiverDirection.SendRecv);
  }

  @override
  Future<String> completeAnswer() async {
    final answer = await _pc.createAnswer(const {});
    await _pc.setLocalDescription(answer);
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
    for (final stream in [_micStream, _camStream, _screenStream]) {
      try {
        await stream?.dispose();
      } on Exception catch (e) {
        logWarning('WebrtcConnection.close: stream afsluiten', e);
      }
    }
    _micStream = null;
    _camStream = null;
    _screenStream = null;
    _cameraTrackId = null;
    _screenTrackId = null;
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

/// De eigen verzend-ssrc's, FID-paren en msid uit de m-sectie van [kind]
/// (`'audio'`/`'video'`) in een SDP — puur en dus los testbaar. Dit is de
/// onderhandelde waarheid die `localSource` nodig heeft: de gecachete
/// `sender.parameters` van de native binding kent die ssrc's niet (#2541).
/// Null zonder SDP of zonder verzend-ssrc in die sectie.
MeetingLocalSource? meetingLocalSourceFromSdp(String? sdp, String kind) {
  if (sdp == null) return null;
  var inSection = false;
  final ssrcs = <int>{};
  final fidPairs = <(int, int)>[];
  String? msid;
  for (final raw in sdp.split('\n')) {
    final line = raw.trim();
    if (line.startsWith('m=')) {
      inSection = line.startsWith('m=$kind ');
      continue;
    }
    if (!inSection) continue;
    if (line.startsWith('a=ssrc-group:FID ')) {
      final parts = line.substring('a=ssrc-group:FID '.length).split(' ');
      if (parts.length >= 2) {
        final media = int.tryParse(parts[0]);
        final rtx = int.tryParse(parts[1]);
        if (media != null && rtx != null) fidPairs.add((media, rtx));
      }
    } else if (line.startsWith('a=ssrc:')) {
      final v = int.tryParse(
        line.substring('a=ssrc:'.length).split(RegExp(r'\s')).first,
      );
      if (v != null && v != 0) ssrcs.add(v);
    } else if (line.startsWith('a=msid:')) {
      msid ??= line.substring('a=msid:'.length).trim();
    }
  }
  if (ssrcs.isEmpty) return null;
  return MeetingLocalSource(
    msid: msid ?? '',
    ssrcs: ssrcs.toList(),
    fidPairs: fidPairs,
  );
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
