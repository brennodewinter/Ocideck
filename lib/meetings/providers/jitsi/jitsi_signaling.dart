// The Jitsi signalling wire layer (#2534): conference-IQ, Jingle
// (session-initiate/accept/terminate, source-add) and the presence
// `SourceInfo` extension — modelled from the real wire captured against the
// pinned testbed (`testbed/jitsi-meet`, stable-11248), not from assumptions.
//
// What the wire showed, and what this file therefore does:
//
//   * join starts with `<iq set to=focus.<domain>><conference room='…@muc…'
//     xmlns='http://jitsi.org/protocol/focus'/>`; Jicofo answers
//     `<conference ready='true' focusjid='…' session-id='…'>` or an iq-error
//     (`not-authorized` = this JID may not create/enter the room);
//   * media negotiation is Jingle over `urn:xmpp:jingle:1`: the focus sends
//     `session-initiate` (audio/video/data contents, BUNDLE group, ice-udp
//     transport carrying the JVB's OWN candidates + a sha-256 DTLS
//     fingerprint, a `json-message` with the jvb sources), the client answers
//     `session-accept` built from its SDP answer. The client sends NO
//     candidates: the JVB learns our address from the STUN checks it
//     receives (peer-reflexive) — that is why there is no transport-info on
//     the wire;
//   * own sources are announced AFTER the accept with `source-add`
//     (`urn:xmpp:jingle:apps:rtp:ssma:0`, name `<nick>-a0`/`-v0` + msid);
//   * mute state is NOT a jingle action in this version: it rides in MUC
//     presence as the `SourceInfo` JSON map (`{"<nick>-a0":{"muted":true}}`);
//   * leave = MUC presence `unavailable` (+ session-terminate is polite).
//
// Pure and deterministic: no I/O, no sessions. Parse failures are typed
// ([JitsiContractIssue]) so a changed/unknown contract fails closed —
// never a "seemingly connected" session without a media path.

import 'dart:convert';

import 'package:xml/xml.dart';

import '../../../xmpp/xmpp_stanza.dart';

const jitsiFocusNs = 'http://jitsi.org/protocol/focus';
const jitsiJitmeetNs = 'http://jitsi.org/jitmeet';
const jingleNs = 'urn:xmpp:jingle:1';
const jingleRtpNs = 'urn:xmpp:jingle:apps:rtp:1';
const jingleIceNs = 'urn:xmpp:jingle:transports:ice-udp:1';
const jingleDtlsNs = 'urn:xmpp:jingle:apps:dtls:0';
const jingleSctpNs = 'urn:xmpp:jingle:transports:dtls-sctp:1';
const jingleGroupNs = 'urn:xmpp:jingle:apps:grouping:0';
const jingleRtcpFbNs = 'urn:xmpp:jingle:apps:rtp:rtcp-fb:0';
const jingleHdrextNs = 'urn:xmpp:jingle:apps:rtp:rtp-hdrext:0';
const jingleSsmaNs = 'urn:xmpp:jingle:apps:rtp:ssma:0';
const jitsiNickNs = 'http://jabber.org/protocol/nick';

/// Waarom een Jingle-/focus-contract niet aanvaard werd — elke waarde is een
/// expliciete, diagnosticeerbare reden (acceptatie: "onbekend of gewijzigd
/// Colibri2/Jingle-contract → fail closed of unsupported").
enum JitsiContractIssue {
  /// Geen `<jingle>`-element, of een andere namespace dan `urn:xmpp:jingle:1`.
  notJingle,

  /// `session-initiate` mist `sid`, `initiator` of inhoud.
  malformedInitiate,

  /// Geen `<group semantics='BUNDLE'>` — wij onderhandelen alleen gebundelde
  /// media (zoals elke huidige Jitsi); iets anders is een gewijzigd contract.
  missingBundle,

  /// Een `<content>` die geen audio/video/data is.
  unknownContent,

  /// Een rtp-content zonder `<description>`.
  missingDescription,

  /// Een content zonder ice-udp `<transport>` met ufrag/pwd.
  missingTransport,

  /// Transport zonder sha-256 DTLS-fingerprint.
  missingFingerprint,

  /// Transport zonder enige bruikbare kandidaat — geen mediapad mogelijk.
  missingCandidates,
}

