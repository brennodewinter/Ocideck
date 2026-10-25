part of 'jitsi_meeting_session.dart';

/// De lokale media-levenscyclus van een Jitsi-sessie (#2535/#2537): onze
/// mic-, camera- en scherm-tracks, hun SSRC-bronaankondiging bij de focus,
/// en de SourceInfo-kaart die presence meedraagt. Het remote-tegenstuk is
/// [JitsiRemoteMedia]; "welke eigen track op welke bron ligt" is ander werk
/// dan de sessie-orkestratie — en precies de groei waarmee de sessieklasse
/// boven haar regelplafond kwam.
///
/// `part of` dezelfde bibliotheek: de staat hier is sessie-privaat
/// (kanaal, nick, `_media` verandert bij elke heronderhandeling) — een
/// API-laag ertussen zou die privaatheid alleen omzeilen, niet opheffen.
final class JitsiLocalMedia {
  JitsiLocalMedia(this._s);

  final JitsiMeetingSession _s;

  String? audioTrackId;

  /// De track die op dit moment de `-v0`-bron voedt — de camera, of het
  /// gedeelde scherm tijdens een share (#2537).
  String? videoTrackId;

  /// De camera-track zélf — blijft bestaan terwijl het scherm op de sender
  /// ligt, zodat stoppen van delen de camera terugzet.
  String? cameraTrackId;
  String? screenTrackId;
  String? screenShareLabel;
  int? audioSsrc;
  int? videoSsrc;
  var micEnabled = true;
  var camEnabled = false;

  /// Een lopende share die door een verse session-initiate (bridge-failover)
  /// sneuvelde — na de heronderhandeling meldt de lokale participant dat het
  /// delen weg is (#2537).
  var shareLostInRenegotiate = false;

  /// De bronnen die dit platform aanbiedt om te delen — leeg waar de seam
  /// geen enumeratie heeft (de browser gebruikt zijn eigen kiezer).
  Future<List<MeetingScreenSource>> screenSources() async =>
      _s._media?.screenSources() ?? const [];

  /// De presence-extensies op een (her)join of update: displaynaam, de
  /// SourceInfo-kaart én de endpoint-features — jicofo leest die uit de
  /// presence (en via disco#info) om de session-initiate samen te stellen
  /// (#2535). `<x xmlns='…/muc'>` plaatst XmppMuc zelf vooraan.
  List<XmlElement> presenceExtensions(Map<String, bool> mutedBySource) =>
      jitsiPresenceExtensions(
        _s.displayName,
        mutedBySource,
        // Een lopende share markeert -v0 als 'desktop' — de andere kant
        // toont dan een schermdeel-tegel i.p.v. een camera (#2537).
        videoType: {if (screenTrackId != null) '${_s._nick}-v0': 'desktop'},
      );

  /// Een lokale track koppelen bij de join (mic/camera). Null bij geen
  /// device = eerlijk receive-only; de track-id/ssrc worden bewaard voor
  /// SourceInfo+source-add.
  Future<void> attachInitial(String kind) async {
    final attached = kind == 'audio'
        ? await _s._media!.addLocalAudio()
        : await _s._media!.addLocalVideo();
    if (attached == null) return;
    if (kind == 'audio') {
      audioTrackId = attached.trackId;
      audioSsrc = attached.ssrc;
      micEnabled = !_s.startMuted;
      await _s._media!.setLocalTrackEnabled(
        attached.trackId,
        enabled: !_s.startMuted,
      );
    } else {
      videoTrackId = attached.trackId;
      cameraTrackId = attached.trackId;
      camEnabled = true;
      videoSsrc = attached.ssrc;
    }
  }

  /// Een nieuwe connection = een nieuwe SSRC-ruimte én nieuwe streams: de
  /// oude track-ids gelden niet meer. Geeft terug of er een share mee
  /// sneuvelde (de participant-update doet de sessie na de aankondiging).
  void resetForConnection() {
    audioTrackId = videoTrackId = cameraTrackId = null;
    audioSsrc = videoSsrc = null;
    micEnabled = !_s.startMuted;
    camEnabled = false;
    if (screenTrackId != null) {
      screenTrackId = null;
      screenShareLabel = null;
      shareLostInRenegotiate = true;
    }
  }

