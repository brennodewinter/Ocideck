// De Jitsi-sessie-orchestrator (#2534) tegen een gescripte XMPP-kanaal en
// een fake media-core: de volledige join-volgorde, roster-events, mute,
// chat, leave en elke faalweg — alles behalve het echte netwerk en libwebrtc.
// De stanza's die de fake terugstuurt zijn de echte wire-vormen uit de
// testbed-capture (presence `<x muc#user>` + status 110, conference-ready,
// de session-initiate-fixture).

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_media_core.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_session.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_signaling.dart';
import 'package:ocideck/xmpp/xmpp_session.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';
import 'package:xml/xml.dart';

const _roomJid = 'kamer@muc.meet.jitsi';
const _mucUserNs = 'http://jabber.org/protocol/muc#user';
const _mucNs = 'http://jabber.org/protocol/muc';
const _nick = 'ocideck';

String _wireInitiateIq() =>
    '<iq type="set" from="$_roomJid/focus" id="init1">'
    '${File('test/fixtures/jitsi/session-initiate.xml').readAsStringSync()}'
    '</iq>';

/// De SDP die onze fake media-core als antwoord "onderhandelt".
const _answerSdp = '''
v=0
o=- 1 2 IN IP4 127.0.0.1
s=-
t=0 0
a=group:BUNDLE audio video data
m=audio 9 UDP/TLS/RTP/SAVPF 111 126
c=IN IP4 0.0.0.0
a=rtcp-mux
a=ice-ufrag:lu
a=ice-pwd:lpw
a=fingerprint:sha-256 9A:9C:B8:A3:60:1E:59:45
a=setup:active
a=mid:audio
a=sendrecv
a=rtpmap:111 opus/48000/2
a=rtpmap:126 telephone-event/8000
m=video 9 UDP/TLS/RTP/SAVPF 41
c=IN IP4 0.0.0.0
a=rtcp-mux
a=ice-ufrag:lu
a=ice-pwd:lpw
a=fingerprint:sha-256 9A:9C:B8:A3:60:1E:59:45
a=setup:active
a=mid:video
a=sendrecv
a=rtpmap:41 AV1/90000
m=application 9 UDP/DTLS/SCTP webrtc-datachannel
c=IN IP4 0.0.0.0
a=ice-ufrag:lu
a=ice-pwd:lpw
a=fingerprint:sha-256 9A:9C:B8:A3:60:1E:59:45
a=setup:active
a=mid:data
a=sctp-port:5000
''';

/// Een kanaal dat als de testbed-server meespeelt: beantwoordt de
/// conference-IQ, spiegelt de join-presence terug met de `<x muc#user>`-
/// vorm uit de wire, stuurt desgevraagd de echte session-initiate en ackt
/// jingle-sets met een leeg result — zoals Prosody/Jicofo deden.
class ScriptedJitsiChannel implements XmppStanzaChannel {
  ScriptedJitsiChannel({
    this.conferenceError,
    this.sendInitiate = true,
    this.selfJoinError,
  });

  final inbound = StreamController<Stanza>.broadcast();
  final sent = <Stanza>[];

  /// Error-condition voor de conference-IQ ('not-authorized', …).
  String? conferenceError;

  /// Stuur de session-initiate na onze join-presence.
  bool sendInitiate;

  /// Error-presence die de MUC-join afbreekt (bijv. 'not-allowed').
  String? selfJoinError;

  @override
  String? boundJid = 'me@guest.meet.jitsi/res';

  @override
  Stream<Stanza> get stanzas => inbound.stream;