class JitsiContractException implements Exception {
  const JitsiContractException(this.issue, this.detail);

  final JitsiContractIssue issue;

  /// Kort, grof diagnosedetail — nooit credentials of volledige payload.
  final String detail;

  @override
  String toString() => 'jitsi contract: ${issue.name} ($detail)';
}

/// Een ICE-kandidaat zoals de JVB hem aankondigt in het transport.
class JingleIceCandidate {
  const JingleIceCandidate({
    required this.ip,
    required this.port,
    this.foundation = '1',
    this.component = '1',
    this.protocol = 'udp',
    this.priority = '0',
    this.type = 'host',
    this.relAddr,
    this.relPort,
    this.generation = '0',
    this.network = '0',
  });

  final String ip;
  final String port;
  final String foundation;
  final String component;
  final String protocol;
  final String priority;
  final String type;
  final String? relAddr;
  final String? relPort;
  final String generation;
  final String network;
}

/// Een RTP-payload-type uit een `<description>` (id, naam, klok, kanalen,
/// fmtp-parameters, rtcp-fb).
class JinglePayloadType {
  const JinglePayloadType({
    required this.id,
    required this.name,
    required this.clockrate,
    this.channels,
    this.parameters = const {},
    this.rtcpFb = const [],
  });

  final String id;
  final String name;
  final String clockrate;
  final String? channels;
  final Map<String, String> parameters;
  final List<String> rtcpFb;
}

/// Het ice-udp transport van één content: ufrag/pwd, DTLS-fingerprint en de
/// kandidaten (bij een initiate: de JVB's eigen adressen).
class JingleTransport {
  const JingleTransport({
    required this.ufrag,
    required this.pwd,
    required this.fingerprint,
    this.fingerprintHash = 'sha-256',
    this.setup = 'actpass',
    this.candidates = const [],
    this.sctpNumber,
    this.sctpStreams,
  });

  final String ufrag;
  final String pwd;
  final String fingerprint;
  final String fingerprintHash;
  final String setup;
  final List<JingleIceCandidate> candidates;

  /// `<sctpmap number>` uit het dtls-sctp-transport (de bridge-datachannel).
  final String? sctpNumber;
  final String? sctpStreams;
}

/// Eén `<content>` uit een Jingle-uitwisseling.
class JingleContent {
  const JingleContent({
    required this.name,
    required this.media,
    this.senders,
    this.creator,
    this.payloads = const [],
    this.headerExtensions = const [],
    this.rtcpMux = false,
    this.transport,
  });

  /// `audio`/`video`/`data` — tevens de BUNDLE-mid.
  final String name;

  /// Het media-attribuut van de description (`audio`, `video`, `application`).
  final String media;

  /// `initiator`/`responder`/`both`/`none` (XEP-0166).
  final String? senders;
  final String? creator;
  final List<JinglePayloadType> payloads;

  /// `(id, uri)`-paren uit `<rtp-hdrext>`.
  final List<(String, String)> headerExtensions;
  final bool rtcpMux;
  final JingleTransport? transport;
}

/// Een ontleedde `session-initiate`.
class JingleSessionInitiate {
  const JingleSessionInitiate({
    required this.sid,
    required this.initiator,
    required this.contents,
    required this.bundleContents,
    this.sourcesJson,
  });

  final String sid;
  final String initiator;
  final List<JingleContent> contents;

  /// De content-namen uit de BUNDLE-group.
  final List<String> bundleContents;

  /// De `json-message`-payload met de jvb-sources (ruwe JSON, begrensd).
  final String? sourcesJson;
}

/// De geslaagde uitkomst van de conference-IQ.
class JitsiConferenceReady {
  const JitsiConferenceReady({this.focusJid, this.sessionId});

  /// De JID waarnaar Jingle-sets gaan (`focus@auth.<domain>/focus`), of null
  /// wanneer de server hem niet meldde — de MUC-occupant `room@muc/focus` is
  /// dan de fallback zoals op de wire gezien.
  final String? focusJid;
  final String? sessionId;
}

// ── conference-IQ (http://jitsi.org/protocol/focus) ─────────────────────────

