// De Jitsi-signalling-laag tegen de echte wire — de fixture is letterlijk
// het `session-initiate` dat Jicofo stuurde in de gepinde testbed
// (`testbed/jitsi-meet`, stable-11248, opgevangen via CDP-WebSocket). Niets
// is gemodelleerd of opgeschoond: als de parser deze slok aankan, werkt hij
// op wat de server werkelijk stuurt.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_participant.dart'
    show MeetingTrackKind;
import 'package:ocideck/meetings/providers/jitsi/jitsi_signaling.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_source_wire.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';
import 'package:xml/xml.dart';

/// Letterlijk de wire: `<iq set><jingle action='session-initiate' …>` van
/// `room@muc.meet.jitsi/focus`.
XmlElement _wireJingle() => XmlDocument.parse(
  '<iq type="set" id="i1">'
  '${File('test/fixtures/jitsi/session-initiate.xml').readAsStringSync()}'
  '</iq>',
).rootElement.childElements.first;

void main() {
  group('session-initiate (echte wire)', () {
    final initiate = parseSessionInitiate(_wireJingle());

    test('sid, initiator en BUNDLE-group kloppen', () {
      expect(initiate.sid, '9h90l0o8t59ro');
      expect(initiate.initiator, 'focus@auth.meet.jitsi/focus');
      expect(initiate.bundleContents, ['audio', 'video', 'data']);
    });

    test('drie contents met de juiste media-namen', () {
      expect(initiate.contents.map((c) => c.name), ['audio', 'video', 'data']);
      expect(initiate.contents[0].media, 'audio');
      expect(initiate.contents[1].media, 'video');
      expect(initiate.contents[2].media, 'application');
    });

    test('audio-description draagt payloads, parameters en rtcp-fb', () {
      final audio = initiate.contents.first;
      expect(
        audio.payloads.map((p) => p.name),
        containsAll(['opus', 'telephone-event']),
      );
      final opus = audio.payloads.firstWhere((p) => p.name == 'opus');
      expect(opus.id, '111');
      expect(opus.clockrate, '48000');
      expect(opus.channels, '2');
      expect(opus.parameters['useinbandfec'], '1');
      expect(opus.rtcpFb, contains('transport-cc'));
      expect(audio.headerExtensions, isNotEmpty);
      expect(audio.rtcpMux, isTrue);
    });

    test('transport draagt ufrag/pwd, sha-256 fingerprint en kandidaten', () {
      for (final c in initiate.contents) {
        final t = c.transport!;
        expect(t.ufrag, 'ce54q1k5ngadqa');
        expect(t.pwd, '4nrast64456ksecda5p6s6m07m');
        expect(t.fingerprintHash, 'sha-256');
        expect(t.fingerprint, startsWith('E2:82:98'));
        expect(t.candidates, isNotEmpty);
      }
      final audio = initiate.contents.first.transport!;
      expect(
        audio.candidates.map((c) => c.ip),
        containsAll(['172.20.0.5', '127.0.0.1']),
      );
    });

    test('de data-content draagt de sctpmap', () {
      final data = initiate.contents[2];
      expect(data.transport!.sctpNumber, '5000');
      expect(data.transport!.sctpStreams, '1024');
    });

    test('json-message met jvb-sources komt mee (begrensd)', () {
      expect(initiate.sourcesJson, contains('jvb-v0'));
      expect(initiate.sourcesJson, contains('3590870398'));
    });
  });

  group('contract-afwijzing', () {
    XmlElement wrap(String inner) => XmlDocument.parse(
      '<jingle xmlns="$jingleNs" action="session-initiate" '
      'sid="s" initiator="i">$inner</jingle>',
    ).rootElement;

    const bundle =
        '<group xmlns="$jingleGroupNs" semantics="BUNDLE">'
        '<content name="audio"/></group>';

    String content({
      String name = 'audio',
      String? description =
          '<description media="audio" xmlns="$jingleRtpNs">'
          '<payload-type id="111" name="opus" clockrate="48000"/>'
          '</description>',
      String? transport =
          '<transport xmlns="$jingleIceNs" ufrag="u" pwd="p">'
          '<fingerprint xmlns="$jingleDtlsNs" hash="sha-256">AA:BB</fingerprint>'
          '<candidate ip="1.2.3.4" port="10000"/>'
          '</transport>',
    }) =>
        '<content name="$name">${description ?? ''}${transport ?? ''}</content>';

    test('geen jingle-namespace → notJingle', () {
      expect(
        () => parseSessionInitiate(
          XmlDocument.parse('<jingle xmlns="urn:other"/>').rootElement,
        ),
        _contractThrows(JitsiContractIssue.notJingle),
      );
    });

    test('verkeerde action → malformedInitiate', () {
      expect(
        () => parseSessionInitiate(
          XmlDocument.parse(
            '<jingle xmlns="$jingleNs" action="session-terminate"/>',
          ).rootElement,
        ),
        _contractThrows(JitsiContractIssue.malformedInitiate),
      );
    });

    test('sid/initiator ontbreken → malformedInitiate', () {
      expect(
        () => parseSessionInitiate(
          XmlDocument.parse(
            '<jingle xmlns="$jingleNs" action="session-initiate">'
            '${content()}</jingle>',
          ).rootElement,
        ),
        _contractThrows(JitsiContractIssue.malformedInitiate),
      );
    });

    test('geen BUNDLE-group → missingBundle (fail closed)', () {
      expect(
        () => parseSessionInitiate(wrap(content())),
        _contractThrows(JitsiContractIssue.missingBundle),
      );
    });

    test('onbekende content → unknownContent', () {
      expect(
        () => parseSessionInitiate(
          wrap(
            '$bundle'
            '${content(name: 'chat', description: '<description media="chat" xmlns="$jingleRtpNs"/>')}',
          ),
        ),
        _contractThrows(JitsiContractIssue.unknownContent),
      );
    });

    test('rtp-content zonder description → missingDescription', () {
      expect(
        () =>
            parseSessionInitiate(wrap('$bundle${content(description: null)}')),
        _contractThrows(JitsiContractIssue.missingDescription),
      );
    });

    test('zonder transport → missingTransport', () {
      expect(
        () => parseSessionInitiate(wrap('$bundle${content(transport: null)}')),
        _contractThrows(JitsiContractIssue.missingTransport),
      );
    });

    test('andere fingerprint-hash → missingFingerprint', () {
      expect(
        () => parseSessionInitiate(
          wrap(
            '$bundle'
            '${content(transport: '<transport xmlns="$jingleIceNs" ufrag="u" pwd="p"><fingerprint xmlns="$jingleDtlsNs" hash="sha-1">AA</fingerprint><candidate ip="1.2.3.4" port="1"/></transport>')}',
          ),
        ),
        _contractThrows(JitsiContractIssue.missingFingerprint),
      );
    });

    test('zonder kandidaten → missingCandidates', () {
      expect(
        () => parseSessionInitiate(
          wrap(
            '$bundle'
            '${content(transport: '<transport xmlns="$jingleIceNs" ufrag="u" pwd="p"><fingerprint xmlns="$jingleDtlsNs" hash="sha-256">AA</fingerprint></transport>')}',
          ),
        ),
        _contractThrows(JitsiContractIssue.missingCandidates),
      );
    });
  });

  group('conference-IQ', () {
    test('buildConferenceRequest draagt room-JID + machine-uid', () {
      final el = buildConferenceRequest('kamer@muc.meet.jitsi', 'abc123');
      expect(el.name.local, 'conference');
      expect(el.getAttribute('room'), 'kamer@muc.meet.jitsi');
      // machine-uid is verplicht — jicofo weigert hem expliciet anders.
      expect(el.getAttribute('machine-uid'), 'abc123');
      expect(el.getAttribute('xmlns') ?? el.name.namespaceUri, jitsiFocusNs);
    });

    test('parseConferenceReply: ready → focusjid + session-id', () {
      final reply = parseConferenceReply(
        XmlDocument.parse(
          "<conference xmlns='$jitsiFocusNs' ready='true' "
          "focusjid='focus@auth.meet.jitsi/focus' session-id='abc'/>",
        ).rootElement,
      );
      expect(reply, isNotNull);
      expect(reply!.focusJid, 'focus@auth.meet.jitsi/focus');
      expect(reply.sessionId, 'abc');
    });

    test('parseConferenceReply: niet-ready of verkeerde ns → null', () {
      expect(
        parseConferenceReply(
          XmlDocument.parse("<conference xmlns='$jitsiFocusNs'/>").rootElement,
        ),
        isNull,
      );
      expect(
        parseConferenceReply(
          XmlDocument.parse(
            "<conference xmlns='urn:other' ready='true'/>",
          ).rootElement,
        ),
        isNull,
      );
    });

    test('jitsiFocusJid: conventie of gedeclareerde host', () {
      expect(jitsiFocusJid('meet.jitsi', null), 'focus.meet.jitsi');
      expect(jitsiFocusJid('meet.jitsi', 'f.example.org'), 'f.example.org');
    });
  });

  group('bouwers', () {
    test('buildSessionAccept: responder + BUNDLE + contents', () {
      final accept = buildSessionAccept(
        sid: 'sid1',
        initiator: 'focus@auth.meet.jitsi/focus',
        responder: 'me@guest.meet.jitsi/res',
        bundleContents: const ['audio', 'video'],
        contents: const [
          JingleContent(
            name: 'audio',
            media: 'audio',
            senders: 'both',
            rtcpMux: true,
            payloads: [
              JinglePayloadType(id: '111', name: 'opus', clockrate: '48000'),
            ],
            transport: JingleTransport(
              ufrag: 'u',
              pwd: 'p',
              fingerprint: 'AA:BB',
            ),
          ),
        ],
      );
      expect(accept.getAttribute('action'), 'session-accept');
      expect(accept.getAttribute('responder'), 'me@guest.meet.jitsi/res');
      final xml = accept.toXmlString();
      expect(xml, contains('BUNDLE'));
      expect(xml, contains('payload-type'));
      expect(xml, contains('fingerprint'));
    });

    test('buildSourceAdd: ssma-source met naam + ssrc + msid', () {
      final el = buildSourceAdd(
        sid: 'sid1',
        initiator: 'focus@auth.meet.jitsi/focus',
        contentName: 'audio',
        media: 'audio',
        sourceName: 'nick1-a0',
        ssrc: '42',
        msid: 'stream track',
      );
      expect(el.getAttribute('action'), 'source-add');
      final xml = el.toXmlString();
      expect(xml, contains(jingleSsmaNs));
      expect(xml, contains('nick1-a0'));
      expect(xml, contains('ssrc="42"'));
      expect(xml, contains('msid'));
    });

    test('buildSourceRemove: dezelfde source, actie remove, geen msid', () {
      final el = buildSourceRemove(
        sid: 'sid1',
        initiator: 'focus@auth.meet.jitsi/focus',
        contentName: 'video',
        media: 'video',
        sourceName: 'nick1-v0',
        ssrc: '43',
      );
      expect(el.getAttribute('action'), 'source-remove');
      final xml = el.toXmlString();
      expect(xml, contains(jingleSsmaNs));
      expect(xml, contains('nick1-v0'));
      expect(xml, contains('ssrc="43"'));
    });

    test('buildSessionTerminate draagt reason success', () {
      final el = buildSessionTerminate(sid: 'sid1');
      expect(el.getAttribute('action'), 'session-terminate');
      expect(el.toXmlString(), contains('success'));
    });
  });

  group('SourceInfo', () {
    test('parse: echte wire-vormen', () {
      expect(parseSourceInfo('{}'), isEmpty);
      expect(parseSourceInfo('{"e5a25d0e-a0":{"muted":false}}'), {
        'e5a25d0e-a0': false,
      });
      expect(
        parseSourceInfo('{"n-a0":{"muted":true},"n-v0":{"muted":false}}'),
        {'n-a0': true, 'n-v0': false},
      );
    });

    test('parse: kapot of vreemd → {} (onbekend, nooit verzonnen)', () {
      expect(parseSourceInfo(null), isEmpty);
      expect(parseSourceInfo(''), isEmpty);
      expect(parseSourceInfo('not json'), isEmpty);
      expect(parseSourceInfo('[1,2]'), isEmpty);
      expect(parseSourceInfo('{"a":1}'), isEmpty);
      expect(parseSourceInfo('{"a":{"muted":"yes"}}'), isEmpty);
      // onbegrensd → ook {} (grootte-begrenzing)
      expect(parseSourceInfo('{"k":{"muted":true}${',' * 9000}}'), isEmpty);
    });

    test('buildSourceInfo → parseSourceInfo roundtrip', () {
      final text = buildSourceInfo({'nick-a0': false, 'nick-v0': true});
      expect(text, '{"nick-a0":{"muted":false},"nick-v0":{"muted":true}}');
      expect(parseSourceInfo(text), {'nick-a0': false, 'nick-v0': true});
    });

    test(
      'videoType markeert de schermdeel-bron; zonder is het camera (#2537)',
      () {
        final text = buildSourceInfo(
          {'nick-a0': false, 'nick-v0': false},
          videoType: {'nick-v0': 'desktop'},
        );
        expect(
          text,
          '{"nick-a0":{"muted":false},'
          '"nick-v0":{"muted":false,"videoType":"desktop"}}',
        );
        expect(parseSourceVideoTypes(text), {'nick-v0': 'desktop'});
        // Parse-fail-closed zoals bij muted: kapot of vreemd → {}.
        expect(parseSourceVideoTypes(null), isEmpty);
        expect(parseSourceVideoTypes('{"v":{"videoType":3}}'), isEmpty);
      },
    );
  });

  group('json-sources', () {
    // De echte wire-vorm van de testbed (source-add json-message van de
    // bridge): per endpoint een geneste array van {s,n,m}-paren.
    const wire =
        '{"sources":{"2d02ebba":['
        '[{"s":4059687427,"n":"2d02ebba-v0","m":"st tr"},'
        '{"s":2915792709,"n":"2d02ebba-v0","m":"st tr"}],'
        '[["f",4059687427,2915792709]],'
        '[{"s":1234995088,"n":"2d02ebba-a0","m":"st tr"}]]}}';

    test('parseJsonSources: ssrc→(endpoint, naam, soort)', () {
      final sources = parseJsonSources(wire);
      expect(sources, hasLength(3));
      expect(sources[0].ssrc, 4059687427);
      expect(sources[0].endpoint, '2d02ebba');
      expect(sources[0].sourceName, '2d02ebba-v0');
      expect(sources[0].kind, MeetingTrackKind.video);
      expect(sources[2].kind, MeetingTrackKind.audio);
      // ssrc-groepen (["f",…]) zijn géén bronnen — die vallen weg.
      expect(sources.where((s) => s.ssrc == 2915792709), hasLength(1));
    });

    test('parseJsonSources: kapot of vreemd → geen bronnen', () {
      expect(parseJsonSources(null), isEmpty);
      expect(parseJsonSources(''), isEmpty);
      expect(parseJsonSources('not json'), isEmpty);
      expect(parseJsonSources('{"a":1}'), isEmpty);
      expect(parseJsonSources('{"sources":{"e":[{"s":"x"}]}}'), isEmpty);
    });

    test('parseForwardedSources: de echte berichten van de bridge', () {
      expect(
        parseForwardedSources(
          '{"colibriClass":"ForwardedSources","forwardedSources":["e-v0"]}',
        ),
        ['e-v0'],
      );
      expect(
        parseForwardedSources(
          '{"colibriClass":"ForwardedSources","forwardedSources":[]}',
        ),
        isEmpty,
      );
      // Andere bridge-berichten zijn géén ForwardedSources → null.
      expect(parseForwardedSources('{"colibriClass":"ServerHello"}'), isNull);
      expect(parseForwardedSources('not json'), isNull);
    });
  });

  group('jingle-dispatch helpers', () {
    test('jingleElementOf vindt het element, anders null', () {
      final children = [
        xmppElement('other'),
        xmppElement('jingle', namespace: jingleNs),
      ];
      expect(jingleElementOf(children), isNotNull);
      expect(jingleElementOf([xmppElement('other')]), isNull);
      expect(
        jingleElementOf([xmppElement('jingle', namespace: 'urn:other')]),
        isNull,
      );
    });

    test('jingleActionOf geeft (action, sid)', () {
      final (a, sid) = jingleActionOf(
        xmppElement(
          'jingle',
          namespace: jingleNs,
          attributes: {'action': 'session-terminate', 'sid': 's9'},
        ),
      )!;
      expect(a, 'session-terminate');
      expect(sid, 's9');
      expect(jingleActionOf(xmppElement('jingle')), isNull);
    });
  });
}

Matcher _contractThrows(JitsiContractIssue issue) => throwsA(
  isA<JitsiContractException>().having((e) => e.issue, 'issue', issue),
);