  /// Mic/camera aan- of uitzetten — de eerste keer haalt dit de echte track
  /// op, daarna schakelt hij alleen de enable-vlag.
  Future<void> setMedia({required String kind, required bool enabled}) async {
    final media = _s._media;
    if (_s._left || media == null) return;
    var trackId = kind == 'audio' ? audioTrackId : cameraTrackId;
    if (enabled && trackId == null) {
      // Eerste keer aan: echte track ophalen — pas daarna adverteren we het
      // vermogen (nooit audio/video veinzen vóór een track bestaat). Tijdens
      // schermdelen blijft het scherm op de video-sender: de camera komt
      // erbij zonder die te verdringen (#2537).
      final attached = kind == 'audio'
          ? await media.addLocalAudio()
          : await media.addLocalVideo(attachToSender: screenTrackId == null);
      if (attached == null) {
        _s._emit(
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
        audioTrackId = trackId;
        audioSsrc = attached.ssrc;
      } else {
        cameraTrackId = trackId;
        // Op de sender (en dus als -v0-bron) komt de camera alleen als er
        // niet gedeeld wordt; anders wacht de track op het einde van de
        // share.
        if (screenTrackId == null) {
          videoTrackId = trackId;
          videoSsrc = attached.ssrc;
        }
      }
      if (kind == 'audio' || screenTrackId == null) {
        await announceNewSource(kind);
      }
    }
    if (trackId == null) return;
    if (kind == 'audio') {
      micEnabled = enabled;
    } else {
      camEnabled = enabled;
    }
    await media.setLocalTrackEnabled(trackId, enabled: enabled);
    await sendPresenceUpdate();
    final local = _s._participants[_s._nick];
    if (local != null) {
      // De (net heracquireerde) tracks vers opbouwen: copyWith kan een
      // track niet wissen, dus reconstrueren uit de huidige ids (#2535).
      final next = _s._localParticipantNow(
        kind == 'audio'
            ? local.copyWith(micMuted: !enabled)
            : local.copyWith(camOff: !enabled),
      );
      _s._participants[_s._nick] = next;
      _s._emit(ParticipantUpdated(next));
    }
  }

  /// Een scherm gaan delen op de vaste video-sender — geen nieuwe m-line,
  /// dus geen heronderhandeling (#2537). Weigering of een weggevallen bron
  /// is een niet-terminale fout voor de gebruiker, nooit een kapotte call.
  Future<void> startShare({String? sourceId, String? sourceLabel}) async {
    final media = _s._media;
    if (_s._left || media == null || screenTrackId != null) return;
    final attached = await media.addLocalScreen(sourceId: sourceId);
    if (attached == null) {
      _s._emit(
        MeetingErrorEvent(
          message: AppLocalizations.active.d(
            'Scherm delen is niet gelukt — de bron is geweigerd of weggevallen.',
          ),
        ),
      );
      return;
    }
    // De schermtrack vervangt het camerabeeld op dezelfde -v0-bron (de
    // Jitsi-route). Was -v0 er nog niet — camera uit — dan is dit een nieuwe
    // bron voor de focus: eerst aankondigen met zijn ssrc.
    final announce = videoTrackId == null;
    screenTrackId = attached.trackId;
    screenShareLabel = sourceLabel;
    videoTrackId = attached.trackId;
    if (announce) {
      videoSsrc = attached.ssrc;
      await announceNewSource('video');
    }
    // Presence zegt nu: -v0 bestaat, is niet gemuteerd, videoType 'desktop'.
    await sendPresenceUpdate();
    _s._refreshLocal((l) => l.copyWith(isScreenShare: true));
  }

  /// Het delen eindigen — door de gebruiker of doordat de bron wegviel aan
  /// de systeemkant ([onLocalTrackLost]). De seam zet de camera terug op de
  /// sender; de signalering zet -v0 bij.
  Future<void> endShare({required bool lost}) async {
    if (_s._left || screenTrackId == null) return;
    await _s._media?.stopScreenShare();
    screenTrackId = null;
    screenShareLabel = null;
    if (cameraTrackId == null) {
      // Het scherm was de enige -v0-bron — die valt weg, niet alleen het
      // type.
      await removeSource('video');
      videoTrackId = null;
      videoSsrc = null;
    } else {
      videoTrackId = cameraTrackId; // zelfde sender, zelfde ssrc
    }
    await sendPresenceUpdate();
    _s._refreshLocal((l) => l.copyWith(isScreenShare: false));
    if (lost) {
      _s._emit(
        MeetingErrorEvent(
          message: AppLocalizations.active.d(
            'De gedeelde bron viel weg; het delen is gestopt.',
          ),
        ),
      );
    }
  }

  /// Een eigen bron valt weg (mic/cam verdwenen, permissie ingetrokken,
  /// #2535): de track is écht weg — niet "gemuteerd". SourceInfo zakt die
  /// bron dus af, de participant toont hem uit, en de gebruiker krijgt een
  /// niet-terminale melding; opnieuw aanzetten haalt een verse track op.
  void onLocalTrackLost(String trackId) {
    if (_s._left) return;
    if (trackId == screenTrackId) {
      // De gedeelde bron viel weg aan de systeemkant (OS-stopknop, venster
      // dicht) — het delen eindigt netjes met een melding, geen crash
      // (#2537).
      unawaited(endShare(lost: true));
      return;
    }
    final isAudio = trackId == audioTrackId;
    if (!isAudio && trackId != cameraTrackId) return;
    if (isAudio) {
      audioTrackId = null;
      audioSsrc = null;
      micEnabled = false;
    } else {
      cameraTrackId = null;
      camEnabled = false;
      // Tijdens delen blijft -v0 het scherm — die bron blijft dus bestaan.
      if (screenTrackId == null) {
        videoTrackId = null;
        videoSsrc = null;
      }
    }
    sendPresenceUpdate();
    final local = _s._participants[_s._nick];
    if (local != null) {
      final next = _s._localParticipantNow(
        isAudio ? local.copyWith(micMuted: true) : local.copyWith(camOff: true),
      );
      _s._participants[_s._nick] = next;
      _s._emit(ParticipantUpdated(next));
    }
    _s._emit(
      MeetingErrorEvent(
        message: AppLocalizations.active.d(
          'Je microfoon of camera viel weg; zet de bron opnieuw aan als je die terug hebt.',
        ),
      ),
    );
  }

  /// Presence met de actuele SourceInfo-kaart (onze mute-waarheid op de
  /// wire) — verstuurd na de accept en na elke mute-wijziging. Tijdens
  /// schermdelen is -v0 het scherm: niet gemuteerd, videoType 'desktop'.
  Future<void> sendPresenceUpdate() async {
    final muted = <String, bool>{
      if (audioTrackId != null) '${_s._nick}-a0': !micEnabled,
      if (videoTrackId != null)
        '${_s._nick}-v0': screenTrackId == null && !camEnabled,
    };
    _s._channel.sendStanza(
      Stanza(
        kind: StanzaKind.presence,
        to: '${_s.roomJid}/${_s._nick}',
        children: presenceExtensions(muted),
      ),
    );
  }

  /// Een bron aankondigen bij de focus, als de ssrc bekend is.
  Future<void> announceNewSource(String kind) async {
    final initiate = _s._initiate;
    final ssrc = kind == 'audio' ? audioSsrc : videoSsrc;
    if (initiate == null || ssrc == null) return;
    _s._channel.sendStanza(
      jitsiSourceAnnounceIq(
        focusInRoom: _s._focusInRoom,
        iqId: _s._nextIqId(),
        sid: initiate.sid,
        initiator: initiate.initiator,
        sourceName: '${_s._nick}-${kind[0]}0',
        ssrc: '$ssrc',
      ),
    );
    // De ack is best-effort: de MUC reflecteert ons sowieso terug, en een
    // verloren source-add herstelt via de volgende presence.
  }

  /// Een bron afmelden bij de focus — het spiegelbeeld van
  /// [announceNewSource] (#2537: het scherm was de enige -v0-bron).
  Future<void> removeSource(String kind) async {
    final initiate = _s._initiate;
    final ssrc = kind == 'audio' ? audioSsrc : videoSsrc;
    if (initiate == null || ssrc == null) return;
    _s._channel.sendStanza(
      jitsiSourceRemoveIq(
        focusInRoom: _s._focusInRoom,
        iqId: _s._nextIqId(),
        sid: initiate.sid,
        initiator: initiate.initiator,
        sourceName: '${_s._nick}-${kind[0]}0',
        ssrc: '$ssrc',
      ),
    );
  }
}
