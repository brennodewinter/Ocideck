// Tests for JitsiMeetingProvider (#2533): host recognition (suffix-safe),
// and the preflight mapping — config fetch → deployment declaration → guest
// check → XEP-0030 discovery — with the network seams injected. Verifies the
// typed outcomes: providerUnavailable, meetingTypeUnsupported,
// accountRequired, and the honest "no join yet".

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_provider.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_config.dart';
import 'package:ocideck/meetings/providers/jitsi/jitsi_meeting_provider.dart';
import 'package:ocideck/xmpp/xmpp_frame_transport.dart';

const _config = '''
  var config = {
    hosts: { domain: 'meet.jitsi', anonymousdomain: 'guest.meet.jitsi' },
    websocket: 'wss://meet.example/xmpp-websocket'
  };
''';

JitsiMeetingProvider _provider({
  String? configSource = _config,
  JitsiSignallingResult? signalling,
  void Function(Uri)? onFetch,
}) => JitsiMeetingProvider(
  configFetcher: (url, {required allowPrivate, pinnedCertSha256 = ''}) {
    onFetch?.call(url);
    if (configSource == null) {
      throw const JitsiConfigFetchException('HTTP 404');
    }
    return Future.value(configSource);
  },
  signallingProbe: (settings, domain) => Future.value(
    signalling ?? const JitsiSignallingResult.ok('muc.meet.jitsi'),
  ),
  nickFactory: () => 'ocideck_00000001',
);

MeetingLinkMatch _match(String url) =>
    MeetingLinkMatch(providerId: 'jitsi', invitation: Uri.parse(url));

void main() {
  group('match', () {
    test('recognises meet.jit.si rooms', () {
      final p = JitsiMeetingProvider();
      final m = p.match(Uri.parse('https://meet.jit.si/standup'));
      expect(m, isNotNull);
      expect(m!.providerId, 'jitsi');
    });

    test('suffix-safe: dotted subdomains yes, look-alikes no', () {
      final p = JitsiMeetingProvider();
      expect(p.match(Uri.parse('https://beta.meet.jit.si/r')), isNotNull);
      expect(p.match(Uri.parse('https://xmeet.jit.si/r')), isNull);
      expect(p.match(Uri.parse('https://meet.jit.si.evil/r')), isNull);
    });

    test('root is not a room', () {
      expect(
        JitsiMeetingProvider().match(Uri.parse('https://meet.jit.si/')),
        isNull,
      );
    });
  });

  group('preflight', () {
    test(
      'happy path: nativeClient, e2ee off, nick, egress disclosed',
      () async {
        Uri? fetched;
        final pre = await _provider(
          onFetch: (u) => fetched = u,
        ).preflight(_match('https://meet.jit.si/standup'));
        expect(pre.canJoin, isTrue);
        expect(pre.support, MeetingSupport.nativeClient);
        expect(pre.e2ee, MeetingE2eeStatus.off);
        expect(pre.identityLabel, 'ocideck_00000001');
        expect(pre.failureReason, isNull);
        // config.js resolved against the room's parent path.
        expect(fetched.toString(), 'https://meet.jit.si/config.js');
        // Web origin + websocket origin + discovered MUC component.
        expect(pre.egressOrigins, contains('https://meet.jit.si'));
        expect(pre.egressOrigins, contains('wss://meet.example'));
        expect(pre.egressOrigins, contains('xmpp:muc.meet.jitsi'));
      },
    );

    test('subpath deployments resolve config.js next to the room', () async {
      Uri? fetched;
      await _provider(
        onFetch: (u) => fetched = u,
      ).preflight(_match('https://meet.jit.si/jitsi/room'));
      expect(fetched.toString(), 'https://meet.jit.si/jitsi/config.js');
    });

    test('config.js unreachable → providerUnavailable with detail', () async {
      final pre = await _provider(
        configSource: null,
      ).preflight(_match('https://meet.jit.si/r'));
      expect(pre.canJoin, isFalse);
      expect(pre.failureReason, MeetingFailureReason.providerUnavailable);
      expect(pre.diagnosticsDetail, contains('config.js'));
    });

    test('no websocket declared → meetingTypeUnsupported', () async {
      final pre = await _provider(
        configSource: "var config = { bosh: 'https://h/http-bind' };",
      ).preflight(_match('https://meet.jit.si/r'));
      expect(pre.support, MeetingSupport.unsupported);
      expect(pre.failureReason, MeetingFailureReason.meetingTypeUnsupported);
    });

    test('no anonymousdomain → accountRequired without probing', () async {
      var probed = false;
      final p = JitsiMeetingProvider(
        configFetcher: (url, {required allowPrivate, pinnedCertSha256 = ''}) =>
            Future.value(
              "var config = { hosts: { domain: 'meet.jitsi' }, "
              "websocket: 'wss://h/ws' };",
            ),
        signallingProbe: (s, d) {
          probed = true;
          return Future.value(const JitsiSignallingResult.ok('m'));
        },
      );
      final pre = await p.preflight(_match('https://meet.jit.si/r'));
      expect(pre.failureReason, MeetingFailureReason.accountRequired);
      expect(probed, isFalse);
    });

    test('signalling failure maps through typed', () async {
      final pre = await _provider(
        signalling: const JitsiSignallingResult.failed(
          MeetingFailureReason.accountRequired,
        ),
      ).preflight(_match('https://meet.jit.si/r'));
      expect(pre.canJoin, isFalse);
      expect(pre.failureReason, MeetingFailureReason.accountRequired);
    });
  });

  group('join (#2534)', () {
    MeetingJoinRequest req(String url) =>
        MeetingJoinRequest(link: _match(url), displayName: 'x');

    test('config.js onbereikbaar → providerUnavailable', () {
      expect(
        _provider(configSource: null).join(req('https://meet.jit.si/r')),
        throwsA(
          isA<MeetingJoinException>().having(
            (e) => e.reason,
            'reason',
            MeetingFailureReason.providerUnavailable,
          ),
        ),
      );
    });

    test('deployment zonder websocket → meetingTypeUnsupported', () {
      expect(
        _provider(
          configSource: "var config = { bosh: 'https://h/http-bind' };",
        ).join(req('https://meet.jit.si/r')),
        throwsA(
          isA<MeetingJoinException>().having(
            (e) => e.reason,
            'reason',
            MeetingFailureReason.meetingTypeUnsupported,
          ),
        ),
      );
    });

    test('geen anonymousdomain → accountRequired', () {
      expect(
        _provider(
          configSource:
              "var config = { hosts: { domain: 'm' }, websocket: 'wss://h/ws' };",
        ).join(req('https://meet.jit.si/r')),
        throwsA(
          isA<MeetingJoinException>().having(
            (e) => e.reason,
            'reason',
            MeetingFailureReason.accountRequired,
          ),
        ),
      );
    });

    test('transport-weigering → providerUnavailable', () {
      expect(
        JitsiMeetingProvider(
          configFetcher:
              (url, {required allowPrivate, pinnedCertSha256 = ''}) =>
                  Future.value(_config),
          transportOpener: (settings) =>
              throw const XmppConnectException('refused'),
        ).join(req('https://meet.jit.si/r')),
        throwsA(
          isA<MeetingJoinException>().having(
            (e) => e.reason,
            'reason',
            MeetingFailureReason.providerUnavailable,
          ),
        ),
      );
    });
  });
}
