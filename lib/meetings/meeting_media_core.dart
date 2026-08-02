// The media plane behind the meeting adapters (F3, `NATIVE_CALLS.md` §3;
// ketenkeuring `assurance/ketenkeuring-flutter-webrtc.md`). WebRTC media is
// libwebrtc — not pure Dart — so this is the one place `flutter_webrtc` is
// touched, behind a seam. The adapter drives a [MeetingMediaCore]; its logic is
// unit-tested against a fake, and the single real binding
// (`meeting_media_core_webrtc.dart`) stays isolated. That real binding runs only
// on a device (camera/mic, ICE, a real peer), so it cannot execute in a headless
// test VM — it is verified live, not by a unit test.
//
// Network posture (ketenkeuring Bevinding 3, the crux): WebRTC media (ICE/STUN/
// TURN over UDP, SRTP) does NOT pass through NetGuard — it is the one traffic
// class outside the central choke. What keeps it bounded, and is enforced where
// the adapter configures ICE (F3.4b): media follows the *validated* signalling
// origin and reaches only the TURN/SFU origins handed to it from that signalling;
// it opens media to no host that did not come from the vetted session, and if
// signalling fails, no media channel opens. This file opens nothing itself — it
// only reports facts and confirms the stack loads.

import 'package:flutter/foundation.dart';

import 'meeting_provider.dart' show MeetingE2eeStatus;

/// The known media-E2EE status for a platform, as a pure function — testable
/// without any media stack. `flutter_webrtc`'s frame cryptor crashes on iOS and
/// macOS (ketenkeuring Bevinding 6, flutter-webrtc#2135), so media E2EE is **off**
/// there until that lands; elsewhere it is not yet wired, so **unknown**. OciDeck
/// never claims E2EE it cannot verify (`NATIVE_CALLS.md` §6).
MeetingE2eeStatus mediaE2eeFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => MeetingE2eeStatus.off,
  _ => MeetingE2eeStatus.unknown,
};

/// The media plane a meeting adapter drives. F3.4a defines the seam and the facts;
/// the connection/track operations the adapter needs arrive with the Jitsi adapter
/// (F3.4b). The one real implementation is `WebrtcMediaCore`
/// (`meeting_media_core_webrtc.dart`); tests use a fake.
abstract interface class MeetingMediaCore {
  /// The media-E2EE status this core can offer on the running platform.
  MeetingE2eeStatus get mediaE2ee;

  /// Confirm the native media stack loads on this device — bring up and tear down
  /// a throwaway peer connection with no ICE servers. Real media needs a device,
  /// so this returns true only where the stack is present, and it reaches NO
  /// network. The module's media preflight uses it to disclose honestly whether
  /// calls can run here.
  Future<bool> selfTest();

  /// Release any native resources.
  Future<void> dispose();
}
