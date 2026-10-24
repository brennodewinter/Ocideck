// Jingle ↔ SDP mapping (#2534), in both directions, modelled on the real
// testbed wire — not a general interop layer, exactly the two translations the
// Jitsi session needs:
//
//   * [jingleOfferToSdp] — synthesise the SDP *offer* from a parsed
//     `session-initiate`. The JVB is the offerer; libwebrtc only ever sees a
//     remote offer, so we never have to build a Jingle initiate ourselves.
//     The offer is BUNDLE-only (the contract check upstream already rejected
//     anything else): shared ice-ufrag/pwd/fingerprint on every m-line, JVB
//     candidates repeated per m-line, `a=mid:<content-name>` matching the
//     BUNDLE group, `a=sctp-port` for the data channel (the wire carries
//     `<sctpmap>`; libwebrtc speaks the modern form).
//
//   * [sdpAnswerToJingle] — parse the SDP *answer* libwebrtc produced and
//     rebuild the Jingle contents for `session-accept`. `senders` follows the
//     negotiated m-line direction the way XEP-0166 and the wire both do:
//     sendonly→responder, recvonly→initiator, sendrecv→both, inactive→none.
//     Our transport carries fingerprint + sctpmap and NO candidates — the
//     wire proves the JVB needs none (it learns our address peer-reflexive
//     from the STUN checks we send to its candidates).
//
//   * [extractLocalSources] — pull `a=ssrc:`/`a=msid:` per m-line from the
//     same answer; the session announces those as `source-add` under the
//     `<nick>-a0`/`-v0` source names (the wire's source-name signalling).
//
// Pure string work, bounded: SDP lines are processed capped and every field
// is length-checked — a hostile focus can only ever reach us through the
// already-bounded stanza layer, but the parse itself stays cheap regardless.

import 'jitsi_signaling.dart';

const _maxSdpLength = 262144;
const _maxSdpLines = 4096;

/// The session-level facts extracted from a Jingle initiate's transport:
/// every BUNDLEd content shares one ice-udp transport on the wire.
class _RemoteTransport {
  _RemoteTransport(this.ufrag, this.pwd, this.fingerprint, this.setup);

  final String ufrag;
  final String pwd;
  final String fingerprint;
  final String setup;
}

/// Synthesise the SDP offer libwebrtc must answer, from the parsed
/// `session-initiate`. Throws [JitsiContractException] on anything the
/// contract layer already guarantees (defence in depth, cheap).
String jingleOfferToSdp(JingleSessionInitiate initiate) {
  final first = initiate.contents.first.transport;
  if (first == null) {
    throw const JitsiContractException(
      JitsiContractIssue.missingTransport,
      'offer zonder transport',
    );
  }
  final remote = _RemoteTransport(
    first.ufrag,
    first.pwd,
    first.fingerprint,
    first.setup,
  );
  final out = StringBuffer()
    ..writeln('v=0')
    ..writeln('o=- ${initiate.sid} 0 IN IP4 ${first.candidates.first.ip}')
    ..writeln('s=-')
    ..writeln('t=0 0')
    ..writeln('a=group:BUNDLE ${initiate.bundleContents.join(' ')}')
    ..writeln('a=extmap-allow-mixed')
    ..writeln('a=msid-semantic:WMS *');

  for (final content in initiate.contents) {
    _writeMediaSection(out, content, remote);
  }
  return out.toString();
}

void _writeMediaSection(
  StringBuffer out,
  JingleContent content,
  _RemoteTransport remote,
) {
  final transport = content.transport;
  if (transport == null) {
    throw JitsiContractException(
      JitsiContractIssue.missingTransport,
      'content=${content.name}',
    );
  }
  final port = transport.candidates.first.port;
  if (content.media == 'application') {
    out.writeln('m=application $port UDP/DTLS/SCTP webrtc-datachannel');
  } else {
    final pts = content.payloads.map((p) => p.id).join(' ');
    out.writeln('m=${content.media} $port UDP/TLS/RTP/SAVPF $pts');
  }
  out
    ..writeln('c=IN IP4 ${transport.candidates.first.ip}')
    ..writeln('a=rtcp-mux')
    ..writeln('a=ice-ufrag:${transport.ufrag}')
    ..writeln('a=ice-pwd:${transport.pwd}')
    ..writeln(
      'a=fingerprint:${transport.fingerprintHash} '
      '${transport.fingerprint}',
    )
    ..writeln('a=setup:${transport.setup}')
    ..writeln('a=mid:${content.name}');
  if (content.media != 'application') {
    out.writeln('a=sendrecv');
    for (final (id, uri) in content.headerExtensions) {
      out.writeln('a=extmap:$id $uri');
    }
    for (final pt in content.payloads) {
      out.writeln(
        'a=rtpmap:${pt.id} ${pt.name}/${pt.clockrate}'
        '${pt.channels != null ? '/${pt.channels}' : ''}',
      );
      if (pt.parameters.isNotEmpty) {
        out.writeln(
          'a=fmtp:${pt.id} '
          '${pt.parameters.entries.map((e) => '${e.key}=${e.value}').join(';')}',
        );
      }
      for (final fb in pt.rtcpFb) {
        out.writeln('a=rtcp-fb:${pt.id} $fb');
      }
    }
  } else {
    // De wire draagt <sctpmap number='5000'>; libwebrtc beantwoordt de moderne
    // sctp-port-vorm. number ontbreekt → 5000, zoals de testbed stuurt.
    out.writeln('a=sctp-port:${transport.sctpNumber ?? '5000'}');
  }
  for (final cand in transport.candidates) {
    out.writeln(_candidateLine(cand));
  }
}