/// `focus.<domain>` tenzij de deployment `hosts.focus` anders declareerde.
String jitsiFocusJid(String domain, String? declaredFocus) =>
    (declaredFocus != null && declaredFocus.isNotEmpty)
    ? declaredFocus
    : 'focus.$domain';

/// De `<conference>`-payload van de `iq set` naar de focus. Jicofo vereist
/// `machine-uid` ("Missing mandatory attribute" zonder — de testbed-weigering
/// die dit attribuut afdwong); het is lib-jitsi-meet's device-id en blijft
/// daarom stabiel over een rejoin heen.
XmlElement buildConferenceRequest(String roomJid, String machineUid) =>
    xmppElement(
      'conference',
      namespace: jitsiFocusNs,
      attributes: {'room': roomJid, 'machine-uid': machineUid},
    );

/// Ontleed het `<conference>`-antwoord van de focus. `null` als het geen
/// conference-element is (een iq-error pakken we elders op).
JitsiConferenceReady? parseConferenceReply(XmlElement conference) {
  final ns = conference.getAttribute('xmlns') ?? conference.name.namespaceUri;
  if (conference.name.local != 'conference' || ns != jitsiFocusNs) return null;
  if (conference.getAttribute('ready') != 'true') return null;
  return JitsiConferenceReady(
    focusJid: _boundedAttr(conference, 'focusjid'),
    sessionId: _boundedAttr(conference, 'session-id'),
  );
}

// ── Jingle (urn:xmpp:jingle:1) ──────────────────────────────────────────────

/// Het `<jingle>`-element van een inbound iq, of null. Geen namespace-match =
/// geen Jingle (niet een contractfout — gewoon niet voor ons).
XmlElement? jingleElementOf(Iterable<XmlElement> children) {
  for (final e in children) {
    if (e.name.local == 'jingle' &&
        (e.getAttribute('xmlns') ?? e.name.namespaceUri) == jingleNs) {
      return e;
    }
  }
  return null;
}

/// Actie + sid van een jingle-element, zodat de sessie goedkoop dispatchen kan.
(String action, String sid)? jingleActionOf(XmlElement jingle) {
  final action = jingle.getAttribute('action');
  if (action == null) return null;
  return (action, jingle.getAttribute('sid') ?? '');
}

/// Ontleed een `session-initiate`-`<jingle>`. Werpt [JitsiContractException]
/// bij elk afwijkend contract — de caller mag dan NOOIT alsof-verbonden doen.
JingleSessionInitiate parseSessionInitiate(XmlElement jingle) {
  if (jingle.name.local != 'jingle' ||
      (jingle.getAttribute('xmlns') ?? jingle.name.namespaceUri) != jingleNs) {
    throw const JitsiContractException(
      JitsiContractIssue.notJingle,
      'geen urn:xmpp:jingle:1 element',
    );
  }
  if (jingle.getAttribute('action') != 'session-initiate') {
    throw JitsiContractException(
      JitsiContractIssue.malformedInitiate,
      'action=${jingle.getAttribute('action')}',
    );
  }
  final sid = _boundedAttr(jingle, 'sid');
  final initiator = _boundedAttr(jingle, 'initiator');
  if (sid == null || initiator == null) {
    throw const JitsiContractException(
      JitsiContractIssue.malformedInitiate,
      'sid/initiator ontbreekt',
    );
  }

  final bundle = <String>[];
  final contents = <JingleContent>[];
  String? sourcesJson;
  for (final child in jingle.childElements) {
    switch (child.name.local) {
      case 'group':
        if ((child.getAttribute('xmlns') ?? child.name.namespaceUri) ==
                jingleGroupNs &&
            child.getAttribute('semantics') == 'BUNDLE') {
          for (final c in child.childElements) {
            if (c.name.local == 'content') {
              final name = _boundedAttr(c, 'name');
              if (name != null) bundle.add(name);
            }
          }
        }
      case 'content':
        if (contents.length >= _maxContents) {
          throw const JitsiContractException(
            JitsiContractIssue.unknownContent,
            'te veel contents',
          );
        }
        contents.add(_parseContent(child));
      case 'json-message':
        final text = child.innerText;
        if (text.length <= _maxSourcesJson) sourcesJson = text;
    }
  }
  if (contents.isEmpty) {
    throw const JitsiContractException(
      JitsiContractIssue.malformedInitiate,
      'geen contents',
    );
  }
  if (bundle.isEmpty) {
    throw const JitsiContractException(
      JitsiContractIssue.missingBundle,
      'geen BUNDLE-group',
    );
  }
  return JingleSessionInitiate(
    sid: sid,
    initiator: initiator,
    contents: contents,
    bundleContents: bundle,
    sourcesJson: sourcesJson,
  );
}

