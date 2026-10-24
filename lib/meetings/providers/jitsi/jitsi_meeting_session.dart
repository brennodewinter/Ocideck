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

import 'package:xml/xml.dart';

import '../../../l10n/app_localizations.dart';
import '../../../xmpp/xmpp_muc.dart';
import '../../../xmpp/xmpp_session.dart' show XmppStanzaChannel;
import '../../../xmpp/xmpp_stanza.dart';
import '../../../utils/log.dart';
import '../../meeting_event.dart';
import '../../meeting_media_core.dart';
import '../../meeting_nick.dart';
import '../../meeting_participant.dart';
import '../../meeting_provider.dart';
import 'jitsi_remote_media.dart';
import 'jitsi_roster.dart';
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
    } catch (e, st) {
      logError('JitsiMeetingSession.join faalde', e, st);
      await session._teardown(silent: true);
      throw MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        '$e\n$st', // tijdelijke diagnose — weer e.toString() na fix
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
  StreamSubscription<String>? _lostSub;
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

  /// Remote-track→participant-eigendom: de gedeelde JVB-streams plus de
  /// Jitsi-signaling (ForwardedSources/source-add) die zegt wie erop ligt
  /// (#2535, uitgeleid naar `jitsi_remote_media.dart`).
  late final _remoteMedia = JitsiRemoteMedia(onChanged: _remapRemoteTiles);

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
  MeetingE2eeStatus get mediaE2ee => _mediaCore.mediaE2ee;

  /// De JVB-adressen uit de laatste session-initiate — de werkelijke media-
  /// egress, niet geraden. Leeg tot er een offer is geweest.
  var _mediaEgress = const <String>[];

  @override
  List<String> get mediaEgressOrigins => _mediaEgress;

  @override
  Future<MeetingVideoSurface?> videoSurfaceFor(String participantId) async {
    final track = _participants[participantId]?.video;
    final media = _media;
    if (media == null || track == null) return null;
    return media.attachVideo(track.id);
  }

  @override
  Future<List<MeetingAudioOutput>> audioOutputs() async =>
      _media?.audioOutputs() ?? const [];

  @override
  Future<void> selectAudioOutput(String deviceId) =>
      _media?.selectAudioOutput(deviceId) ?? Future.value();

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
    await _negotiateMediaAndAnnounce(_initiate!);

    _roster = _muc!.occupants.listen(_onRoster);
    _participants[_nick] = MeetingParticipant(
      id: _nick,
      displayName: displayName,
      role: _localRoleFromMuc(),
      isLocal: true,
      audio: _audioTrackId == null
          ? null
          : MeetingTrack(id: _audioTrackId!, kind: MeetingTrackKind.audio),
      video: _videoTrackId == null
          ? null
          : MeetingTrack(id: _videoTrackId!, kind: MeetingTrackKind.video),
      micMuted: _audioTrackId == null || startMuted,
      camOff: _videoTrackId == null || startCameraOff,
    );
    _setConnection(MeetingConnectionState.connected);
  }

  /// lib-jitsi-meet's device-id voor de conference-IQ — eenmalig per sessie
  /// en hergebruikt bij een rejoin, zodat jicofo hetzelfde apparaat ziet.
  final _machineUid = jitsiNewMachineUid();

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
      final condition = jitsiStanzaErrorCondition(reply);
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
        jitsiMapMucFailure(result.failure!),
        'muc: ${result.failure!.name}',
      );
    }
  }

  /// De presence-extensies op een (her)join of update: displaynaam, de
  /// SourceInfo-kaart én de endpoint-features — jicofo leest die uit de
  /// presence (en via disco#info) om de session-initiate samen te stellen
  /// (#2535). `<x xmlns='…/muc'>` plaatst XmppMuc zelf vooraan.
  List<XmlElement> _presenceExtensions(Map<String, bool> mutedBySource) =>
      jitsiPresenceExtensions(displayName, mutedBySource);

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

  /// Media-onderhandeling + bronnen aankondigen + liveness-bewijs — gedeeld
  /// door de join, de [rejoin] én de renegotiate bij een verse
  /// session-initiate van een draaiende sessie (bridge-failover, #2535).
  Future<void> _negotiateMediaAndAnnounce(
    JingleSessionInitiate initiate,
  ) async {
    _initiate = initiate;
    await _negotiateMedia(initiate);
    // Eigen bronnen aankondigen (wire-volgorde: presence, dan source-add).
    await _sendPresenceUpdate();
    await _announceNewSource('audio');
    await _announceNewSource('video');
    // Mediapad-bewijs — pas live ICE betekent "connected".
    await _awaitMediaLive();
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
    // Per-connection streams: rejoin/renegotiate vervangt `_media`, dus
    // ALLE subscriptions op de oude connection worden hier vervangen —
    // niet verspreid over de call-sites (daar gingen remoteTracks/liveness
    // anders dood na een heronderhandeling, #2535).
    unawaited(_lostSub?.cancel());
    _lostSub = _media!.localTrackLost.listen(_onLocalTrackLost);
    unawaited(_remoteTracks?.cancel());
    _remoteTracks = _media!.remoteTracks.listen(_remoteMedia.trackArrived);
    unawaited(_livenessSub?.cancel());
    _livenessSub = _media!.liveness.listen(_onLiveness);
    // Nieuwe connectie = nieuwe SSRC-ruimte én nieuwe gedeelde streams: de
    // oude koppeling geldt niet en remote-tegels van de dode connectie zijn
    // eerlijk gezegd weg (de reset triggert zelf de remap die ze leegt).
    _remoteMedia.reset();
    _mediaEgress = {
      for (final content in initiate.contents)
        if (content.transport != null)
          for (final c in content.transport!.candidates) '${c.ip}:${c.port}',
    }.toList();
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
          'accept: ${jitsiStanzaErrorCondition(reply)}',
        );
      }
      // Het endpoint-kanaal opent pas als DTLS/SCTP staat — parallel aan de
      // ICE-wacht, nooit ervoor blokkerend.
      final media = _media!;
      unawaited(
        _remoteMedia.openEndpointChannel(
          media,
          stillValid: () => !_left && identical(media, _media),
        ),
      );
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
      jitsiSourceAnnounceIq(
        focusInRoom: _focusInRoom,
        iqId: _nextIqId(),
        sid: initiate.sid,
        initiator: initiate.initiator,
        sourceName: '$_nick-${kind[0]}0',
        ssrc: '$ssrc',
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
      await _media?.close();
      await _negotiateMediaAndAnnounce(initiate);
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
          try {
            final initiate = parseSessionInitiate(jingle);
            if (_state == MeetingConnectionState.connected &&
                _initiate != null &&
                initiate.sid != _initiate!.sid) {
              // Bridge-failover: geen nieuwe join — een renegotiate op de
              // bestaande sessie (#2535).
              unawaited(_renegotiate(initiate));
            } else {
              // Te vroeg voor de await — bewaren; [_awaitInitiate] pikt hem op.
              _pendingInitiate = initiate;
            }
          } on JitsiContractException {
            // Een kapot contract zonder wachter hoeven we niet te bewaren.
          }
        }
      case 'session-terminate':
        ack();
        unawaited(_remoteTerminated());
      case 'source-add' || 'source-remove':
        // De json-message mapt ssrc→sourcenaam per endpoint — dé koppeling
        // tussen binnenkomende RTP en een participant (#2535). Verwijderen is
        // symmetrisch: dezelfde payload, andere richting.
        final json = jingle.childElements
            .where((e) => e.name.local == 'json-message')
            .firstOrNull
            ?.innerText;
        _remoteMedia.applySources(
          parseJsonSources(json),
          add: name == 'source-add',
        );
        ack();
      case 'transport-info' || 'session-info':
        // transport-info draagt onze ICE-kandidaten niet (de JVB leert die
        // peer-reflexive).
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
        final role = jitsiRoleOf(occ);
        if (role != local.role) {
          final next = local.copyWith(role: role);
          _participants[_nick] = next;
          _emit(ParticipantUpdated(next));
        }
        continue;
      }
      final parsed = jitsiParticipantOf(occ);
      final existing = _participants[occ.nick];
      if (existing == null) {
        _participants[occ.nick] = parsed;
        _emit(ParticipantJoined(parsed));
      } else if (jitsiParticipantDiffers(existing, parsed)) {
        // Tracks behouden: die komen via de media-laag, niet via presence.
        _participants[occ.nick] = jitsiParticipantWithTracks(
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
    // Een verse roster kan tegels van net-gearriveerde streams uitdelen.
    _remapRemoteTiles();
  }

  MeetingRole _localRoleFromMuc() {
    for (final occ in _muc?.roster ?? const <MucOccupant>[]) {
      if (occ.isSelf) return jitsiRoleOf(occ);
    }
    return MeetingRole.attendee;
  }

  // ── remote tracks → participant-tegels ────────────────────────────────────

  /// Deel de gedeelde JVB-streams uit aan de participants die de signaling
  /// als eigenaar aanwijst — welke track bij wie hoort beheert
  /// [JitsiRemoteMedia]; hier zetten we dat om in participant-updates.
  /// Nooit een tegel verzinnen — zonder feit geen track.
  void _remapRemoteTiles() {
    for (final entry in _participants.entries.toList()) {
      final p = entry.value;
      if (p.isLocal) continue;
      final video = _remoteMedia.videoFor(p.id);
      final audio = _remoteMedia.audioFor(p.id);
      if (identical(video, p.video) && identical(audio, p.audio)) continue;
      final updated = jitsiParticipantWithTracks(p, audio: audio, video: video);
      _participants[entry.key] = updated;
      _emit(ParticipantUpdated(updated));
    }
  }

  /// Een eigen bron valt weg (mic/cam verdwenen, permissie ingetrokken,
  /// #2535): de track is écht weg — niet "gemuteerd". SourceInfo zakt die
  /// bron dus af, de participant toont hem uit, en de gebruiker krijgt een
  /// niet-terminale melding; opnieuw aanzetten haalt een verse track op.
  void _onLocalTrackLost(String trackId) {
    if (_left) return;
    final isAudio = trackId == _audioTrackId;
    if (!isAudio && trackId != _videoTrackId) return;
    if (isAudio) {
      _audioTrackId = null;
      _audioSsrc = null;
      _micEnabled = false;
    } else {
      _videoTrackId = null;
      _videoSsrc = null;
    }
    _sendPresenceUpdate();
    final local = _participants[_nick];
    if (local != null) {
      final next = _localParticipantNow(
        isAudio ? local.copyWith(micMuted: true) : local.copyWith(camOff: true),
      );
      _participants[_nick] = next;
      _emit(ParticipantUpdated(next));
    }
    _emit(
      MeetingErrorEvent(
        message: AppLocalizations.active.d(
          'Je microfoon of camera viel weg; zet de bron opnieuw aan als je die terug hebt.',
        ),
      ),
    );
  }

  /// Een verse session-initiate terwijl we verbonden zijn = de bridge is
  /// vervangen (failover) en de sessie onderhandelt opnieuw (#2535). Dezelfde
  /// kamer en roster blijven; het mediapad wordt opnieuw opgebouwd. Een
  /// mislukte heronderhandeling is eerlijk fataal voor de call.
  Future<void> _renegotiate(JingleSessionInitiate initiate) async {
    if (_left) return;
    _setConnection(MeetingConnectionState.reconnecting);
    try {
      await _media?.close();
      await _negotiateMediaAndAnnounce(initiate);
      _setConnection(MeetingConnectionState.connected);
    } on MeetingJoinException {
      await _terminalError(
        AppLocalizations.active.d('De mediaverbinding is weggevallen.'),
      );
    }
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
    await _lostSub?.cancel();
    await _remoteMedia.close();
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
      // De (net heracquireerde) tracks vers opbouwen: copyWith kan een
      // track niet wissen, dus reconstrueren uit de huidige ids (#2535).
      final next = _localParticipantNow(
        kind == 'audio'
            ? local.copyWith(micMuted: !enabled)
            : local.copyWith(camOff: !enabled),
      );
      _participants[_nick] = next;
      _emit(ParticipantUpdated(next));
    }
  }

  /// Herbouw vanuit de huidige track-ids — de mapping zelf staat in
  /// `jitsi_roster.dart` (copyWith kan een track niet wissen, #2535).
  MeetingParticipant _localParticipantNow(MeetingParticipant local) =>
      jitsiLocalParticipant(
        nick: _nick,
        of: local,
        audioTrackId: _audioTrackId,
        videoTrackId: _videoTrackId,
      );

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

  void _setConnection(MeetingConnectionState next) {
    if (_state == next || _events.isClosed) return;
    _state = next;
    _emit(ConnectionStateChanged(next));
  }

  void _emit(MeetingEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  String _nextIqId() => 'ocideck-${++_iqSeq}';

  static const _maxChatLength = 4096;
}