String _candidateLine(JingleIceCandidate c) {
  final buf = StringBuffer(
    'a=candidate:${c.foundation} ${c.component} ${c.protocol} '
    '${c.priority} ${c.ip} ${c.port} typ ${c.type}',
  );
  if (c.relAddr != null) buf.write(' raddr ${c.relAddr}');
  if (c.relPort != null) buf.write(' rport ${c.relPort}');
  buf.write(' generation ${c.generation}');
  return buf.toString();
}

// ── antwoord-SDP → Jingle ───────────────────────────────────────────────────

/// Eén m-sectie uit het SDP-antwoord dat libwebrtc maakte.
class SdpMediaSection {
  const SdpMediaSection({
    required this.media,
    required this.mid,
    required this.direction,
    required this.payloads,
    required this.headerExtensions,
    required this.rtcpMux,
    this.sctpPort,
    this.sources = const [],
  });

  final String media;
  final String mid;
  final String direction;
  final List<JinglePayloadType> payloads;
  final List<(String, String)> headerExtensions;
  final bool rtcpMux;
  final String? sctpPort;

  /// `(ssrc, msid)`-paren uit `a=ssrc:`/`a=msid:` — onze eigen zendbronnen.
  final List<({String ssrc, String? msid})> sources;
}

/// Het ontleedde SDP-antwoord van de lokale media-stack.
class SdpAnswer {
  const SdpAnswer({
    required this.ufrag,
    required this.pwd,
    required this.fingerprint,
    required this.setup,
    required this.sections,
  });

  final String ufrag;
  final String pwd;
  final String fingerprint;
  final String setup;
  final List<SdpMediaSection> sections;
}

/// Parse the answer libwebrtc produced. Only called on SDP our own stack
/// generated — still bounded and lenient: unknown attribute lines are
/// ignored, missing ICE credentials throw.
SdpAnswer parseSdpAnswer(String sdp) {
  if (sdp.length > _maxSdpLength) {
    throw const FormatException('sdp antwoord te groot');
  }
  final acc = _AnswerAccum();
  final sections = <SdpMediaSection>[];
  var lineCount = 0;

  for (final rawLine in sdp.split('\n')) {
    if (++lineCount > _maxSdpLines) {
      throw const FormatException('te veel sdp-regels');
    }
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('m=')) {
      final done = acc.flush();
      if (done != null) sections.add(done);
      acc.reset(line.substring(2).split(' ').first);
      continue;
    }
    if (!line.startsWith('a=')) continue;
    final body = line.substring(2);
    final colon = body.indexOf(':');
    acc.applyAttr(
      colon < 0 ? body : body.substring(0, colon),
      colon < 0 ? '' : body.substring(colon + 1),
    );
  }
  final done = acc.flush();
  if (done != null) sections.add(done);

  if (acc.ufrag == null || acc.pwd == null || acc.fingerprint == null) {
    throw const FormatException('sdp antwoord mist ICE-credentials');
  }
  return SdpAnswer(
    ufrag: acc.ufrag!,
    pwd: acc.pwd!,
    fingerprint: acc.fingerprint!,
    setup: acc.setup,
    sections: sections,
  );
}

/// De accumulatoren van [parseSdpAnswer]: één m-sectie tegelijk plus de
/// sessie-brede ICE/DTLS-velden (die op de wire óók per sectie kunnen
/// staan — BUNDLE herhaalt ze; de laatste wint, zoals bij de offer).
class _AnswerAccum {
  String? ufrag;
  String? pwd;
  String? fingerprint;
  var setup = 'active';

  String media = '';
  var mid = '';
  var direction = 'sendrecv';
  var rtcpMux = false;
  String? sctpPort;
  final payloads = <JinglePayloadType>[];
  final hdrexts = <(String, String)>[];
  final sources = <({String ssrc, String? msid})>[];
  final rtpmap = <String, (String, String, String?)>{};
  final fmtp = <String, Map<String, String>>{};
  final rtcpfb = <String, List<String>>{};
  final ssrcToMsid = <String, String>{};
  String? pendingMsid;

  void reset(String media) {
    this.media = media;
    mid = '';
    direction = 'sendrecv';
    rtcpMux = false;
    sctpPort = null;
    payloads.clear();
    hdrexts.clear();
    sources.clear();
    rtpmap.clear();
    fmtp.clear();
    rtcpfb.clear();
    ssrcToMsid.clear();
    pendingMsid = null;
  }