JingleContent _parseContent(XmlElement content) {
  final name = _boundedAttr(content, 'name');
  if (name == null || (name != 'audio' && name != 'video' && name != 'data')) {
    throw JitsiContractException(
      JitsiContractIssue.unknownContent,
      'content=${content.getAttribute('name')}',
    );
  }
  XmlElement? description;
  XmlElement? transport;
  for (final e in content.childElements) {
    final ns = e.getAttribute('xmlns') ?? e.name.namespaceUri;
    if (e.name.local == 'description' && ns == jingleRtpNs) description = e;
    if (e.name.local == 'transport' && ns == jingleIceNs) transport = e;
  }
  final media = name == 'data'
      ? 'application'
      : description == null
      ? (throw JitsiContractException(
          JitsiContractIssue.missingDescription,
          'content=$name',
        ))
      : _boundedAttr(description, 'media') ??
            (throw JitsiContractException(
              JitsiContractIssue.missingDescription,
              'content=$name',
            ));
  if (transport == null ||
      _boundedAttr(transport, 'ufrag') == null ||
      _boundedAttr(transport, 'pwd') == null) {
    throw JitsiContractException(
      JitsiContractIssue.missingTransport,
      'content=$name',
    );
  }
  return JingleContent(
    name: name,
    media: media,
    senders: _boundedAttr(content, 'senders'),
    creator: _boundedAttr(content, 'creator'),
    payloads: description == null ? const [] : _parsePayloads(description),
    headerExtensions: description == null
        ? const []
        : _parseHeaderExtensions(description),
    rtcpMux:
        description?.childElements.any((e) => e.name.local == 'rtcp-mux') ??
        false,
    transport: _parseTransport(transport),
  );
}

List<JinglePayloadType> _parsePayloads(XmlElement description) {
  final out = <JinglePayloadType>[];
  for (final pt in description.childElements) {
    if (pt.name.local != 'payload-type') continue;
    if (out.length >= _maxPayloads) break;
    final id = _boundedAttr(pt, 'id');
    final name = _boundedAttr(pt, 'name');
    final clockrate = _boundedAttr(pt, 'clockrate');
    if (id == null || name == null || clockrate == null) continue;
    final parameters = <String, String>{};
    final rtcpFb = <String>[];
    for (final e in pt.childElements) {
      switch (e.name.local) {
        case 'parameter':
          final key = _boundedAttr(e, 'name');
          final value = _boundedAttr(e, 'value');
          if (key != null && value != null) parameters[key] = value;
        case 'rtcp-fb':
          final type = _boundedAttr(e, 'type');
          if (type != null) {
            final subtype = _boundedAttr(e, 'subtype');
            rtcpFb.add(subtype == null ? type : '$type $subtype');
          }
      }
    }
    out.add(
      JinglePayloadType(
        id: id,
        name: name,
        clockrate: clockrate,
        channels: _boundedAttr(pt, 'channels'),
        parameters: parameters,
        rtcpFb: rtcpFb,
      ),
    );
  }
  return out;
}

List<(String, String)> _parseHeaderExtensions(XmlElement description) {
  final out = <(String, String)>[];
  for (final e in description.childElements) {
    if (e.name.local != 'rtp-hdrext') continue;
    if (out.length >= _maxHeaderExtensions) break;
    final id = _boundedAttr(e, 'id');
    final uri = _boundedAttr(e, 'uri');
    if (id != null && uri != null) out.add((id, uri));
  }
  return out;
}

