// Jingle↔SDP-vertaling (#2534): de gesynthetiseerde offer uit een echte
// session-initiate, en de terugweg van een libwebrtc-achtig antwoord naar
// Jingle-contents. De offer-test gebruikt dezelfde wire-fixture als de
// signalling-tests — zo blijft de hele keten aan één echte opname geknoopt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_sdp.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_signaling.dart';
import 'package:xml/xml.dart';

JingleSessionInitiate _wireInitiate() => parseSessionInitiate(
  XmlDocument.parse(
    '<iq type="set" id="i1">'
    '${File('test/fixtures/jitsi/session-initiate.xml').readAsStringSync()}'
    '</iq>',
  ).rootElement.childElements.first,
);

/// Een libwebrtc-achtig antwoord op de wire-offer: zelfde m-lijnen, eigen
/// ICE-credentials en fingerprint, en (op de audio) een a=ssrc+msid — wat een
/// echt antwoord ook draagt.
const _answer = '''
v=0
o=- 12345 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE audio video data
a=msid-semantic: WMS mystream
m=audio 9 UDP/TLS/RTP/SAVPF 111 126
c=IN IP4 0.0.0.0
a=rtcp-mux
a=ice-ufrag:Ithj
a=ice-pwd:Vb8iEufnNgrGd5Tv5KPzCq04
a=fingerprint:sha-256 9A:9C:B8:A3:60:1E:59:45:7E:35:46:FA:D5:C8:07:71:DB:B8:56:F0:68:A9:B3:E7:31:39:97:77:B5:4F:5A:32
a=setup:active
a=mid:audio
a=sendrecv
a=msid:mystream tracka
a=rtpmap:111 opus/48000/2
a=rtpmap:126 telephone-event/8000
a=fmtp:111 minptime=10;useinbandfec=1
a=rtcp-fb:111 transport-cc
a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level
a=ssrc:4242 cname:cname1
a=ssrc:4242 msid:mystream tracka
m=video 9 UDP/TLS/RTP/SAVPF 41 100
c=IN IP4 0.0.0.0
a=rtcp-mux
a=ice-ufrag:Ithj
a=ice-pwd:Vb8iEufnNgrGd5Tv5KPzCq04
a=fingerprint:sha-256 9A:9C:B8:A3:60:1E:59:45:7E:35:46:FA:D5:C8:07:71:DB:B8:56:F0:68:A9:B3:E7:31:39:97:77:B5:4F:5A:32
a=setup:active
a=mid:video
a=recvonly
a=rtpmap:41 AV1/90000
a=rtpmap:100 VP8/90000
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:Ithj
a=ice-pwd:Vb8iEufnNgrGd5Tv5KPzCq04
a=fingerprint:sha-256 9A:9C:B8:A3:60:1E:59:45:7E:35:46:FA:D5:C8:07:71:DB:B8:56:F0:68:A9:B3:E7:31:39:97:77:B5:4F:5A:32
a=setup:active
a=mid:data
a=sctp-port:5000
''';