  /// Sluit de lopende sectie af: rtpmap+fmtp+rtcp-fb → payload-lijst,
  /// ssrc→msid → bronlijst. Null bij niets te doen (voorlopertext).
  SdpMediaSection? flush() {
    if (media.isEmpty) return null;
    for (final e in rtpmap.entries) {
      if (payloads.length >= 64) break;
      payloads.add(
        JinglePayloadType(
          id: e.key,
          name: e.value.$1,
          clockrate: e.value.$2,
          channels: e.value.$3,
          parameters: fmtp[e.key] ?? const {},
          rtcpFb: rtcpfb[e.key] ?? const [],
        ),
      );
    }
    for (final e in ssrcToMsid.entries) {
      sources.add((ssrc: e.key, msid: e.value));
    }
    return SdpMediaSection(
      media: media,
      mid: mid,
      direction: direction,
      payloads: List.unmodifiable(payloads),
      headerExtensions: List.unmodifiable(hdrexts),
      rtcpMux: rtcpMux,
      sctpPort: sctpPort,
      sources: List.unmodifiable(sources),
    );
  }

  void applyAttr(String attr, String value) {
    switch (attr) {
      case 'mid':
        mid = value.trim();
      case 'sendrecv' || 'sendonly' || 'recvonly' || 'inactive':
        direction = attr;
      case 'rtcp-mux':
        rtcpMux = true;
      case 'ice-ufrag':
        ufrag = value.trim();
      case 'ice-pwd':
        pwd = value.trim();
      case 'fingerprint':
        fingerprint = _fingerprintValue(value);
      case 'setup':
        setup = value.trim();
      case 'rtpmap':
        final sp = value.indexOf(' ');
        if (sp < 0) return;
        final id = value.substring(0, sp).trim();
        final parts = value.substring(sp + 1).split('/');
        if (parts.length >= 2) {
          rtpmap[id] = (parts[0], parts[1], parts.length > 2 ? parts[2] : null);
        }
      case 'fmtp':
        final sp = value.indexOf(' ');
        if (sp < 0) return;
        final id = value.substring(0, sp).trim();
        fmtp.putIfAbsent(id, () => {});
        for (final kv in value.substring(sp + 1).split(';')) {
          final eq = kv.indexOf('=');
          if (eq > 0) {
            fmtp[id]![kv.substring(0, eq).trim()] = kv.substring(eq + 1).trim();
          } else if (kv.trim().isNotEmpty) {
            fmtp[id]![kv.trim()] = '';
          }
        }
      case 'rtcp-fb':
        final sp = value.indexOf(' ');
        if (sp < 0) return;
        rtcpfb
            .putIfAbsent(value.substring(0, sp).trim(), () => [])
            .add(value.substring(sp + 1).trim());
      case 'extmap':
        final sp = value.indexOf(' ');
        if (sp < 0) return;
        if (hdrexts.length < 64) {
          hdrexts.add((value.substring(0, sp).trim(), value.substring(sp + 1)));
        }
      case 'sctp-port':
        sctpPort = value.trim();
      case 'msid':
        pendingMsid = value.trim();
      case 'ssrc':
        // `a=ssrc:<n> msid:<stream> <track>` — de msid kan óók los als
        // `a=msid:` staan; combineer beide vormen.
        final parts = value.trim().split(RegExp(r'\s+'));
        if (parts.isNotEmpty && parts.first.isNotEmpty) {
          final ssrc = parts.first;
          if (parts.length >= 3 && parts[1] == 'msid:') {
            ssrcToMsid[ssrc] = parts.sublist(2).join(' ');
          } else if (pendingMsid != null) {
            ssrcToMsid[ssrc] = pendingMsid!;
          } else {
            ssrcToMsid.putIfAbsent(ssrc, () => '');
          }
        }
    }
  }
}

/// `a=fingerprint:sha-256 AA:BB:…` → `sha-256`-waarde, of null bij een andere
/// hash — wij accepteren precies wat de Jingle-transport-laag toestaat.
String? _fingerprintValue(String value) {
  final parts = value.trim().split(RegExp(r'\s+'));
  if (parts.length != 2 || parts[0] != 'sha-256') return null;
  return parts[1];
}

/// De Jingle-contents voor onze `session-accept`, uit het ontleedde antwoord.
/// Volgorde = de BUNDLE-group van de initiate (de accept volgt het offer).
List<JingleContent> sdpAnswerToJingle(SdpAnswer answer) {
  return [
    for (final s in answer.sections)
      JingleContent(
        name: s.mid,
        media: s.media == 'application' ? 'application' : s.media,
        senders: switch (s.direction) {
          'sendrecv' => 'both',
          'sendonly' => 'responder',
          'recvonly' => 'initiator',
          _ => 'none',
        },
        payloads: s.payloads,
        headerExtensions: s.headerExtensions,
        rtcpMux: s.rtcpMux,
        transport: JingleTransport(
          ufrag: answer.ufrag,
          pwd: answer.pwd,
          fingerprint: answer.fingerprint,
          setup: 'active',
          sctpNumber: s.sctpPort,
        ),
      ),
  ];
}
