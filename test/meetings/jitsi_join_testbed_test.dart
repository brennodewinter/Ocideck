// Integration test for the Jitsi join (#2534) against the pinned local
// testbed (`testbed/jitsi-meet/`, #2540). Everything that is OUR protocol
// code runs for real: config.js via NetGuard-pinned socket, anonymous XMPP,
// XEP-0030, conference IQ, MUC join, the Jicofo `session-initiate`, our
// `session-accept`, source-add and SourceInfo presence — over real Prosody,
// Jicofo and JVB, with two OciDeck clients in one room.
//
// What is NOT real: the RTP path. libwebrtc cannot run on a headless test
// VM, so the media seam (`MeetingMediaCore`) is a fake that produces a
// syntactically valid answer and reports liveness — exactly the boundary
// the seam was designed for (meeting_media_core.dart). The browser probe
// (`testbed/jitsi-meet/probe.js`) is the proof that real RTP flows through
// the same deployment; this test proves our signalling chain is correct
// enough for Jicofo to accept.
//
// Gated behind OCIDECK_JITSI_INTEGRATION=1; the stack must be running
// (`testbed/jitsi-meet/run.sh up`). Run:
//   OCIDECK_JITSI_INTEGRATION=1 make test-jitsi-integration

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_event.dart';
import 'package:ocideck/meetings/meeting_media_core.dart';
import 'package:ocideck/meetings/meeting_participant.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/meetings/meeting_provider_profile.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_provider.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_signaling.dart';
import 'package:ocideck/models/xmpp_settings.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport_platform.dart';
import 'package:ocideck/xmpp/xmpp_muc.dart';
import 'package:ocideck/xmpp/xmpp_session.dart';
import 'package:ocideck/xmpp/xmpp_stanza.dart';

// Letterlijk loopback — NetGuard honoureert ws/http op loopback alleen voor
// letterlijke adressen ('localhost' is een naam en gaat langs DNS).
const _origin = 'http://127.0.0.1:8000';

bool get _enabled => Platform.environment['OCIDECK_JITSI_INTEGRATION'] == '1';

/// Het antwoord dat de fake media-laag "onderhandelt" — mids `audio`/`video`/
/// `data`, zoals de testbed-Jicofo ze aanbiedt (zie
/// `test/fixtures/jitsi/session-initiate.xml`). Codec-ids zijn de door Jicofo
// aangeboden opus/AV1-sets.
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

/// De fake media-laag: de Jingle-seam in, een geldig antwoord + directe
/// liveness eruit. `offerSdp` bewaart wat de sessie aanbood, zodat de test
/// kan bewijzen dat de echte Jicofo-offer onze vertaling doorliep.
class _FakeMediaCore implements MeetingMediaCore {
  final conn = _FakeMediaConnection();

  @override
  MeetingE2eeStatus get mediaE2ee => MeetingE2eeStatus.off;

  @override
  Future<bool> selfTest() async => true;

  @override
  Future<MeetingMediaConnection> openConnection({
    List<MeetingIceServer> iceServers = const [],
  }) async => conn;

  @override
  Future<void> dispose() async {}
}

class _FakeMediaConnection implements MeetingMediaConnection {
  final _liveness = StreamController<MeetingMediaLiveness>.broadcast();
  var _ssrcSeq = 42420000;
  String? offerSdp;

  @override
  Stream<MeetingRemoteTrack> get remoteTracks => const Stream.empty();

  @override
  Stream<MeetingMediaLiveness> get liveness => _liveness.stream;

  @override
  MeetingMediaLiveness currentLiveness = MeetingMediaLiveness.connecting;

  @override
  Future<({String trackId, int? ssrc})?> addLocalAudio() async =>
      (trackId: 'ta', ssrc: _ssrcSeq++);

  @override
  Future<({String trackId, int? ssrc})?> addLocalVideo() async =>
      (trackId: 'tv', ssrc: _ssrcSeq++);

  @override
  Future<void> setLocalTrackEnabled(
    String trackId, {
    required bool enabled,
  }) async {}

  @override
  Future<void> applyRemoteOffer(String sdp) async => offerSdp = sdp;

  @override
  Future<String> completeAnswer() async {
    currentLiveness = MeetingMediaLiveness.live;
    unawaited(
      Future.microtask(() {
        if (!_liveness.isClosed) _liveness.add(MeetingMediaLiveness.live);
      }),
    );
    return _answerSdp;
  }