void main() {
  group('jingleOfferToSdp (echte wire-initiate)', () {
    final sdp = jingleOfferToSdp(_wireInitiate());
    final lines = sdp.split('\n');

    test('BUNDLE-group met de drie content-namen', () {
      expect(lines, contains('a=group:BUNDLE audio video data'));
    });

    test('drie m-lijnen met de juiste media/protocollen', () {
      expect(lines.where((l) => l.startsWith('m=')), [
        startsWith('m=audio 10000 UDP/TLS/RTP/SAVPF 111 126'),
        startsWith(
          'm=video 10000 UDP/TLS/RTP/SAVPF 41 100 107 101 42 96 97 99',
        ),
        'm=application 10000 UDP/DTLS/SCTP webrtc-datachannel',
      ]);
    });

    test('elke sectie draagt de JVB-transportfeiten', () {
      expect(lines.where((l) => l == 'a=ice-ufrag:ce54q1k5ngadqa').length, 3);
      expect(
        lines.where((l) => l == 'a=ice-pwd:4nrast64456ksecda5p6s6m07m').length,
        3,
      );
      expect(
        lines
            .where((l) => l.startsWith('a=fingerprint:sha-256 E2:82:98'))
            .length,
        3,
      );
      expect(lines.where((l) => l == 'a=setup:actpass').length, 3);
      expect(
        lines
            .where(
              (l) => l.startsWith('a=candidate:') && l.contains(' typ host'),
            )
            .length,
        3,
      );
    });

    test('mid-waarden volgen de BUNDLE-namen; data krijgt sctp-port', () {
      expect(lines, containsAll(['a=mid:audio', 'a=mid:video', 'a=mid:data']));
      expect(lines, contains('a=sctp-port:5000'));
    });

    test('rtpmap/fmtp/rtcp-fb/extmap komen over', () {
      expect(lines, contains('a=rtpmap:111 opus/48000/2'));
      expect(lines, contains('a=fmtp:111 minptime=10;useinbandfec=1'));
      expect(lines, contains('a=rtcp-fb:111 transport-cc'));
      expect(
        lines.any(
          (l) => l.startsWith(
            'a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level',
          ),
        ),
        isTrue,
      );
    });

    test('srflx-kandidaat draagt raddr/rport', () {
      expect(
        lines.any(
          (l) =>
              l.contains('127.0.0.1') &&
              l.contains('raddr 172.20.0.5') &&
              l.contains('rport 10000'),
        ),
        isTrue,
      );
    });
  });

  group('parseSdpAnswer', () {
    final answer = parseSdpAnswer(_answer);

    test('ICE-credentials en fingerprint', () {
      expect(answer.ufrag, 'Ithj');
      expect(answer.pwd, 'Vb8iEufnNgrGd5Tv5KPzCq04');
      expect(answer.fingerprint, startsWith('9A:9C:B8'));
      expect(answer.setup, 'active');
    });

    test('drie secties met mid, richting en payloads', () {
      expect(answer.sections.map((s) => s.mid), ['audio', 'video', 'data']);
      expect(answer.sections[0].direction, 'sendrecv');
      expect(answer.sections[1].direction, 'recvonly');
      expect(answer.sections[0].payloads.map((p) => p.name), [
        'opus',
        'telephone-event',
      ]);
      expect(answer.sections[1].payloads.map((p) => p.name), ['AV1', 'VP8']);
      expect(answer.sections[2].sctpPort, '5000');
    });

    test('ssrc+msid komen als bronnen over', () {
      expect(answer.sections[0].sources, [
        (ssrc: '4242', msid: 'mystream tracka'),
      ]);
    });

    test('mist ICE-credentials → FormatException', () {
      expect(
        () => parseSdpAnswer('v=0\nm=audio 9 UDP/TLS/RTP/SAVPF 111\n'),
        throwsFormatException,
      );
    });
  });

  group('sdpAnswerToJingle', () {
    final contents = sdpAnswerToJingle(parseSdpAnswer(_answer));

    test('drie contents met XEP-0166 senders-mapping', () {
      expect(contents.map((c) => c.name), ['audio', 'video', 'data']);
      expect(contents[0].senders, 'both'); // sendrecv → both
      expect(contents[1].senders, 'initiator'); // recvonly → initiator
      expect(contents[2].media, 'application');
    });

    test('transport draagt onze credentials zonder kandidaten', () {
      for (final c in contents) {
        expect(c.transport!.ufrag, 'Ithj');
        expect(c.transport!.fingerprint, startsWith('9A:9C:B8'));
        expect(c.transport!.setup, 'active');
        // De client stuurt NOOIT kandidaten — de JVB leert ons adres
        // peer-reflexive (de wire toont geen enkele client-candidate).
        expect(c.transport!.candidates, isEmpty);
      }
      expect(contents[2].transport!.sctpNumber, '5000');
    });

    test('contents serialiseren naar een accept-achtige jingle', () {
      final accept = buildSessionAccept(
        sid: 's',
        initiator: 'i',
        responder: 'r',
        contents: contents,
        bundleContents: const ['audio', 'video', 'data'],
      ).toXmlString();
      expect(accept, contains('session-accept'));
      expect(accept, contains('BUNDLE'));
      expect(accept, contains('sctpmap'));
    });
  });

  test('roundtrip: offer → (libwebrtc-antwoord) → jingle-contents', () {
    // Bewijst dat de twee vertalingen op elkaar aansluiten: een echte
    // initiate wordt SDP, een antwoord wordt weer Jingle.
    final offerSdp = jingleOfferToSdp(_wireInitiate());
    expect(offerSdp, contains('m=application'));
    final contents = sdpAnswerToJingle(parseSdpAnswer(_answer));
    expect(
      contents.map((c) => c.name),
      containsAll(['audio', 'video', 'data']),
    );
  });
}