JingleTransport _parseTransport(XmlElement transport) {
  String? fingerprint;
  var hash = 'sha-256';
  var setup = 'actpass';
  String? sctpNumber;
  String? sctpStreams;
  final candidates = <JingleIceCandidate>[];
  for (final e in transport.childElements) {
    switch (e.name.local) {
      case 'fingerprint':
        final ns = e.getAttribute('xmlns') ?? e.name.namespaceUri;
        if (ns == jingleDtlsNs) {
          fingerprint = _bounded(e.innerText, _maxFingerprintLength);
          hash = _boundedAttr(e, 'hash') ?? hash;
          setup = _boundedAttr(e, 'setup') ?? setup;
        }
      case 'sctpmap':
        sctpNumber = _boundedAttr(e, 'number');
        sctpStreams = _boundedAttr(e, 'streams');
      case 'candidate':
        if (candidates.length >= _maxCandidates) break;
        final ip = _boundedAttr(e, 'ip');
        final port = _boundedAttr(e, 'port');
        if (ip == null || port == null) continue;
        candidates.add(
          JingleIceCandidate(
            ip: ip,
            port: port,
            foundation: _boundedAttr(e, 'foundation') ?? '1',
            component: _boundedAttr(e, 'component') ?? '1',
            protocol: _boundedAttr(e, 'protocol') ?? 'udp',
            priority: _boundedAttr(e, 'priority') ?? '0',
            type: _boundedAttr(e, 'type') ?? 'host',
            relAddr: _boundedAttr(e, 'rel-addr'),
            relPort: _boundedAttr(e, 'rel-port'),
            generation: _boundedAttr(e, 'generation') ?? '0',
            network: _boundedAttr(e, 'network') ?? '0',
          ),
        );
    }
  }
  if (fingerprint == null || hash != 'sha-256') {
    throw const JitsiContractException(
      JitsiContractIssue.missingFingerprint,
      'geen sha-256 fingerprint',
    );
  }
  if (candidates.isEmpty) {
    throw const JitsiContractException(
      JitsiContractIssue.missingCandidates,
      'geen ICE-kandidaten',
    );
  }
  return JingleTransport(
    ufrag: _boundedAttr(transport, 'ufrag')!,
    pwd: _boundedAttr(transport, 'pwd')!,
    fingerprint: fingerprint,
    fingerprintHash: hash,
    setup: setup,
    candidates: candidates,
    sctpNumber: sctpNumber,
    sctpStreams: sctpStreams,
  );
}

// ── bouwers: onze kant van de Jingle-uitwisseling ───────────────────────────

/// `<jingle action='session-accept'>` voor op een initiate, opgebouwd uit de
/// inhouden die de media-core onderhandelde ([contents]).
XmlElement buildSessionAccept({
  required String sid,
  required String initiator,
  required String responder,
  required List<JingleContent> contents,
  required List<String> bundleContents,
}) => xmppElement(
  'jingle',
  namespace: jingleNs,
  attributes: {
    'action': 'session-accept',
    'initiator': initiator,
    'responder': responder,
    'sid': sid,
  },
  children: [
    xmppElement(
      'group',
      namespace: jingleGroupNs,
      attributes: {'semantics': 'BUNDLE'},
      children: [
        for (final name in bundleContents)
          xmppElement('content', attributes: {'name': name}),
      ],
    ),
    for (final c in contents) _contentElement(c, creator: 'responder'),
  ],
);

