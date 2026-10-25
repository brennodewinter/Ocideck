// Jitsi: de bron-wire — alles wat "welke bron (a0/v0) bestaat en in welke
// staat" op de wire zegt (#2534/#2535/#2537). Uit jitsi_signaling.dart
// gehaald om dat bestand onder het regelplafond te houden; de Jingle- voor
// de session-levenscyclus blijft daar.
//
//   * SourceInfo in MUC-presence is de mute/type-kaart:
//     `{"<nick>-a0":{"muted":true},"<nick>-v0":{"videoType":"desktop"}}`;
//   * `source-add`/`source-remove` jingle-acties kondigen eigen bronnen aan/
//     af bij de focus; de `json-message`-payload daarin koppelt ssrc→
//     sourcenaam→endpoint — dé sleutel tussen binnenkomende RTP en een
//     participant (de msid op de wire is een willekeurige UUID);
//   * `ForwardedSources` op het endpoint-datachannel zegt welke video-bron
//     de bridge nu forwardt.
//
// Pure parsers en bouwers, zelfde fail-closed regels als jitsi_signaling:
// onleesbare of onbegrensde invoer levert niets op, nooit een verzonnen
// feit.

import 'dart:convert';

import 'package:xml/xml.dart';

import '../../../xmpp/xmpp_stanza.dart';
import '../../meeting_participant.dart' show MeetingTrackKind;
import 'jitsi_signaling.dart';

// ── SourceInfo: mute-state in MUC-presence ──────────────────────────────────

/// De `SourceInfo`-JSON uit presence: `{ "<bron>": {"muted": true}, … }`.
/// Geeft bron→muted terug; onleesbare of onbegrensde invoer levert {} —
/// ontbrekende info is "onbekend", nooit "deelt niet mee".
Map<String, bool> parseSourceInfo(String? text) {
  if (text == null || text.isEmpty || text.length > _maxSourceInfoLength) {
    return const {};
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map) return const {};
  final out = <String, bool>{};
  for (final e in decoded.entries) {
    if (out.length >= _maxSources) break;
    final key = e.key;
    final value = e.value;
    if (key is String && value is Map && value['muted'] is bool) {
      out[key] = value['muted'] as bool;
    }
  }
  return out;
}

/// De `videoType` per bron uit dezelfde SourceInfo-JSON — 'desktop' markeert
/// een gedeeld scherm, 'camera' (of afwezig) een camera (#2537). Dezelfde
/// begrenzingen en fail-closed regels als [parseSourceInfo].
Map<String, String> parseSourceVideoTypes(String? text) {
  if (text == null || text.isEmpty || text.length > _maxSourceInfoLength) {
    return const {};
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const {};
  }
  if (decoded is! Map) return const {};
  final out = <String, String>{};
  for (final e in decoded.entries) {
    if (out.length >= _maxSources) break;
    final key = e.key;
    final value = e.value;
    if (key is String && value is Map && value['videoType'] is String) {
      out[key] = value['videoType'] as String;
    }
  }
  return out;
}

/// Bouw onze eigen SourceInfo-tekst — `{"<nick>-a0":{"muted":false}}`.
/// [videoType] markeert een bron als 'desktop' tijdens schermdelen (#2537);
/// zonder vermelding leest de andere kant 'camera'.
String buildSourceInfo(
  Map<String, bool> mutedBySource, {
  Map<String, String> videoType = const {},
}) => jsonEncode({
  for (final e in mutedBySource.entries)
    e.key: {
      'muted': e.value,
      if (videoType.containsKey(e.key)) 'videoType': videoType[e.key],
    },
});

// ── json-sources: ssrc↔sourcenaam in source-add/-remove ─────────────────────

/// Eén remote bron uit de `source-add`/`source-remove` json-message: de
/// bridge meldt SSRC's met hun sourcenaam (`<endpoint>-a0`/`-v0`) — dat is dé
/// koppelsleutel tussen binnenkomende RTP en een MUC-participant (de msid op
/// de wire is een willekeurige UUID, niet de sourcenaam).
typedef JitsiRemoteSource = ({
  int ssrc,
  String endpoint,
  String sourceName,
  MeetingTrackKind kind,
});

/// Parse de `{"sources":{…}}`-payload van een `source-add`/`source-remove`.
/// De endpoint-waarde is een geneste array (video-ssrc's, ssrc-groepen,
/// audio-ssrc's) waarvan de posities niet betrouwbaar zijn; we verzamelen álle
/// `{"s":…,"n":…}`-paren en classificeren op het `-a`/`-v`-achtervoegsel van de
/// naam. Onleesbare of onbegrensde invoer levert geen bronnen.
List<JitsiRemoteSource> parseJsonSources(String? text) {
  if (text == null || text.isEmpty || text.length > jitsiMaxSourcesJson) {
    return const [];
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map || decoded['sources'] is! Map) return const [];
  final out = <JitsiRemoteSource>[];
  for (final e in (decoded['sources'] as Map).entries) {
    if (out.length >= _maxSources) break;
    if (e.key is! String) continue;
    _collectSources(e.value, e.key as String, out);
  }
  return out;
}

