// The live Jitsi session (#2534): conference-IQ → MUC-join → Jingle
// session-initiate/accept → ICE naar de JVB, dan roster + mute + chat live.
// De volgorde komt van de echte wire (stable-11248 testbed-capture), niet uit
// documentatie:
//
//   1. `<iq set to=focus.<domain>><conference room='r@muc'/>` — Jicofo wijst de
//      kamer toe (`ready='true'`) of weigert getypeerd (`not-authorized` =
//      deze JID mag niet binnen → accountRequired);
//   2. MUC-join op `room@muc/<unieke-nick>` met de presence-extensies
//      (`<nick>` voor de displaynaam, `SourceInfo` — de mute-kaart);
//   3. de focus stuurt `session-initiate` — het mediapad wordt opgebouwd uit
//      de SDP-offer die we daaruit synthetiseren ([jingleOfferToSdp]);
//   4. `session-accept` terug met onze onderhandelde inhoud; eigen bronnen
//      volgen via `source-add` (`<nick>-a0`/`-v0`) en een verse presence;
//   5. pas als ICE `live` meldt bestaat een mediapad → `connected`. Alles
//      daarvoor of daarna fout is fail-closed: nooit een "verbonden" call
//      zonder werkend mediapad (het acceptatiecriterium).
//
// Deze klasse spreekt XMPP via [XmppStanzaChannel] — de tests drijven hem met
// een gescripte fake-channel, de app met een echte `XmppSession` (die zelf de
// transport-reconnect + `onRejoin`-callback aanbiedt; [rejoin] bouwt de kamer
// opnieuw op over hetzelfde kanaal).

import 'dart:async';
import 'dart:math';

import 'package:xml/xml.dart';

import '../../../l10n/app_localizations.dart';
import '../../../xmpp/xmpp_muc.dart';
import '../../../xmpp/xmpp_session.dart' show XmppStanzaChannel;
import '../../../xmpp/xmpp_stanza.dart';
import '../../meeting_event.dart';
import '../../meeting_media_core.dart';
import '../../meeting_nick.dart';
import '../../meeting_participant.dart';
import '../../meeting_provider.dart';
import 'jitsi_sdp.dart';
import 'jitsi_signaling.dart';

/// Één actieve Jitsi-vergadering. Gemaakt via [JitsiMeetingSession.start];
/// die werpt [MeetingJoinException] bij elke mislukte stap vóór `connected` —
/// een geretourneerde sessie heeft dus altijd een mediapad.
class JitsiMeetingSession implements MeetingSession {
  JitsiMeetingSession._(
    this._channel,
    this._mediaCore,
    this._closeSession,
    this._nick, {
    required this.roomJid,
    required this.focusJid,
    required this.displayName,
    required this.startMuted,
    required this.startCameraOff,
    String Function()? nickFactory,
    this.conferenceTimeout = const Duration(seconds: 15),
    this.initiateTimeout = const Duration(seconds: 20),
    this.iceTimeout = const Duration(seconds: 20),
    this.mucTimeout = const Duration(seconds: 20),
  }) : _nickFactory = nickFactory ?? uniqueMeetingNick;