/// `<jingle action='source-add'>` — meldt één eigen bron (SSRC + msid) aan de
/// focus, zoals de echte client na de accept doet.
XmlElement buildSourceAdd({
  required String sid,
  required String initiator,
  required String contentName,
  required String media,
  required String sourceName,
  required String ssrc,
  String? msid,
}) => xmppElement(
  'jingle',
  namespace: jingleNs,
  attributes: {'action': 'source-add', 'initiator': initiator, 'sid': sid},
  children: [
    xmppElement(
      'content',
      attributes: {'name': contentName},
      children: [
        xmppElement(
          'description',
          namespace: jingleRtpNs,
          attributes: {'media': media},
          children: [
            xmppElement(
              'source',
              namespace: jingleSsmaNs,
              attributes: {'name': sourceName, 'ssrc': ssrc},
              children: [
                if (msid != null)
                  xmppElement(
                    'parameter',
                    attributes: {'name': 'msid', 'value': msid},
                  ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// `<jingle action='session-terminate'>` — netjes afsluiten; reden is altijd
/// `success` bij een vrijwillig leave.
XmlElement buildSessionTerminate({required String sid}) => xmppElement(
  'jingle',
  namespace: jingleNs,
  attributes: {'action': 'session-terminate', 'sid': sid},
  children: [
    xmppElement('reason', children: [xmppElement('success')]),
  ],
);

XmlElement _contentElement(JingleContent c, {required String creator}) =>
    xmppElement(
      'content',
      attributes: {
        'name': c.name,
        'creator': creator,
        if (c.senders != null) 'senders': c.senders!,
      },
      children: [
        if (c.media != 'application')
          xmppElement(
            'description',
            namespace: jingleRtpNs,
            attributes: {'media': c.media},
            children: [
              for (final pt in c.payloads) _payloadElement(pt),
              if (c.rtcpMux) xmppElement('rtcp-mux'),
              for (final (id, uri) in c.headerExtensions)
                xmppElement(
                  'rtp-hdrext',
                  namespace: jingleHdrextNs,
                  attributes: {'id': id, 'uri': uri},
                ),
            ],
          ),
        if (c.transport != null) _transportElement(c.transport!),
      ],
    );

XmlElement _payloadElement(JinglePayloadType pt) => xmppElement(
  'payload-type',
  attributes: {
    'id': pt.id,
    'name': pt.name,
    'clockrate': pt.clockrate,
    if (pt.channels != null) 'channels': pt.channels!,
  },
  children: [
    for (final e in pt.parameters.entries)
      xmppElement('parameter', attributes: {'name': e.key, 'value': e.value}),
    for (final fb in pt.rtcpFb)
      xmppElement(
        'rtcp-fb',
        namespace: jingleRtcpFbNs,
        attributes: _rtcpFbAttrs(fb),
      ),
  ],
);

Map<String, String> _rtcpFbAttrs(String fb) {
  final i = fb.indexOf(' ');
  if (i < 0) return {'type': fb};
  return {'type': fb.substring(0, i), 'subtype': fb.substring(i + 1)};
}

XmlElement _transportElement(JingleTransport t) => xmppElement(
  'transport',
  namespace: jingleIceNs,
  attributes: {'ufrag': t.ufrag, 'pwd': t.pwd},
  children: [
    if (t.sctpNumber != null)
      xmppElement(
        'sctpmap',
        namespace: jingleSctpNs,
        attributes: {
          'number': t.sctpNumber!,
          'protocol': 'webrtc-datachannel',
          'streams': t.sctpStreams ?? '1024',
        },
      ),
    xmppElement(
      'fingerprint',
      namespace: jingleDtlsNs,
      attributes: {'hash': t.fingerprintHash, 'setup': t.setup},
      text: t.fingerprint,
    ),
    for (final c in t.candidates)
      xmppElement(
        'candidate',
        attributes: {
          'foundation': c.foundation,
          'component': c.component,
          'protocol': c.protocol,
          'priority': c.priority,
          'ip': c.ip,
          'port': c.port,
          'type': c.type,
          'generation': c.generation,
          'network': c.network,
          if (c.relAddr != null) 'rel-addr': c.relAddr!,
          if (c.relPort != null) 'rel-port': c.relPort!,
        },
      ),
  ],
);

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

/// Bouw onze eigen SourceInfo-tekst — `{"<nick>-a0":{"muted":false}}`.
String buildSourceInfo(Map<String, bool> mutedBySource) => jsonEncode({
  for (final e in mutedBySource.entries) e.key: {'muted': e.value},
});

// ── begrenzingen ────────────────────────────────────────────────────────────

const _maxContents = 8;
const _maxPayloads = 64;
const _maxHeaderExtensions = 32;
const _maxCandidates = 64;
const _maxSources = 64;
const _maxSourcesJson = 16384;
const _maxSourceInfoLength = 8192;
const _maxFingerprintLength = 256;
const _maxFieldLength = 3071; // RFC 6120 §3 JID-cap, hergebruikt

String? _bounded(String? v, int max) {
  if (v == null) return null;
  final t = v.trim();
  return (t.isEmpty || t.length > max) ? null : t;
}

String? _boundedAttr(XmlElement e, String name) =>
    _bounded(e.getAttribute(name), _maxFieldLength);
