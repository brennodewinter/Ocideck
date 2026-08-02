import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/meetings/meeting_media_core.dart';
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
}
