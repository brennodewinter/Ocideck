// Jitsi: welke remote media bij welke deelnemer hoort (#2535).
//
// De JVB stuurt audio en video over één gedeelde stream per richting — de
// track zelf zegt niets over de eigenaar (zijn msid is een willekeurige
// UUID). De eigenaar komt uit Jitsi-signaling: source-add json-messages
// koppelen ssrc→sourcenaam→endpoint (audio), en `ForwardedSources` op de
// EndpointMessageTransport zegt welke video-bron de bridge nu forwardt.
// Deze klasse beheert die feiten en beantwoordt per participant welke
// track er hoort — de sessie vertaalt dat naar participant-updates.
// Fail-closed: zonder feit is er geen track, nooit een tegel verzinnen.

import 'dart:async';

import '../../../utils/log.dart';
import '../../meeting_media_core.dart';
import '../../meeting_participant.dart';
import 'jitsi_roster.dart';
import 'jitsi_signaling.dart';

class JitsiRemoteMedia {
  /// [onChanged] vuurt telkens als de track-toewijzing kan zijn
  /// veranderd (nieuwe track, source-update, forwarded-update, reset);
  /// de sessie mapt dan de tracks op haar participants.
  JitsiRemoteMedia({required this.onChanged});

  final void Function() onChanged;

  /// De gedeelde binnenkomende streams van de JVB — één audio-, één
  /// video-m-line.
  MeetingTrack? _audioTrack;
  MeetingTrack? _videoTrack;

  /// De sourcenamen die de bridge nu op de video-m-line forwardt
  /// (`ForwardedSources`) — een `ep-vN` naam betekent "het beeld van `ep`".
  final _forwardedSources = <String>{};

  /// SSRC→bron zoals de `source-add` json-messages hem melden — welke
  /// endpoints een audio-/video-bron op de bridge hebben.
  final _ssrcOwners = <int, JitsiRemoteSource>{};

  StreamSubscription<String>? _endpointSub;

  /// De videotrack voor [participantId], of null als de bridge geen bron
  /// van dit endpoint forwardt.
  MeetingTrack? videoFor(String participantId) =>
      _forwardedSources.any((n) => jitsiEndpointOfSource(n) == participantId)
      ? _videoTrack
      : null;

  /// De audiotrack voor [participantId] — bekend zodra source-add een
  /// audio-ssrc van dit endpoint heeft gemeld.
  MeetingTrack? audioFor(String participantId) =>
      _ssrcOwners.values.any(
        (s) => s.kind == MeetingTrackKind.audio && s.endpoint == participantId,
      )
      ? _audioTrack
      : null;

  /// Een track-event van de media-laag: bewaar (of ruim bij `active=false`)
  /// de gedeelde stream van deze soort.
  void trackArrived(MeetingRemoteTrack remote) {
    if (remote.track.kind == MeetingTrackKind.audio) {
      _audioTrack = remote.active ? remote.track : null;
    } else {
      _videoTrack = remote.active ? remote.track : null;
    }
    onChanged();
  }

  /// Een source-add/-remove json toepassen ([add] = richting) — de kaart
  /// zegt welke endpoints een bron op de bridge hebben.
  void applySources(Iterable<JitsiRemoteSource> sources, {required bool add}) {
    for (final s in sources) {
      if (add) {
        _ssrcOwners[s.ssrc] = s;
      } else {
        _ssrcOwners.remove(s.ssrc);
      }
    }
    onChanged();
  }

  /// De EndpointMessageTransport: een SCTP-datachannel naar de JVB waarover
  /// de bridge-messages lopen. De handshake is client-gedreven
  /// (`ClientHello` → `ServerHello` terug); daarna zeggen we met
  /// `ReceiverVideoConstraints` welke video de bridge moet forwarden —
  /// zonder dat komt er nooit een remote videotrack binnen (de
  /// `EndpointMessageTransport still not connected` uit de jvb-log).
  /// Een falend kanaal is géén join-faal: audio werkt zonder, en een
  /// tegel verschijnt pas bij een echte remote track — eerlijk.
  /// [stillValid] bewaakt de race met een nieuwe connection: is [media]
  /// bij aankomst van het kanaal niet meer de huidige, dan sluiten we hem.
  Future<void> openEndpointChannel(
    MeetingMediaConnection media, {
    required bool Function() stillValid,
  }) async {
    try {
      final channel = await media.openDataChannel('EndpointMessage');
      if (!stillValid()) {
        await channel.close();
        return;
      }
      await _endpointSub?.cancel();
      _endpointSub = channel.messages.listen(_onEndpointMessage);
      await channel.send('{"colibriClass":"ClientHello"}');
      // Geen per-source selectie nodig: defaultConstraints geldt voor elke
      // huidige én toekomstige source, net als tile-view in de web-client.
      await channel.send(
        '{"colibriClass":"ReceiverVideoConstraints",'
        '"defaultConstraints":{"maxHeight":720}}',
      );
    } catch (e) {
      logWarning('JitsiRemoteMedia: endpoint-channel', e);
    }
  }

  /// Bridge-messages op het endpoint-kanaal. `ForwardedSources` is hier
  /// het werkpaard: de JVB stuurt één gedeelde videostream en zegt hiermee
  /// wélke bron er op ligt. Andere klassen (ServerHello, stats,
  /// speaker-events) consumeren we later.
  void _onEndpointMessage(String text) {
    final forwarded = parseForwardedSources(text);
    if (forwarded == null) return;
    _forwardedSources
      ..clear()
      ..addAll(forwarded);
    onChanged();
  }

  /// Alles terug naar leeg — een nieuwe connection is een nieuwe
  /// SSRC-ruimte met nieuwe gedeelde streams; de oude koppeling geldt
  /// niet en remote-tegels van de dode connectie zijn eerlijk gezegd weg.
  void reset() {
    _audioTrack = null;
    _videoTrack = null;
    _forwardedSources.clear();
    _ssrcOwners.clear();
    unawaited(_endpointSub?.cancel());
    _endpointSub = null;
    onChanged();
  }

  Future<void> close() async {
    await _endpointSub?.cancel();
    _endpointSub = null;
  }
}
