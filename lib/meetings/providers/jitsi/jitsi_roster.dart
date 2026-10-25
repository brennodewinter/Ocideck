// Pure MUC-occupant → `MeetingParticipant` mapping for the Jitsi adapter
// (#2535, uit `jitsi_meeting_session.dart` gehaald voor het file-plafond).
// Dit is wire-kennis, geen orchestratie: de jitsi `<nick>`-extensie, de
// SourceInfo-mute-kaart en de `<nick>-a0`/`-v0`-sourcenamen — daarom staat
// hij naast de andere wire-helpers, los van de sessie-state.

import 'package:xml/xml.dart';

import '../../../xmpp/xmpp_muc.dart';
import '../../meeting_participant.dart';
import '../../meeting_provider.dart' show MeetingFailureReason;
import 'jitsi_signaling.dart';
import 'jitsi_source_wire.dart';

/// Eén occupant → de provider-neutrale participant. Geen presence-gegevens
/// = het veiligste antwoord (gemuteerd/camera uit), nooit rooskleuriger dan
/// de wire toelaat.
MeetingParticipant jitsiParticipantOf(MucOccupant occ) {
  var display = occ.nick;
  var micMuted = true;
  var camOff = true;
  var isScreenShare = false;
  for (final ext in occ.extensions) {
    switch (ext.name.local) {
      case 'nick':
        if ((ext.getAttribute('xmlns') ?? ext.name.namespaceUri) ==
            jitsiNickNs) {
          final v = ext.innerText.trim();
          if (v.isNotEmpty && v.length <= 128) display = v;
        }
      case 'SourceInfo':
        final text = ext.innerText;
        final muted = parseSourceInfo(text);
        final a = muted['${occ.nick}-a0'];
        final v = muted['${occ.nick}-v0'];
        if (a != null) micMuted = a;
        if (v != null) camOff = v;
        // 'desktop' op de -v0-bron: de andere kant deelt zijn scherm op de
        // bestaande video-source, niet op een aparte m-line (#2537).
        isScreenShare =
            parseSourceVideoTypes(text)['${occ.nick}-v0'] == 'desktop';
    }
  }
  return MeetingParticipant(
    id: occ.nick,
    displayName: display,
    role: jitsiRoleOf(occ),
    micMuted: micMuted,
    camOff: camOff,
    isScreenShare: isScreenShare,
  );
}

/// MUC-rol → de provider-neutrale rol.
MeetingRole jitsiRoleOf(MucOccupant occ) => switch (occ.role) {
  MucRole.moderator => MeetingRole.moderator,
  MucRole.participant => MeetingRole.attendee,
  MucRole.visitor => MeetingRole.guest,
  MucRole.none => MeetingRole.unknown,
};

/// De velden die presence verandert — tracks komen via de media-laag en
/// tellen hier niet mee.
/// Het endpoint van een Jitsi-sourcenaam — `'<ep>-v0'` → `'<ep>'`. Ons
/// nick-alfabet sluit streepjes uit, dus het laatste streepje scheidt.
String? jitsiEndpointOfSource(String sourceName) {
  final dash = sourceName.lastIndexOf('-');
  return dash > 0 ? sourceName.substring(0, dash) : null;
}

bool jitsiParticipantDiffers(MeetingParticipant a, MeetingParticipant b) =>
    a.displayName != b.displayName ||
    a.role != b.role ||
    a.micMuted != b.micMuted ||
    a.camOff != b.camOff ||
    a.isScreenShare != b.isScreenShare;

/// Tracks zijn niet `copyWith`-baar (null betekent "houden") — bouw
/// expliciet, bijv. bij een presence-update die de media-tracks bewaart.
MeetingParticipant jitsiParticipantWithTracks(
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

/// De lokale participant herbouwd vanuit de huidige bronnen — `copyWith`
/// kan een track per ontwerp niet wissen, dus reconstrueren we de
/// track-velden uit de track-ids die de sessie bijhoudt (#2535).
MeetingParticipant jitsiLocalParticipant({
  required String nick,
  required MeetingParticipant of,
  required String? audioTrackId,
  required String? videoTrackId,
}) => MeetingParticipant(
  id: nick,
  displayName: of.displayName,
  role: of.role,
  isLocal: true,
  audio: audioTrackId == null
      ? null
      : MeetingTrack(id: audioTrackId, kind: MeetingTrackKind.audio),
  video: videoTrackId == null
      ? null
      : MeetingTrack(id: videoTrackId, kind: MeetingTrackKind.video),
  micMuted: of.micMuted,
  camOff: of.camOff,
  isDominantSpeaker: of.isDominantSpeaker,
  isScreenShare: of.isScreenShare,
);

/// MUC-join-failure → provider-neutrale failure-reason — pure mapping,
/// geen sessie-state (#2535, uit de sessie gehaald voor het file-plafond).
MeetingFailureReason jitsiMapMucFailure(MucJoinFailure failure) =>
    switch (failure) {
      MucJoinFailure.banned ||
      MucJoinFailure.membersOnly ||
      MucJoinFailure.passwordRequired ||
      MucJoinFailure.notAllowed => MeetingFailureReason.appApprovalRequired,
      _ => MeetingFailureReason.providerUnavailable,
    };