  /// De volledige join. Geeft een live sessie of werpt [MeetingJoinException];
  /// bij elke mislukte stap is alles alweer opgeruimd (geen half-open sessies).
  static Future<JitsiMeetingSession> start({
    required XmppStanzaChannel channel,
    required MeetingMediaCore mediaCore,
    required String roomJid,
    required String focusJid,
    required String displayName,
    required bool startMuted,
    required bool startCameraOff,
    required Future<void> Function() closeSession,
    String Function()? nickFactory,
    Duration conferenceTimeout = const Duration(seconds: 15),
    Duration initiateTimeout = const Duration(seconds: 20),
    Duration iceTimeout = const Duration(seconds: 20),
    Duration mucTimeout = const Duration(seconds: 20),
  }) async {
    final session = JitsiMeetingSession._(
      channel,
      mediaCore,
      closeSession,
      (nickFactory ?? uniqueMeetingNick)(),
      roomJid: roomJid,
      focusJid: focusJid,
      displayName: displayName,
      startMuted: startMuted,
      startCameraOff: startCameraOff,
      nickFactory: nickFactory,
      conferenceTimeout: conferenceTimeout,
      initiateTimeout: initiateTimeout,
      iceTimeout: iceTimeout,
      mucTimeout: mucTimeout,
    );
    try {
      await session._join();
      return session;
    } on MeetingJoinException {
      await session._teardown(silent: true);
      rethrow;
    } catch (e) {
      await session._teardown(silent: true);
      throw MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        e.toString(),
      );
    }
  }

  final XmppStanzaChannel _channel;
  final MeetingMediaCore _mediaCore;
  final String roomJid;
  final String focusJid;
  String _nick;
  final String displayName;
  final bool startMuted;
  final bool startCameraOff;
  final String Function() _nickFactory;
  final Future<void> Function() _closeSession;
  final Duration conferenceTimeout;
  final Duration initiateTimeout;
  final Duration iceTimeout;
  final Duration mucTimeout;

  final _events = StreamController<MeetingEvent>.broadcast();
  final _participants = <String, MeetingParticipant>{};
  StreamSubscription<Stanza>? _stanzas;
  StreamSubscription<List<MucOccupant>>? _roster;
  StreamSubscription<MeetingRemoteTrack>? _remoteTracks;
  StreamSubscription<MeetingMediaLiveness>? _livenessSub;
  XmppMuc? _muc;
  MeetingMediaConnection? _media;
  JingleSessionInitiate? _initiate;
  MeetingConnectionState _state = MeetingConnectionState.idle;
  var _left = false;
  var _micEnabled = true;
  var _iqSeq = 0;
  String? _audioTrackId;
  String? _videoTrackId;
  int? _audioSsrc;
  int? _videoSsrc;
  Completer<JingleSessionInitiate>? _initiateCompleter;
  Timer? _initiateTimer;

  /// Een initiate die vóór [_awaitInitiate] binnenkwam — de focus hoeft niet
  /// te wachten tot wij luisteren; zonder deze buffer gaat hij verloren.
  JingleSessionInitiate? _pendingInitiate;

  /// Het room-occupant JID van de focus — op de wire gaan alle jingle-IQ's
  /// hierheen (`room@muc/focus`), niet naar `focus@auth.<domain>`.
  String get _focusInRoom => '$roomJid/focus';

  // ── MeetingSession ────────────────────────────────────────────────────────

  @override
  String get providerId => 'jitsi';

  @override
  Stream<MeetingEvent> get events => _events.stream;

  @override
  MeetingConnectionState get connectionState => _state;

  @override
  MeetingRole get localRole =>
      _participants[_nick]?.role ?? MeetingRole.attendee;

  @override
  List<MeetingParticipant> get participants =>
      List.unmodifiable(_participants.values);

  @override
  MeetingCapabilities get capabilities => const MeetingCapabilities(
    // Controls die de gebruiker mag zien; of een track ook echt komt hangt aan
    // het apparaat en staat in micMuted/camOff/participant.tracks — die twee
    // feiten houden we strikt gescheiden (nooit een track veinzen).
    audio: true,
    video: true,
    screenShare: false, // schermdelen komt in een volgende slice (#2535+)
    chat: true,
    roster: true,
  );

  @override
  Future<void> setMicrophone({required bool enabled}) =>
      _setLocalMedia(kind: 'audio', enabled: enabled);

  @override
  Future<void> setCamera({required bool enabled}) =>
      _setLocalMedia(kind: 'video', enabled: enabled);

  @override
  Future<void> startScreenShare() async {
    _emit(
      MeetingErrorEvent(
        message: AppLocalizations.active.d(
          'Scherm delen is nog niet beschikbaar.',
        ),
      ),
    );
  }

  @override
  Future<void> stopScreenShare() async {}

  @override
  Future<void> sendChat(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > _maxChatLength || _left) return;
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.message,
        type: 'groupchat',
        to: roomJid,
        children: [
          xmppElement('body', text: trimmed),
          xmppElement('nick', namespace: jitsiNickNs, text: displayName),
        ],
      ),
    );
  }

  @override
  Future<void> leave() => _teardown();

  // ── join-sequentie ────────────────────────────────────────────────────────

  Future<void> _join() async {
    _setConnection(MeetingConnectionState.connecting);
    _stanzas = _channel.stanzas.listen(
      _onStanza,
      onDone: () => unawaited(_sessionDropped()),
    );

    // Stap 1: de kamer aanmelden bij de focus-component.
    await _conferenceRequest();

    // Stap 2: de MUC betreden met onze presence-extensies.
    await _joinMuc();

    // Stap 3+4: session-initiate → offer → antwoord → accept.
    _initiate = await _awaitInitiate();
    await _negotiateMedia(_initiate!);

    // Stap 5: eigen bronnen aankondigen (wire-volgorde: presence, dan
    // source-add per bron).
    await _sendPresenceUpdate();
    await _announceNewSource('audio');
    await _announceNewSource('video');

    // Stap 6: mediapad-bewijs — pas live ICE betekent "connected".
    await _awaitMediaLive();

    _roster = _muc!.occupants.listen(_onRoster);
    _remoteTracks = _media!.remoteTracks.listen(_onRemoteTrack);
    _livenessSub = _media!.liveness.listen(_onLiveness);
    _participants[_nick] = MeetingParticipant(
      id: _nick,
      displayName: displayName,
      role: _localRoleFromMuc(),
      isLocal: true,
      micMuted: _audioTrackId == null || startMuted,
      camOff: _videoTrackId == null || startCameraOff,
    );
    _setConnection(MeetingConnectionState.connected);
  }

  /// lib-jitsi-meet's device-id voor de conference-IQ — eenmalig per sessie
  /// en hergebruikt bij een rejoin, zodat jicofo hetzelfde apparaat ziet.
  final _machineUid = _newMachineUid();

  /// De conference-IQ: `<iq set to=focusJid><conference …/></iq>` →
  /// `<conference ready='true' …>` of een getypeerde weigering.
  Future<void> _conferenceRequest() async {
    final id = _nextIqId();
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.iq,
        to: focusJid,
        id: id,
        type: 'set',
        children: [buildConferenceRequest(roomJid, _machineUid)],
      ),
    );
    final reply = await _awaitIq(id, conferenceTimeout);
    if (reply.type == 'error') {
      final condition = _errorCondition(reply);
      // Een anonieme gast mag op veel deployments geen kamer ALLOceren
      // (`not-authorized` — exact wat de testbed-gast op de wire kreeg), maar
      // mag een bestaande kamer wél binnen: de MUC-join en de focus-invite
      // beslissen dan. Doorgaan dus; als niemand de kamer opent, kapt de
      // session-initiate-timeout de join alsnog eerlijk af.
      if (condition != 'not-authorized') {
        throw MeetingJoinException(
          MeetingFailureReason.providerUnavailable,
          'conference: $condition',
        );
      }
      return;
    }
    final el = reply.children.isNotEmpty ? reply.children.first : null;
    final ready = el == null ? null : parseConferenceReply(el);
    if (ready == null) {
      throw const MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        'conference: geen ready',
      );
    }
  }

  Future<void> _joinMuc() async {
    var nick = _nick;
    for (var attempt = 0; attempt < 2; attempt++) {
      _muc = XmppMuc(
        channel: _channel,
        roomJid: roomJid,
        nick: nick,
        timeout: mucTimeout,
      );
      final result = await _muc!.join(
        presenceExtensions: _presenceExtensions(const {}),
      );
      if (result.ok) {
        _nick = nick;
        return;
      }
      // Eén nickbotsing = verse nick en nog één poging (unieke nicks maken
      // dit zeldzaam, maar de MUC beslist — nooit aannemen).
      if (result.failure == MucJoinFailure.nickConflict && attempt == 0) {
        nick = _nickFactory();
        continue;
      }
      throw MeetingJoinException(
        _mapMucFailure(result.failure!),
        'muc: ${result.failure!.name}',
      );
    }
  }

  /// De presence-extensies op een (her)join of update: displaynaam + de
  /// SourceInfo-kaart. `<x xmlns='…/muc'>` plaatst XmppMuc zelf vooraan.
  List<XmlElement> _presenceExtensions(Map<String, bool> mutedBySource) => [
    xmppElement('nick', namespace: jitsiNickNs, text: displayName),
    xmppElement('SourceInfo', text: buildSourceInfo(mutedBySource)),
  ];

  Future<JingleSessionInitiate> _awaitInitiate() {
    final completer = _initiateCompleter = Completer<JingleSessionInitiate>();
    final pending = _pendingInitiate;
    if (pending != null) {
      _pendingInitiate = null;
      completer.complete(pending);
      return completer.future;
    }
    _initiateTimer = Timer(initiateTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          const MeetingJoinException(
            MeetingFailureReason.providerUnavailable,
            'geen session-initiate',
          ),
        );
      }
    });
    return completer.future;
  }

  Future<void> _negotiateMedia(JingleSessionInitiate initiate) async {
    try {
      _media = await _mediaCore.openConnection();
    } catch (e) {
      throw MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        'media: $e',
      );
    }
    // De echte client koppelt de mic ook bij een gemuteerde join — een
    // gemuteerde track met muted:true in SourceInfo. Geen device →
    // receive-only, en SourceInfo meldt dan eerlijk géén bron.
    await _attachLocal('audio');
    if (!startCameraOff) await _attachLocal('video');

    try {
      await _media!.applyRemoteOffer(jingleOfferToSdp(initiate));
      final answerSdp = await _media!.completeAnswer();
      final answer = parseSdpAnswer(answerSdp);
      final accept = buildSessionAccept(
        sid: initiate.sid,
        initiator: initiate.initiator,
        responder: _channel.boundJid ?? _nick,
        contents: sdpAnswerToJingle(answer),
        bundleContents: initiate.bundleContents,
      );
      final id = _nextIqId();
      _channel.sendStanza(
        Stanza(
          kind: StanzaKind.iq,
          to: _focusInRoom,
          id: id,
          type: 'set',
          children: [accept],
        ),
      );
      final reply = await _awaitIq(id, initiateTimeout);
      if (reply.type == 'error') {
        throw MeetingJoinException(
          MeetingFailureReason.providerUnavailable,
          'accept: ${_errorCondition(reply)}',
        );
      }
    } on JitsiContractException catch (e) {
      throw MeetingJoinException(
        MeetingFailureReason.meetingTypeUnsupported,
        e.toString(),
      );
    } on FormatException catch (e) {
      throw MeetingJoinException(
        MeetingFailureReason.meetingTypeUnsupported,
        'sdp: ${e.message}',
      );
    }
  }

  /// Een lokale track koppelen (mic/camera). Null bij geen device = eerlijk
  /// receive-only; de track-id/ssrc worden bewaard voor SourceInfo+source-add.
  Future<void> _attachLocal(String kind) async {
    final attached = kind == 'audio'
        ? await _media!.addLocalAudio()
        : await _media!.addLocalVideo();
    if (attached == null) return;
    if (kind == 'audio') {
      _audioTrackId = attached.trackId;
      _audioSsrc = attached.ssrc;
      _micEnabled = !startMuted;
      await _media!.setLocalTrackEnabled(
        attached.trackId,
        enabled: !startMuted,
      );
    } else {
      _videoTrackId = attached.trackId;
      _videoSsrc = attached.ssrc;
    }
  }

  /// Presence met de actuele SourceInfo-kaart (onze mute-waarheid op de
  /// wire) — verstuurd na de accept en na elke mute-wijziging.
  Future<void> _sendPresenceUpdate() async {
    final muted = <String, bool>{
      if (_audioTrackId != null) '$_nick-a0': !_micEnabled,
      if (_videoTrackId != null) '$_nick-v0': false,
    };
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.presence,
        to: '$roomJid/$_nick',
        children: _presenceExtensions(muted),
      ),
    );
  }

  /// Een bron aankondigen bij de focus, als de ssrc bekend is.
  Future<void> _announceNewSource(String kind) async {
    final initiate = _initiate;
    final ssrc = kind == 'audio' ? _audioSsrc : _videoSsrc;
    if (initiate == null || ssrc == null) return;
    _channel.sendStanza(
      Stanza(
        kind: StanzaKind.iq,
        to: _focusInRoom,
        id: _nextIqId(),
        type: 'set',
        children: [
          buildSourceAdd(
            sid: initiate.sid,
            initiator: initiate.initiator,
            contentName: kind,
            media: kind,
            sourceName: '$_nick-${kind[0]}0',
            ssrc: '$ssrc',
          ),
        ],
      ),
    );
    // De ack is best-effort: de MUC reflecteert ons sowieso terug, en een
    // verloren source-add herstelt via de volgende presence.
  }

  Future<void> _awaitMediaLive() async {
    if (_media!.currentLiveness == MeetingMediaLiveness.live) return;
    try {
      await _media!.liveness
          .firstWhere((l) => l == MeetingMediaLiveness.live)
          .timeout(iceTimeout);
    } on TimeoutException {
      throw const MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        'geen mediapad (ICE-timeout)',
      );
    }
  }

  /// Rejoin na een transport-reconnect van de `XmppSession` — die belt dit
  /// als `onRejoin`. De kamer opnieuw opbouwen over hetzelfde kanaal:
  /// conference-IQ + MUC-join + een verse session-initiate afwachten. `false`
  /// = de rejoin mislukte, de sessie probeert opnieuw met backoff.
  Future<bool> rejoin() async {
    if (_left) return false;
    _setConnection(MeetingConnectionState.reconnecting);
    try {
      await _conferenceRequest();
      await _joinMuc();
      // De media-onderhandeling herhaalt vanzelf: Jicofo stuurt een nieuwe
      // session-initiate voor de nieuwe occupant.
      final initiate = await _awaitInitiate();
      _initiate = initiate;
      await _media?.close();
      await _negotiateMedia(initiate);
      await _sendPresenceUpdate();
      await _announceNewSource('audio');
      await _announceNewSource('video');
      await _awaitMediaLive();
      _setConnection(MeetingConnectionState.connected);
      return true;
    } on MeetingJoinException {
      return false;
    } on Object {
      return false;
    }
  }

  // ── inkomende stanzas ─────────────────────────────────────────────────────

  void _onStanza(Stanza stanza) {
    switch (stanza.kind) {
      case StanzaKind.iq:
        _onIq(stanza);
      case StanzaKind.message:
        _onMessage(stanza);
      case StanzaKind.presence:
        break; // presence verwerkt XmppMuc → de roster-stream
    }
  }

  void _onIq(Stanza stanza) {
    final jingle = jingleElementOf(stanza.children);
    if (jingle == null) return;
    final action = jingleActionOf(jingle);
    if (action == null) return;
    final (name, sid) = action;
    if (_initiate != null &&
        sid != _initiate!.sid &&
        name != 'session-initiate') {
      return; // jingle van een andere sessie
    }
    // Elke set-IQ moet een result-ack krijgen (RFC 6120).
    void ack() {
      if (stanza.type == 'set' && stanza.id != null) {
        _channel.sendStanza(
          Stanza(
            kind: StanzaKind.iq,
            to: stanza.from,
            id: stanza.id,
            type: 'result',
          ),
        );
      }
    }

    switch (name) {
      case 'session-initiate':
        ack();
        final completer = _initiateCompleter;
        _initiateTimer?.cancel();
        if (completer != null && !completer.isCompleted) {
          try {
            completer.complete(parseSessionInitiate(jingle));
          } on JitsiContractException catch (e) {
            completer.completeError(
              MeetingJoinException(
                MeetingFailureReason.meetingTypeUnsupported,
                e.toString(),
              ),
            );
          }
        } else {
          // Te vroeg voor de await — bewaren; [_awaitInitiate] pikt hem op.
          try {
            _pendingInitiate = parseSessionInitiate(jingle);
          } on JitsiContractException {
            // Een kapot contract zonder wachter hoeven we niet te bewaren.
          }
        }
      case 'session-terminate':
        ack();
        unawaited(_remoteTerminated());
      case 'source-add' ||
          'source-remove' ||
          'transport-info' ||
          'session-info':
        // Bronnen van anderen lopen in deze deployment via presence-
        // SourceInfo, niet via jingle; transport-info dragen onze
        // ICE-kandidaten niet (de JVB leert die peer-reflexive).
        ack();
    }
  }

  void _onMessage(Stanza stanza) {
    if (stanza.type != 'groupchat' || stanza.from == null) return;
    final from = stanza.from!;
    if (!from.startsWith('$roomJid/')) return;
    final nick = from.substring(roomJid.length + 1);
    if (nick == _nick || nick.isEmpty || nick == 'focus') return;
    final body = stanza.child('body')?.innerText.trim() ?? '';
    if (body.isEmpty || body.length > _maxChatLength) return;
    _emit(ChatReceived(participantId: nick, text: body));
  }

  // ── roster → participants ─────────────────────────────────────────────────

  void _onRoster(List<MucOccupant> occupants) {
    final seen = <String>{};
    for (final occ in occupants) {
      if (occ.nick == 'focus') continue;
      seen.add(occ.nick);
      if (occ.isSelf) {
        final local = _participants[_nick];
        if (local == null) continue;
        final role = _roleOf(occ);
        if (role != local.role) {
          final next = local.copyWith(role: role);
          _participants[_nick] = next;
          _emit(ParticipantUpdated(next));
        }
        continue;
      }
      final parsed = _participantOf(occ);
      final existing = _participants[occ.nick];
      if (existing == null) {
        _participants[occ.nick] = parsed;
        _emit(ParticipantJoined(parsed));
      } else if (_differs(existing, parsed)) {
        // Tracks behouden: die komen via de media-laag, niet via presence.
        _participants[occ.nick] = _participantWithTracks(
          parsed,
          audio: existing.audio,
          video: existing.video,
        );
        _emit(ParticipantUpdated(_participants[occ.nick]!));
      }
    }
    for (final id in _participants.keys.toList()) {
      if (id == _nick || seen.contains(id)) continue;
      _participants.remove(id);
      _emit(ParticipantLeft(id));
    }
  }

  MeetingParticipant _participantOf(MucOccupant occ) {
    var display = occ.nick;
    var micMuted = true;
    var camOff = true;
    for (final ext in occ.extensions) {
      switch (ext.name.local) {
        case 'nick':
          if ((ext.getAttribute('xmlns') ?? ext.name.namespaceUri) ==
              jitsiNickNs) {
            final v = ext.innerText.trim();
            if (v.isNotEmpty && v.length <= 128) display = v;
          }
        case 'SourceInfo':
          final muted = parseSourceInfo(ext.innerText);
          final a = muted['${occ.nick}-a0'];
          final v = muted['${occ.nick}-v0'];
          if (a != null) micMuted = a;
          if (v != null) camOff = v;
      }
    }
    return MeetingParticipant(
      id: occ.nick,
      displayName: display,
      role: _roleOf(occ),
      micMuted: micMuted,
      camOff: camOff,
    );
  }

  MeetingRole _roleOf(MucOccupant occ) => switch (occ.role) {
    MucRole.moderator => MeetingRole.moderator,
    MucRole.participant => MeetingRole.attendee,
    MucRole.visitor => MeetingRole.guest,
    MucRole.none => MeetingRole.unknown,
  };

  MeetingRole _localRoleFromMuc() {
    for (final occ in _muc?.roster ?? const <MucOccupant>[]) {
      if (occ.isSelf) return _roleOf(occ);
    }
    return MeetingRole.attendee;
  }

  bool _differs(MeetingParticipant a, MeetingParticipant b) =>
      a.displayName != b.displayName ||
      a.role != b.role ||
      a.micMuted != b.micMuted ||
      a.camOff != b.camOff;

  /// Tracks zijn niet `copyWith`-baar (null betekent "houden") — bouw expliciet.
  MeetingParticipant _participantWithTracks(
    MeetingParticipant p, {
    MeetingTrack? audio,
    MeetingTrack? video,
  }) => MeetingParticipant(
    id: p.id,
    displayName: p.displayName,
    role: p.role,
    isLocal: p.isLocal,
    micMuted: p.micMuted,
    camOff: p.camOff,
    isDominantSpeaker: p.isDominantSpeaker,
    isScreenShare: p.isScreenShare,
    audio: audio,
    video: video,
  );

  // ── remote tracks → participant-tegels ────────────────────────────────────

  void _onRemoteTrack(MeetingRemoteTrack remote) {
    // Jitsi-sourcenamen: '<nick>-a0' / '<nick>-v0'. Zonder herleidbare naam
    // schrijven we de track NOOIT aan een participant toe — eerder geen tegel
    // dan een verzonnen eigenaar.
    final msid = remote.msid ?? remote.track.id;
    final dash = msid.indexOf('-');
    if (dash <= 0) return; // jvb-* sources zijn geen participant
    final nick = msid.substring(0, dash);
    final participant = _participants[nick];
    if (participant == null) return;
    final isAudio = remote.track.kind == MeetingTrackKind.audio;
    final next = remote.active ? remote.track : null;
    if ((isAudio ? participant.audio : participant.video)?.id == next?.id) {
      return;
    }
    final updated = _participantWithTracks(
      participant,
      audio: isAudio ? next : participant.audio,
      video: isAudio ? participant.video : next,
    );
    _participants[nick] = updated;
    _emit(ParticipantUpdated(updated));
  }

  // ── liveness / einde ──────────────────────────────────────────────────────

  void _onLiveness(MeetingMediaLiveness liveness) {
    if (_left) return;
    switch (liveness) {
      case MeetingMediaLiveness.disrupted:
        _setConnection(MeetingConnectionState.reconnecting);
      case MeetingMediaLiveness.live:
        if (_state == MeetingConnectionState.reconnecting) {
          _setConnection(MeetingConnectionState.connected);
        }
      case MeetingMediaLiveness.dead:
        unawaited(
          _terminalError(
            AppLocalizations.active.d('De mediaverbinding is weggevallen.'),
          ),
        );
      case MeetingMediaLiveness.connecting || MeetingMediaLiveness.closed:
        break;
    }
  }

  /// De remote side hing op of de server beëindigde de sessie.
  Future<void> _remoteTerminated() async {
    if (_left) return;
    await _teardown();
  }

  Future<void> _sessionDropped() async {
    if (_left) return;
    _setConnection(MeetingConnectionState.failed);
    _emit(
      MeetingErrorEvent(
        message: AppLocalizations.active.d('De verbinding is verbroken.'),
        terminal: true,
      ),
    );
    await _teardown(silent: true);
  }

  Future<void> _terminalError(String message) async {
    if (_left) return;
    _setConnection(MeetingConnectionState.failed);
    _emit(MeetingErrorEvent(message: message, terminal: true));
    await _teardown(silent: true);
  }

  /// Alles afbreken. Idempotent; [silent] = geen stanzas meer sturen (bij een
  /// gevallen sessie of een gefaalde join is zenden zinloos of onmogelijk).
  Future<void> _teardown({bool silent = false}) async {
    if (_left) return;
    _left = true;
    _initiateTimer?.cancel();
    _initiateCompleter = null;
    if (!silent && _initiate != null) {
      _channel.sendStanza(
        Stanza(
          kind: StanzaKind.iq,
          to: _focusInRoom,
          id: _nextIqId(),
          type: 'set',
          children: [buildSessionTerminate(sid: _initiate!.sid)],
        ),
      );
    }
    await _roster?.cancel();
    await _remoteTracks?.cancel();
    await _livenessSub?.cancel();
    await _muc?.leave();
    await _media?.close();
    await _stanzas?.cancel();
    await _closeSession();
    if (!silent) _setConnection(MeetingConnectionState.disconnected);
    if (!_events.isClosed) await _events.close();
  }

  // ── lokale media aan/uit ──────────────────────────────────────────────────

  Future<void> _setLocalMedia({
    required String kind,
    required bool enabled,
  }) async {
    if (_left || _media == null) return;
    var trackId = kind == 'audio' ? _audioTrackId : _videoTrackId;
    if (enabled && trackId == null) {
      // Eerste keer aan: echte track ophalen — pas daarna adverteren we het
      // vermogen (nooit audio/video veinzen vóór een track bestaat).
      final attached = kind == 'audio'
          ? await _media!.addLocalAudio()
          : await _media!.addLocalVideo();
      if (attached == null) {
        _emit(
          MeetingErrorEvent(
            message: AppLocalizations.active.d(
              'Het apparaat geeft geen toegang tot deze bron.',
            ),
          ),
        );
        return;
      }
      trackId = attached.trackId;
      if (kind == 'audio') {
        _audioTrackId = trackId;
        _audioSsrc = attached.ssrc;
      } else {
        _videoTrackId = trackId;
        _videoSsrc = attached.ssrc;
      }
      await _announceNewSource(kind);
    }
    if (trackId == null) return;
    if (kind == 'audio') _micEnabled = enabled;
    await _media!.setLocalTrackEnabled(trackId, enabled: enabled);
    await _sendPresenceUpdate();
    final local = _participants[_nick];
    if (local != null) {
      final next = kind == 'audio'
          ? local.copyWith(micMuted: !enabled)
          : local.copyWith(camOff: !enabled);
      _participants[_nick] = next;
      _emit(ParticipantUpdated(next));
    }
  }

  // ── helpers ───────────────────────────────────────────────────────────────

  /// IQ-roundtrip: versturen deed de aanroeper al; hier wachten we het
  /// antwoord met ons id af (bounded).
  Future<Stanza> _awaitIq(String id, Duration timeout) async {
    try {
      return await _channel.stanzas
          .where((s) => s.kind == StanzaKind.iq && s.id == id)
          .first
          .timeout(timeout);
    } on TimeoutException {
      throw const MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        'iq-timeout',
      );
    } on StateError {
      throw const MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        'sessie weggevallen',
      );
    }
  }

  String _errorCondition(Stanza stanza) {
    final error = stanza.child('error');
    if (error == null) return 'unknown';
    for (final e in error.childElements) {
      if (e.name.local != 'text') return e.name.local;
    }
    return 'unknown';
  }

  MeetingFailureReason _mapMucFailure(MucJoinFailure failure) =>
      switch (failure) {
        MucJoinFailure.banned ||
        MucJoinFailure.membersOnly ||
        MucJoinFailure.passwordRequired ||
        MucJoinFailure.notAllowed => MeetingFailureReason.appApprovalRequired,
        _ => MeetingFailureReason.providerUnavailable,
      };

  void _setConnection(MeetingConnectionState next) {
    if (_state == next || _events.isClosed) return;
    _state = next;
    _emit(ConnectionStateChanged(next));
  }

  void _emit(MeetingEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  String _nextIqId() => 'ocideck-${++_iqSeq}';

  /// Een willekeurige 128-bit uid in de vorm die de wire toont (32 hex) —
  /// lib-jitsi-meet gebruikt het als device-id, jicofo eist hem in de
  /// conference-IQ. Per sessie, niet per device: er is geen hergebruik-
  /// voordeel dat het koppelen van calls aan één device rechtvaardigt.
  static String _newMachineUid() {
    final r = Random.secure();
    return List.generate(32, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  static const _maxChatLength = 4096;
}