  @override
  void sendStanza(Stanza s) {
    sent.add(s);
    bool has(String local) => s.children.any((e) => e.name.local == local);
    if (s.kind == StanzaKind.iq && s.type == 'set' && has('conference')) {
      if (conferenceError != null) {
        _reply(
          Stanza.parse(
            "<iq type='error' id='${s.id}'>"
            "<error type='auth'><$conferenceError xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></iq>",
          ),
        );
      } else {
        _reply(
          Stanza(
            kind: StanzaKind.iq,
            type: 'result',
            id: s.id,
            from: 'focus.meet.jitsi',
            children: [
              xmppElement(
                'conference',
                namespace: jitsiFocusNs,
                attributes: {
                  'ready': 'true',
                  'focusjid': 'focus@auth.meet.jitsi/focus',
                  'session-id': 'sess1',
                },
              ),
            ],
          ),
        );
      }
      return;
    }
    if (s.kind == StanzaKind.iq && s.type == 'set' && has('jingle')) {
      _reply(Stanza(kind: StanzaKind.iq, type: 'result', id: s.id));
      return;
    }
    if (s.kind == StanzaKind.presence) {
      final isJoin = s.children.any(
        (e) =>
            e.name.local == 'x' &&
            (e.getAttribute('xmlns') ?? e.name.namespaceUri) == _mucNs,
      );
      if (!isJoin || s.to == null) return;
      if (selfJoinError != null) {
        _reply(
          Stanza.parse(
            "<presence type='error' from='${s.to}'>"
            "<error type='cancel'><$selfJoinError xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/></error></presence>",
          ),
        );
        return;
      }
      // De self-presence zoals de MUC hem terugspiegelt (status 110 = self).
      _reply(
        Stanza.parse(
          "<presence from='${s.to}'>"
          "<x xmlns='$_mucUserNs'><item affiliation='none' role='participant'/>"
          "<status code='110'/><status code='100'/></x></presence>",
        ),
      );
      if (sendInitiate) _reply(Stanza.parse(_wireInitiateIq()));
    }
  }

  void inject(Stanza s) {
    if (!inbound.isClosed) inbound.add(s);
  }

  /// Auto-antwoorden gaan als microtask — een synchrone reply zou verstuurd
  /// worden vóór `_awaitIq` zijn listener installeert (de broadcast-stream
  /// zou hem dan verliezen). De echte sessie heeft die race niet: netwerk
  /// is van nature asynchroon.
  void _reply(Stanza s) => unawaited(Future.microtask(() => inject(s)));

  void drop() {
    if (!inbound.isClosed) unawaited(inbound.close());
  }

  List<Stanza> get iqSets =>
      sent.where((s) => s.kind == StanzaKind.iq && s.type == 'set').toList();

  Stanza? get lastPresence =>
      sent.reversed.where((s) => s.kind == StanzaKind.presence).firstOrNull;
}

class FakeMediaCore implements MeetingMediaCore {
  final conn = FakeMediaConnection();
  var openCount = 0;

  @override
  MeetingE2eeStatus get mediaE2ee => MeetingE2eeStatus.off;

  @override
  Future<bool> selfTest() async => true;

  @override
  Future<MeetingMediaConnection> openConnection({
    List<MeetingIceServer> iceServers = const [],
  }) async {
    openCount++;
    return conn;
  }

  @override
  Future<void> dispose() async {}
}

class FakeMediaConnection implements MeetingMediaConnection {
  final _remoteTracks = StreamController<MeetingRemoteTrack>.broadcast();
  final _liveness = StreamController<MeetingMediaLiveness>.broadcast();
  final enabledCalls = <(String, bool)>[];
  var audioSsrc = 4242;
  var videoSsrc = 4343;
  var allowAudio = true;
  var allowVideo = true;
  var closed = false;
  String? offerSdp;

  @override
  Stream<MeetingRemoteTrack> get remoteTracks => _remoteTracks.stream;

  @override
  Stream<MeetingMediaLiveness> get liveness => _liveness.stream;

  @override
  MeetingMediaLiveness currentLiveness = MeetingMediaLiveness.connecting;

  @override
  Future<({String trackId, int? ssrc})?> addLocalAudio() async =>
      allowAudio ? (trackId: 'ta', ssrc: audioSsrc) : null;

  @override
  Future<({String trackId, int? ssrc})?> addLocalVideo() async =>
      allowVideo ? (trackId: 'tv', ssrc: videoSsrc) : null;

