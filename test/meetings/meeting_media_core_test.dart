import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_media_core.dart';
import 'package:ocideck/meetings/meeting_media_core_webrtc.dart';
import 'package:ocideck/meetings/meeting_provider.dart';

void main() {
  test(
    'media E2EE is off on iOS and macOS (frame-cryptor crash, Bevinding 6)',
    () {
      // flutter_webrtc's frame cryptor crashes on Apple platforms
      // (flutter-webrtc#2135); OciDeck reports E2EE off there rather than claim it.
      expect(mediaE2eeFor(TargetPlatform.iOS), MeetingE2eeStatus.off);
      expect(mediaE2eeFor(TargetPlatform.macOS), MeetingE2eeStatus.off);
    },
  );

  test('media E2EE is unknown elsewhere until it is wired', () {
    // Never claim E2EE OciDeck cannot verify: unknown, not on.
    expect(mediaE2eeFor(TargetPlatform.android), MeetingE2eeStatus.unknown);
    expect(mediaE2eeFor(TargetPlatform.linux), MeetingE2eeStatus.unknown);
    expect(mediaE2eeFor(TargetPlatform.windows), MeetingE2eeStatus.unknown);
    expect(mediaE2eeFor(TargetPlatform.fuchsia), MeetingE2eeStatus.unknown);
  });

  test('schermdelen is een platformfeit: desktop en web, nooit mobiel', () {
    // getDisplayMedia + een eigen bronlijst bestaan op desktop; de browser
    // heeft zijn eigen kiezer; mobiel vraagt een capture-flow die er bewust
    // niet is (#2537 — nooit claimen wat niet bewezen is).
    expect(screenShareFor(TargetPlatform.macOS), isTrue);
    expect(screenShareFor(TargetPlatform.windows), isTrue);
    expect(screenShareFor(TargetPlatform.linux), isTrue);
    expect(screenShareFor(TargetPlatform.android, isWeb: true), isTrue);
    expect(screenShareFor(TargetPlatform.iOS), isFalse);
    expect(screenShareFor(TargetPlatform.android), isFalse);
    expect(screenShareFor(TargetPlatform.fuchsia), isFalse);
  });

  group('meetingLocalSourceFromSdp', () {
    // Vorm na de echte libwebrtc-answer: per m-sectie a=ssrc-regels (met
    // per-ssrc attributen), a=ssrc-group en a=msid (#2541).
    const sdp =
        'v=0\r\n'
        'm=audio 9 UDP/TLS/RTP/SAVPF 111\r\n'
        'a=msid:streamA trackA\r\n'
        'a=ssrc:4242 cname:x\r\n'
        'a=ssrc:4242 msid:streamA trackA\r\n'
        'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
        'a=msid:streamV trackV\r\n'
        'a=ssrc:101 cname:x\r\n'
        'a=ssrc:202 cname:x\r\n'
        'a=ssrc-group:FID 101 202\r\n'
        'm=application 9 UDP/DTLS/SCTP webrtc-datachannel\r\n';

    test('leest ssrc, FID-paar en msid per m-sectie', () {
      final audio = meetingLocalSourceFromSdp(sdp, 'audio')!;
      expect(audio.ssrcs, [4242]);
      expect(audio.fidPairs, isEmpty);
      expect(audio.msid, 'streamA trackA');

      final video = meetingLocalSourceFromSdp(sdp, 'video')!;
      expect(video.ssrcs, containsAllInOrder([101, 202]));
      expect(video.fidPairs, [(101, 202)]);
      expect(video.msid, 'streamV trackV');
    });

    test('geen sectie of geen verzend-ssrc → null', () {
      expect(meetingLocalSourceFromSdp(sdp, 'screen'), isNull);
      expect(meetingLocalSourceFromSdp(null, 'audio'), isNull);
      expect(
        meetingLocalSourceFromSdp(
          'm=video 9 UDP/TLS/RTP/SAVPF 96\r\n'
              'a=recvonly\r\n',
          'video',
        ),
        isNull,
      );
    });
  });

  test('MeetingScreenSource draagt id, label, soort en miniatuur', () {
    const src = MeetingScreenSource(
      id: 'window:7',
      label: 'Editor',
      isWindow: true,
      thumbnail: null,
    );
    expect(src.id, 'window:7');
    expect(src.label, 'Editor');
    expect(src.isWindow, isTrue);
    expect(src.thumbnail, isNull);
  });
}