void _collectSources(
  Object? node,
  String endpoint,
  List<JitsiRemoteSource> out,
) {
  if (out.length >= _maxSources) return;
  if (node is List) {
    for (final item in node) {
      _collectSources(item, endpoint, out);
    }
  } else if (node is Map) {
    final ssrc = node['s'];
    final name = node['n'];
    if (ssrc is int && name is String && name.length <= jitsiMaxFieldLength) {
      final dash = name.lastIndexOf('-');
      final kind = dash >= 0 && dash + 1 < name.length
          ? switch (name[dash + 1]) {
              'a' => MeetingTrackKind.audio,
              'v' => MeetingTrackKind.video,
              _ => null,
            }
          : null;
      if (kind != null) {
        out.add((ssrc: ssrc, endpoint: endpoint, sourceName: name, kind: kind));
      }
    }
  }
}

/// Eén `ForwardedSources`-bericht van de bridge: welke sourcenamen op dit
/// moment op de gedeelde video-m-line liggen. Null als dit bericht géén
/// ForwardedSources is. De wire-vorm is een lijst; oudere deployments sturen
/// een map — beide worden gelezen.
List<String>? parseForwardedSources(String? text) {
  if (text == null || text.isEmpty || text.length > jitsiMaxSourcesJson) {
    return null;
  }
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map || decoded['colibriClass'] != 'ForwardedSources') {
    return null;
  }
  final raw = decoded['forwardedSources'];
  if (raw is List) return raw.whereType<String>().toList();
  if (raw is Map) return raw.keys.whereType<String>().toList();
  return const [];
}

// ── presence- en announce-bouwers ───────────────────────────────────────────

/// De presence-extensies op een (her)join of update: displaynaam, de
/// SourceInfo-kaart én de endpoint-features — jicofo leest die uit de
/// presence (en via disco#info) om de session-initiate samen te stellen
/// (#2535). `<x xmlns='…/muc'>` plaatst XmppMuc zelf vooraan.
List<XmlElement> jitsiPresenceExtensions(
  String displayName,
  Map<String, bool> mutedBySource, {
  Map<String, String> videoType = const {},
}) => [
  xmppElement('nick', namespace: jitsiNickNs, text: displayName),
  xmppElement(
    'SourceInfo',
    text: buildSourceInfo(mutedBySource, videoType: videoType),
  ),
  xmppElement(
    'features',
    children: [
      for (final f in jitsiCallFeatures)
        xmppElement('feature', attributes: {'var': f}),
    ],
  ),
];

/// Een eigen bron aankondigen bij de focus als een source-add IQ — de
/// stanza-bouw (niet de beslissing of/when; dat is sessie-orchestratie).
Stanza jitsiSourceAnnounceIq({
  required String focusInRoom,
  required String iqId,
  required String sid,
  required String initiator,
  required String sourceName,
  required String ssrc,
}) => _jitsiSourceIq(
  focusInRoom: focusInRoom,
  iqId: iqId,
  sid: sid,
  initiator: initiator,
  sourceName: sourceName,
  ssrc: ssrc,
  remove: false,
);

/// Dezelfde bron weer afmelden bij de focus — `source-remove` i.p.v.
/// `source-add` (#2537; bijvoorbeeld het scherm was de enige video-bron).
Stanza jitsiSourceRemoveIq({
  required String focusInRoom,
  required String iqId,
  required String sid,
  required String initiator,
  required String sourceName,
  required String ssrc,
}) => _jitsiSourceIq(
  focusInRoom: focusInRoom,
  iqId: iqId,
  sid: sid,
  initiator: initiator,
  sourceName: sourceName,
  ssrc: ssrc,
  remove: true,
);

Stanza _jitsiSourceIq({
  required String focusInRoom,
  required String iqId,
  required String sid,
  required String initiator,
  required String sourceName,
  required String ssrc,
  required bool remove,
}) => Stanza(
  kind: StanzaKind.iq,
  to: focusInRoom,
  id: iqId,
  type: 'set',
  children: [
    if (remove)
      buildSourceRemove(
        sid: sid,
        initiator: initiator,
        contentName: sourceName.endsWith('-a0') ? 'audio' : 'video',
        media: sourceName.endsWith('-a0') ? 'audio' : 'video',
        sourceName: sourceName,
        ssrc: ssrc,
      )
    else
      buildSourceAdd(
        sid: sid,
        initiator: initiator,
        contentName: sourceName.endsWith('-a0') ? 'audio' : 'video',
        media: sourceName.endsWith('-a0') ? 'audio' : 'video',
        sourceName: sourceName,
        ssrc: ssrc,
      ),
  ],
);

// ── begrenzingen (alleen deze wire) ─────────────────────────────────────────

const _maxSources = 64;
const _maxSourceInfoLength = 8192;
