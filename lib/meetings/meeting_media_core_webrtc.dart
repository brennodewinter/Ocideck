// The one real `flutter_webrtc` binding (F3, ketenkeuring
// `assurance/ketenkeuring-flutter-webrtc.md`). It touches libwebrtc through
// platform channels, so it cannot run in a headless test VM — it is verified on a
// device, live, not by a unit test. For that reason it is the sole media file in
// `tool/coverage_summary.dart`'s `uncoveredBaseline` (an untestable native-media
// binding, the same reason a platform `_io` half sits there). Every testable
// decision — the E2EE fact, the egress policy — lives in `meeting_media_core.dart`
// and is covered there; this file holds only the direct libwebrtc calls.

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../utils/log.dart';
import 'meeting_media_core.dart';
import 'meeting_provider.dart' show MeetingE2eeStatus;

/// The production [MeetingMediaCore]. Kept deliberately thin: no branching logic,
/// only the libwebrtc calls the seam promises.
class WebrtcMediaCore implements MeetingMediaCore {
  WebrtcMediaCore({TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform;

  final TargetPlatform _platform;

  @override
  MeetingE2eeStatus get mediaE2ee => mediaE2eeFor(_platform);

  @override
  Future<bool> selfTest() async {
    // Bring up a throwaway peer connection with no ICE servers to confirm
    // libwebrtc loaded on this device, then tear it down. Nothing is captured and
    // nothing is sent — this reaches no network.
    try {
      final pc = await createPeerConnection(const {'iceServers': <Object>[]});
      await pc.close();
      return true;
    } catch (e) {
      logWarning('WebrtcMediaCore.selfTest: media stack unavailable', e);
      return false;
    }
  }

  @override
  Future<void> dispose() async {}
}