  @override
  Future<void> close() async {
    currentLiveness = MeetingMediaLiveness.closed;
    if (!_liveness.isClosed) unawaited(_liveness.close());
  }
}

MeetingLinkMatch _match(String room) => MeetingLinkMatch(
  providerId: 'jitsi',
  invitation: Uri.parse('$_origin/$room'),
  viaProfile: MeetingProviderProfile(
    id: 'testbed',
    providerId: 'jitsi',
    origin: Uri.parse(_origin),
    trustedInternal: true,
  ),
);

/// Poll een live-state tot die klopt — presence/roster-propagatie over echte
/// Prosody is asynchroon; dit is eerlijker dan een vaste sleep.
Future<void> _until(
  bool Function() test, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (test()) return;
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  fail('voorwaarde niet gehaald binnen $timeout');
}

/// `whereType` bestaat alleen op Iterable; voor een event-stream is
/// `where`+`cast` de idiomatische filter.
Stream<T> _ofType<T>(Stream<MeetingEvent> events) =>
    events.where((e) => e is T).cast<T>();

MeetingParticipant? _byName(MeetingSession s, String displayName) {
  for (final p in s.participants) {
    if (p.displayName == displayName) return p;
  }
  return null;
}

/// Het host-wachtwoord uit `testbed/jitsi-meet/.env` (door `run.sh users`
/// gegenereerd, niet gecommit). Ontbreekt het, dan staat de stack er sowieso
/// niet — de test faalt dan met de aanmaakinstructie.
String get _hostPassword {
  final file = File('testbed/jitsi-meet/.env');
  if (!file.existsSync()) {
    fail('testbed/.env ontbreekt — draai ./run.sh init && ./run.sh users');
  }
  for (final line in file.readAsLinesSync()) {
    if (line.startsWith('TEST_HOST_PASSWORD=')) {
      return line.substring('TEST_HOST_PASSWORD='.length).trim();
    }
  }
  fail('TEST_HOST_PASSWORD ontbreekt in testbed/.env');
}