  @override
  Future<void> setLocalTrackEnabled(
    String trackId, {
    required bool enabled,
  }) async => enabledCalls.add((trackId, enabled));

  @override
  Future<void> applyRemoteOffer(String sdp) async => offerSdp = sdp;

  @override
  Future<String> completeAnswer() async => _answerSdp;

  @override
  Future<void> close() async {
    closed = true;
    emitLiveness(MeetingMediaLiveness.closed);
  }

  void goLive() => emitLiveness(MeetingMediaLiveness.live);

  void emitLiveness(MeetingMediaLiveness l) {
    currentLiveness = l;
    if (!_liveness.isClosed) _liveness.add(l);
  }

  void emitTrack(MeetingRemoteTrack t) => _remoteTracks.add(t);
}

/// Wacht tot [pred] op de verzonden stanzas uitkomt — de join is asynchroon
/// en de fake antwoordt synchroon via de broadcast-stream.
Future<void> _until(
  ScriptedJitsiChannel ch,
  bool Function(Stanza) pred, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (ch.sent.any(pred)) return;
    await pumpEventQueue();
  }
  fail(
    'geen stanza gezien die aan de verwachting voldeed (sent: '
    '${ch.sent.map((s) => '${s.kind.name}:${s.children.isEmpty ? '' : s.children.first.name.local}').join(', ')})',
  );
}

XmlElement? _sourceInfoOf(Stanza presence) {
  for (final e in presence.children) {
    if (e.name.local == 'SourceInfo') return e;
  }
  return null;
}

