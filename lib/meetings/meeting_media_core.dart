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
// signalling fails, no media channel opens.
//
// The seam is deliberately *Jingle-shaped*, not generic-WebRTC-shaped: the Jitsi
// adapter is always the answerer (the JVB offers), so [MeetingMediaConnection]
// exposes applyRemoteOffer/completeAnswer rather than an offerer flow.

import 'package:flutter/foundation.dart';

import 'meeting_participant.dart' show MeetingTrack;
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

/// Wat de media-laag over één remote track meldt. [msid] is de `msid`-waarde
/// uit het SDP — bij Jitsi bevat die de sourcenaam (`<nick>-a0`) die de sessie
/// aan een participant koppelt. Een track zonder herleidbare msid krijgt geen
/// eigenaar en wordt dus nooit verzonnen aan een participant toegeschreven.
class MeetingRemoteTrack {
  const MeetingRemoteTrack({
    required this.track,
    this.msid,
    this.active = true,
  });

  final MeetingTrack track;

  /// De `msid` van de stream zoals de peer die stuurde, of null.
  final String? msid;

  /// `false` = de track eindigde (onRemoveStream/track ended).
  final bool active;
}

/// De liveness van de ICE/DTLS-verbinding naar de peer (de JVB). [live] is het
/// enige moment waarop een sessie "connected" mag claimen — het is het
/// mediapad-bewijs (acceptatie: nooit een schijnbaar verbonden call zonder
/// mediapad).
enum MeetingMediaLiveness { connecting, live, disrupted, dead, closed }

/// One ICE server the *vetted signalling session* handed us (extdisco/TURN).
/// The adapter fills this — never a hardcoded public service (P1).
class MeetingIceServer {
  const MeetingIceServer(this.url, {this.username, this.credential});

  final String url;
  final String? username;
  final String? credential;
}

/// A live peer connection the adapter negotiates over. The Jitsi flow:
/// [addLocalTrack]s first (tracks exist before the answer), [applyRemoteOffer]
/// with the synthesised offer, [completeAnswer] produces our SDP, and the
/// adapter announces the resulting SSRCs itself (source-add). Tracks added
/// after the answer ([addLocalTrack] again) re-negotiate *locally* only —
/// Jitsi signals them via source-add, not a re-offer.
abstract interface class MeetingMediaConnection {
  /// Remote tracks as they arrive and end, in order.
  Stream<MeetingRemoteTrack> get remoteTracks;

  /// ICE/DTLS liveness changes, in order.
  Stream<MeetingMediaLiveness> get liveness;

  /// The current liveness snapshot (for a late subscriber).
  MeetingMediaLiveness get currentLiveness;

  /// Attach a local microphone track. Returns `(trackId, ssrc)` — the SSRC
  /// the adapter announces via `source-add` — or null when the device denies
  /// us (no device, no permission): the adapter joins receive-only then and
  /// never pretends a muted track exists.
  Future<({String trackId, int? ssrc})?> addLocalAudio();

  /// Attach a local camera track (same contract as [addLocalAudio]).
  Future<({String trackId, int? ssrc})?> addLocalVideo();

  /// Enable/disable a previously added local track (mute). The track keeps
  /// flowing; `enabled=false` is what jitsi's `muted` SourceInfo means.
  Future<void> setLocalTrackEnabled(String trackId, {required bool enabled});

  /// The remote offer (the synthesised SDP from `session-initiate`).
  Future<void> applyRemoteOffer(String sdp);

  /// Create + set the local answer, and return its SDP for the adapter to
  /// turn into `session-accept` and `source-add`.
  Future<String> completeAnswer();

  /// Release the peer connection and all tracks. Idempotent.
  Future<void> close();
}

/// The media plane a meeting adapter drives. The one real implementation is
/// `WebrtcMediaCore` (`meeting_media_core_webrtc.dart`); tests use a fake.
abstract interface class MeetingMediaCore {
  /// The media-E2EE status this core can offer on the running platform.
  MeetingE2eeStatus get mediaE2ee;

  /// Confirm the native media stack loads on this device — bring up and tear
  /// down a throwaway peer connection with no ICE servers. Real media needs a
  /// device, so this returns true only where the stack is present, and it
  /// reaches NO network. The module's media preflight uses it to disclose
  /// honestly whether calls can run here.
  Future<bool> selfTest();

  /// Open a peer connection for one session. [iceServers] are the STUN/TURN
  /// the *signalling* handed us (extdisco) — never a hardcoded service; an
  /// empty list is correct for a deployment whose SFU is directly reachable
  /// (the testbed: JVB on loopback, no STUN/TURN).
  Future<MeetingMediaConnection> openConnection({
    List<MeetingIceServer> iceServers = const [],
  });

  /// Release any native resources.
  Future<void> dispose();
}