/// De room-creator. Op deze testbed staat `restrict_room_creation` aan, dus
/// de kamer ontstaat alleen via een conference-IQ van een geauthenticeerd
/// account — precies wat de browser-host uit probe.js doet. OciDeck joint
/// zelf anoniem (zoals een echte gast); deze helper speelt de rol die een
/// jitsi-meet-moderator in de echte wereld heeft.
Future<({XmppSession session, XmppMuc muc})> _hostInRoom(String room) async {
  const settings = XmppSettings(
    serverUrl: 'ws://127.0.0.1:8000/xmpp-websocket',
    jid: 'host@meet.jitsi',
    trustedInternal: true,
  );
  final session = XmppSession(
    transport: await openXmppFrameTransport(settings),
    settings: settings,
    password: _hostPassword,
  );
  final conn = await session.connect();
  if (!conn.ok) fail('host-connect mislukt: ${conn.detail}');

  // De conference-IQ alloceert de kamer bij jicofo — dezelfde stanza die de
  // sessie straks zelf stuurt (dan als gast, met not-authorized als antwoord).
  const iqId = 'conf-host-1';
  final replyFuture = session.stanzas
      .where((s) => s.kind == StanzaKind.iq && s.id == iqId)
      .first
      .timeout(const Duration(seconds: 20));
  session.sendStanza(
    Stanza(
      kind: StanzaKind.iq,
      to: 'focus.meet.jitsi',
      id: iqId,
      type: 'set',
      children: [
        buildConferenceRequest('$room@muc.meet.jitsi', 'ocideck_test_host'),
      ],
    ),
  );
  final reply = await replyFuture;
  if (reply.type == 'error') {
    fail('host conference-IQ geweigerd: ${reply.toXmlString()}');
  }

  // De host blijft als occupant in de kamer — jicofo ruimt een lege
  // conferentie op. Zonder hem is er geen session-initiate voor gasten.
  // Jicofo maakt de MUC-room pas ASYNCHROON aan na `ready='true'` (zijn
  // eigen "Joining …" in de log); joinen we te vroeg, dan bestaat de room
  // nog niet en weigert `restrict_room_creation` met notAllowed. Begrensde
  // retry — geen aannames over jicofo's interne volgorde.
  final muc = XmppMuc(
    channel: session,
    roomJid: '$room@muc.meet.jitsi',
    nick: 'de_host',
    timeout: const Duration(seconds: 20),
  );
  MucJoinResult? joined;
  for (var attempt = 0; attempt < 30; attempt++) {
    joined = await muc.join();
    if (joined.ok || joined.failure != MucJoinFailure.notAllowed) break;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  if (joined == null || !joined.ok) {
    fail('host-muc mislukt: ${joined?.failure}');
  }
  return (session: session, muc: muc);
}

void main() {
  if (!_enabled) {
    test(
      'Jitsi join integration (skipped — set OCIDECK_JITSI_INTEGRATION=1)',
      () {},
      tags: ['integration'],
    );
    return;
  }

  test(
    'two OciDeck clients share one room over real Jicofo signalling',
    () async {
      final room = 'ocideck_join_it_${DateTime.now().millisecondsSinceEpoch}';
      // Eerst de kamer aanmaken: restrict_room_creation staat aan, dus alleen
      // een geauthenticeerd account kan dit — zoals op elke echte
      // internal-auth-deployment.
      final host = await _hostInRoom(room);
      addTearDown(() async {
        await host.muc.leave();
        await host.session.close();
      });

      final mediaA = _FakeMediaCore();
      final mediaB = _FakeMediaCore();
      final sessionA = await JitsiMeetingProvider(
        mediaCoreFactory: () => mediaA,
      ).join(MeetingJoinRequest(link: _match(room), displayName: 'ocideck-a'));
      final errorsA = <MeetingErrorEvent>[];
      _ofType<MeetingErrorEvent>(sessionA.events).listen(errorsA.add);

      try {
        // `start()` keert pas na mediapad-bewijs: connected IS het bewijs
        // dat conference-IQ → MUC → initiate → accept → liveness liep.
        expect(sessionA.connectionState, MeetingConnectionState.connected);
        // De echte Jicofo-offer bereikte de media-seam (Jingle→SDP).
        expect(mediaA.conn.offerSdp, contains('a=mid:audio'));
        expect(mediaA.conn.offerSdp, contains('a=mid:video'));
        final localA = _byName(sessionA, 'ocideck-a');
        expect(localA, isNotNull);
        expect(localA!.isLocal, isTrue);
        // De focus is geen participant.
        expect(sessionA.participants.any((p) => p.id == 'focus'), isFalse);

        // Tweede client in dezelfde kamer.
        final sessionB =
            await JitsiMeetingProvider(mediaCoreFactory: () => mediaB).join(
              MeetingJoinRequest(link: _match(room), displayName: 'ocideck-b'),
            );
        try {
          expect(sessionB.connectionState, MeetingConnectionState.connected);

          // Roster-propagatie: beide zien elkaar, geen van beiden ziet focus.
          await _until(
            () =>
                _byName(sessionA, 'ocideck-b') != null &&
                _byName(sessionB, 'ocideck-a') != null,
          );
          expect(sessionB.participants.any((p) => p.id == 'focus'), isFalse);

          // Chat over de echte MUC-groupchat.
          final chat = _ofType<ChatReceived>(sessionA.events)
              .firstWhere((e) => e.text == 'hoi van b')
              .timeout(const Duration(seconds: 15));
          await sessionB.sendChat('hoi van b');
          final received = await chat;
          expect(received.participantId, _byName(sessionB, 'ocideck-b')!.id);

          // Mute-propagatie: A meldt mic-dicht, B ziet het via SourceInfo.
          await sessionA.setMicrophone(enabled: false);
          await _until(() => _byName(sessionB, 'ocideck-a')?.micMuted == true);

          // Leave: B ziet A vertrekken; A is netjes weg.
          await sessionA.leave();
          await _until(() => _byName(sessionB, 'ocideck-a') == null);
          expect(sessionA.connectionState, MeetingConnectionState.disconnected);
          expect(
            errorsA.where((e) => e.terminal),
            isEmpty,
            reason: 'geen terminale fout tijdens een schone call',
          );
        } finally {
          await sessionB.leave();
        }
      } finally {
        await sessionA.leave();
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    tags: ['integration'],
  );
}