void main() {
  late ScriptedJitsiChannel channel;
  late FakeMediaCore mediaCore;
  var sessionClosed = false;

  setUp(() {
    channel = ScriptedJitsiChannel();
    mediaCore = FakeMediaCore();
    sessionClosed = false;
  });

  Future<JitsiMeetingSession> start({
    bool startMuted = true,
    bool startCameraOff = true,
  }) => JitsiMeetingSession.start(
    channel: channel,
    mediaCore: mediaCore,
    roomJid: _roomJid,
    focusJid: 'focus.meet.jitsi',
    displayName: 'Brenno',
    startMuted: startMuted,
    startCameraOff: startCameraOff,
    closeSession: () async => sessionClosed = true,
    nickFactory: () => _nick,
    conferenceTimeout: const Duration(milliseconds: 400),
    initiateTimeout: const Duration(milliseconds: 400),
    iceTimeout: const Duration(milliseconds: 400),
    mucTimeout: const Duration(milliseconds: 400),
  );

  /// Rijdt de join door tot de accept verstuurd is en zet daarna de ICE
  /// live — dan mag `start()` pas connected teruggeven.
  Future<JitsiMeetingSession> joinLive({
    bool startMuted = true,
    bool startCameraOff = true,
  }) async {
    final future = start(
      startMuted: startMuted,
      startCameraOff: startCameraOff,
    );
    await _until(
      channel,
      (s) =>
          s.kind == StanzaKind.iq &&
          s.children.any(
            (e) =>
                e.name.local == 'jingle' &&
                e.getAttribute('action') == 'session-accept',
          ),
    );
    mediaCore.conn.goLive();
    return future;
  }

  group('join-volgorde (de echte wire)', () {
    test(
      'conference → muc-presence → accept → presence → source-add → live',
      () async {
        final session = await joinLive(startMuted: false);
        addTearDown(() => session.leave());

        final kinds = channel.sent
            .map(
              (s) => switch (s.kind) {
                StanzaKind.iq
                    when s.children.any((e) => e.name.local == 'conference') =>
                  'conference',
                StanzaKind.iq
                    when s.children.any((e) => e.name.local == 'jingle') =>
                  'jingle:${s.children.firstWhere((e) => e.name.local == 'jingle').getAttribute('action')}',
                StanzaKind.presence => 'presence',
                _ => s.kind.name,
              },
            )
            .toList();
        expect(kinds.first, 'conference');
        // De join-presence volgt; accept komt na de initiate.
        expect(
          kinds.indexOf('presence'),
          lessThan(kinds.indexOf('jingle:session-accept')),
        );
        // Na de accept: een presence-update met SourceInfo + source-add's.
        final acceptI = kinds.indexOf('jingle:session-accept');
        expect(kinds.indexOf('presence', acceptI + 1), greaterThan(acceptI));
        expect(kinds, contains('jingle:source-add'));

        expect(session.connectionState, MeetingConnectionState.connected);
        expect(
          channel.sent
              .firstWhere(
                (s) => s.children.any((e) => e.name.local == 'conference'),
              )
              .to,
          'focus.meet.jitsi',
        );
        final accept = channel.sent.firstWhere(
          (s) => s.children.any(
            (e) =>
                e.name.local == 'jingle' &&
                e.getAttribute('action') == 'session-accept',
          ),
        );
        expect(accept.to, '$_roomJid/focus');
      },
    );

    test(
      'de accept draagt onze contents + BUNDLE; source-add de ssrc',
      () async {
        final session = await joinLive();
        addTearDown(() => session.leave());

        final acceptEl = channel.sent
            .firstWhere(
              (s) => s.children.any(
                (e) =>
                    e.name.local == 'jingle' &&
                    e.getAttribute('action') == 'session-accept',
              ),
            )
            .children
            .first;
        expect(acceptEl.getAttribute('sid'), '9h90l0o8t59ro');
        expect(acceptEl.getAttribute('responder'), 'me@guest.meet.jitsi/res');
        expect(acceptEl.toXmlString(), contains('BUNDLE'));
        expect(acceptEl.toXmlString(), contains('rtcp-mux'));

        final sourceAdd = channel.sent.firstWhere(
          (s) => s.children.any(
            (e) =>
                e.name.local == 'jingle' &&
                e.getAttribute('action') == 'source-add',
          ),
        );
        final xml = sourceAdd.children.first.toXmlString();
        expect(xml, contains('$_nick-a0'));
        expect(xml, contains('ssrc="4242"'));
      },
    );

    test('presence draagt de SourceInfo-mute-kaart', () async {
      final session = await joinLive(startMuted: true);
      addTearDown(() => session.leave());
      final sourceInfo = _sourceInfoOf(channel.lastPresence!);
      expect(sourceInfo, isNotNull);
      expect(parseSourceInfo(sourceInfo!.innerText), {'$_nick-a0': true});
    });

    test('lokale participant staat in de roster met eerlijke staat', () async {
      final session = await joinLive(startMuted: true);
      addTearDown(() => session.leave());
      final local = session.participants.singleWhere((p) => p.isLocal);
      expect(local.id, _nick);
      expect(local.displayName, 'Brenno');
      expect(local.micMuted, isTrue);
      expect(local.camOff, isTrue);
    });

    test('geen mediapad → join faalt, nooit "verbonden" claimen', () async {
      final future = start();
      await _until(
        channel,
        (s) => s.children.any(
          (e) =>
              e.name.local == 'jingle' &&
              e.getAttribute('action') == 'session-accept',
        ),
      );
      await expectLater(
        future,
        throwsA(
          isA<MeetingJoinException>().having(
            (e) => e.reason,
            'reason',
            MeetingFailureReason.providerUnavailable,
          ),
        ),
      );
      expect(mediaCore.conn.closed, isTrue);
      expect(sessionClosed, isTrue);
    });

    test(
      'not-authorized op conference mag door (de echte gast-wire)',
      () async {
        channel.conferenceError = 'not-authorized';
        final session = await joinLive();
        addTearDown(() => session.leave());
        expect(session.connectionState, MeetingConnectionState.connected);
      },
    );

    test('andere conference-error → providerUnavailable', () async {
      channel.conferenceError = 'item-not-found';
      await expectLater(
        start(),
        throwsA(
          isA<MeetingJoinException>().having(
            (e) => e.reason,
            'reason',
            MeetingFailureReason.providerUnavailable,
          ),
        ),
      );
    });

    test('geen initiate binnen de timeout → providerUnavailable', () async {
      channel.sendInitiate = false;
      await expectLater(
        start(),
        throwsA(
          isA<MeetingJoinException>().having(
            (e) => e.reason,
            'reason',
            MeetingFailureReason.providerUnavailable,
          ),
        ),
      );
    });

    test('MUC-weigering → getypeerde reden', () async {
      channel.selfJoinError = 'registration-required';
      await expectLater(start(), throwsA(isA<MeetingJoinException>()));
    });
  });

  group('live call', () {
    test('roster → ParticipantJoined/Updated/Left met SourceInfo-staat', () async {
      final session = await joinLive();
      addTearDown(() => session.leave());
      final events = <MeetingEvent>[];
      final sub = session.events.listen(events.add);

      channel.inject(
        Stanza.parse(
          "<presence from='$_roomJid/alice'>"
          "<x xmlns='$_mucUserNs'><item affiliation='none' role='participant'/></x>"
          "<nick xmlns='$jitsiNickNs'>Alice</nick>"
          '<SourceInfo>{"alice-a0":{"muted":false},"alice-v0":{"muted":true}}</SourceInfo>'
          '</presence>',
        ),
      );
      await pumpEventQueue();
      final joined = events.whereType<ParticipantJoined>().single;
      expect(joined.participant.displayName, 'Alice');
      expect(joined.participant.micMuted, isFalse);
      expect(joined.participant.camOff, isTrue);

      channel.inject(
        Stanza.parse(
          "<presence from='$_roomJid/alice'>"
          "<x xmlns='$_mucUserNs'><item affiliation='none' role='participant'/></x>"
          '<SourceInfo>{"alice-a0":{"muted":true}}</SourceInfo></presence>',
        ),
      );
      await pumpEventQueue();
      final updated = events.whereType<ParticipantUpdated>().last;
      expect(updated.participant.micMuted, isTrue);

      channel.inject(
        Stanza.parse(
          "<presence type='unavailable' from='$_roomJid/alice'>"
          "<x xmlns='$_mucUserNs'><item affiliation='none' role='none'/></x></presence>",
        ),
      );
      await pumpEventQueue();
      expect(
        events.whereType<ParticipantLeft>().map((e) => e.participantId),
        contains('alice'),
      );
      await sub.cancel();
    });

    test('de focus-occupant is nooit een participant', () async {
      final session = await joinLive();
      addTearDown(() => session.leave());
      channel.inject(
        Stanza.parse(
          "<presence from='$_roomJid/focus'>"
          "<x xmlns='$_mucUserNs'><item affiliation='owner' role='moderator'/></x></presence>",
        ),
      );
      await pumpEventQueue();
      expect(session.participants.map((p) => p.id), isNot(contains('focus')));
    });

    test('remote track met <nick>-a0 msid koppelt aan de participant', () async {
      final session = await joinLive();
      addTearDown(() => session.leave());
      channel.inject(
        Stanza.parse(
          "<presence from='$_roomJid/bob'>"
          "<x xmlns='$_mucUserNs'><item affiliation='none' role='participant'/></x></presence>",
        ),
      );
      await pumpEventQueue();
      mediaCore.conn.emitTrack(
        const MeetingRemoteTrack(
          track: MeetingTrack(id: 't1', kind: MeetingTrackKind.audio),
          msid: 'bob-a0',
        ),
      );
      await pumpEventQueue();
      final bob = session.participants.singleWhere((p) => p.id == 'bob');
      expect(bob.audio?.id, 't1');
    });

    test('mute zet de track uit én meldt muted in SourceInfo', () async {
      final session = await joinLive(startMuted: false);
      addTearDown(() => session.leave());
      expect(mediaCore.conn.enabledCalls, contains(('ta', true)));
      await session.setMicrophone(enabled: false);
      await pumpEventQueue();
      expect(mediaCore.conn.enabledCalls, contains(('ta', false)));
      final sourceInfo = _sourceInfoOf(channel.lastPresence!);
      expect(parseSourceInfo(sourceInfo!.innerText)['$_nick-a0'], isTrue);
      expect(
        session.participants.singleWhere((p) => p.isLocal).micMuted,
        isTrue,
      );
    });

    test('camera aan tijdens de call → nieuwe source-add', () async {
      final session = await joinLive(startCameraOff: true);
      addTearDown(() => session.leave());
      await session.setCamera(enabled: true);
      await pumpEventQueue();
      final adds = channel.sent
          .where(
            (s) => s.children.any(
              (e) =>
                  e.name.local == 'jingle' &&
                  e.getAttribute('action') == 'source-add' &&
                  e.toXmlString().contains('-v0'),
            ),
          )
          .toList();
      expect(adds, isNotEmpty);
      expect(
        session.participants.singleWhere((p) => p.isLocal).camOff,
        isFalse,
      );
    });

    test('chat in en uit', () async {
      final session = await joinLive();
      addTearDown(() => session.leave());
      final events = <MeetingEvent>[];
      final sub = session.events.listen(events.add);

      channel.inject(
        Stanza.parse(
          "<message type='groupchat' from='$_roomJid/alice'><body>hallo</body></message>",
        ),
      );
      await pumpEventQueue();
      final chat = events.whereType<ChatReceived>().single;
      expect(chat.participantId, 'alice');
      expect(chat.text, 'hallo');

      await session.sendChat('terug');
      final out = channel.sent.last;
      expect(out.kind, StanzaKind.message);
      expect(out.type, 'groupchat');
      expect(out.to, _roomJid);
      expect(out.child('body')!.innerText, 'terug');
      await sub.cancel();
    });

    test(
      'geen device → eerlijk receive-only, nooit een verzonnen track',
      () async {
        mediaCore.conn.allowVideo = false;
        final session = await joinLive(startCameraOff: false);
        addTearDown(() => session.leave());
        final local = session.participants.singleWhere((p) => p.isLocal);
        expect(local.camOff, isTrue); // geen v0-bron → camOff blijft waar
        // En geen source-add voor video gestuurd.
        expect(
          channel.sent.any(
            (s) => s.children.any(
              (e) =>
                  e.name.local == 'jingle' &&
                  e.getAttribute('action') == 'source-add' &&
                  e.toXmlString().contains('-v0'),
            ),
          ),
          isFalse,
        );
      },
    );
  });

  group('einde', () {
    test(
      'leave: session-terminate + unavailable presence + alles dicht',
      () async {
        final session = await joinLive();
        await session.leave();

        final kinds = channel.sent.map((s) {
          final jingle = s.children
              .where((e) => e.name.local == 'jingle')
              .firstOrNull;
          return jingle?.getAttribute('action');
        }).toList();
        expect(kinds, contains('session-terminate'));
        expect(
          channel.sent.any(
            (s) => s.kind == StanzaKind.presence && s.type == 'unavailable',
          ),
          isTrue,
        );
        expect(mediaCore.conn.closed, isTrue);
        expect(sessionClosed, isTrue);
        expect(session.connectionState, MeetingConnectionState.disconnected);
        // Idempotent: nogmaals leave doet niets en crasht niet.
        await session.leave();
      },
    );

    test('session-terminate van de focus sluit de sessie', () async {
      final session = await joinLive();
      channel.inject(
        Stanza.parse(
          "<iq type='set' from='$_roomJid/focus' id='t1'>"
          "<jingle xmlns='$jingleNs' action='session-terminate' sid='9h90l0o8t59ro'>"
          '<reason><success/></reason></jingle></iq>',
        ),
      );
      await pumpEventQueue(times: 5);
      expect(mediaCore.conn.closed, isTrue);
      expect(sessionClosed, isTrue);
      expect(session.connectionState, MeetingConnectionState.disconnected);
    });

    test('dropped kanaal → failed + terminal error-event', () async {
      final session = await joinLive();
      final events = <MeetingEvent>[];
      final sub = session.events.listen(events.add);
      channel.drop();
      await pumpEventQueue(times: 5);
      expect(session.connectionState, MeetingConnectionState.failed);
      expect(sessionClosed, isTrue);
      await sub.cancel();
    });
  });
}
