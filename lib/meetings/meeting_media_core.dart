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

import 'call_audio_source.dart';
import 'meeting_participant.dart' show MeetingTrack;
import 'meeting_provider.dart' show MeetingE2eeStatus;

/// Eén lokale verzend-bron zoals de adapter hem aan de focus meldt
/// (#2541): de msid van de track op de sender, álle ssrc's die de sender
/// werkelijk gebruikt (media én rtx) en de FID-paren daartussen. De echte
/// wire (testbed-capture) toont per bron meerdere `<source>`-elementen
/// plus `ssrc-group`s — een enkel kaal ssrc-veld is niet wat de focus
/// consumeert.
class MeetingLocalSource {
  const MeetingLocalSource({
    required this.msid,
    required this.ssrcs,
    this.fidPairs = const [],
  });

  /// `'<stream-id> <track-id>'` — de a=msid waarmee onze RTP zich
  /// identificeert; de remote koppelt die aan de sourcenaam.
  final String msid;

  /// De media- én rtx-ssrc's van de sender, in encoding-volgorde.
  final List<int> ssrcs;

  /// `(media, rtx)`-paren voor `ssrc-group semantics='FID'`.
  final List<(int, int)> fidPairs;
}

/// The known media-E2EE status for a platform, as a pure function — testable
/// without any media stack. `flutter_webrtc`'s frame cryptor crashes on iOS and
/// macOS (ketenkeuring Bevinding 6, flutter-webrtc#2135), so media E2EE is **off**
/// there until that lands; elsewhere it is not yet wired, so **unknown**. OciDeck
/// never claims E2EE it cannot verify (`NATIVE_CALLS.md` §6).
MeetingE2eeStatus mediaE2eeFor(TargetPlatform platform) => switch (platform) {
  TargetPlatform.iOS || TargetPlatform.macOS => MeetingE2eeStatus.off,
  _ => MeetingE2eeStatus.unknown,
};

/// Kan dit platform een schermbron vastleggen (#2537)? Desktop en web kunnen
/// via `getDisplayMedia` (desktop met een eigen bronlijst, web via de kiezer
/// van de browser); iOS en Android vragen een eigen broadcast-extensie-
/// respectievelijk MediaProjection-flow die er bewust niet is — nooit
/// claimen wat niet bewezen is.
bool screenShareFor(TargetPlatform platform, {bool isWeb = kIsWeb}) =>
    isWeb ||
    platform == TargetPlatform.macOS ||
    platform == TargetPlatform.windows ||
    platform == TargetPlatform.linux;

/// Eén deelbare schermbron uit de bronlijst van het systeem — een scherm of
/// een venster, met een miniatuur voor de kiezer. De lijst is leeg op
/// platforms waar de browser of het OS zélf kiest ([screenShareFor] zegt
/// daar nog steeds waar; alleen de eigen kiezer valt weg).
class MeetingScreenSource {
  const MeetingScreenSource({
    required this.id,
    required this.label,
    this.isWindow = false,
    this.thumbnail,
  });

  /// De source-id zoals `getDisplayMedia` hem verwacht.
  final String id;

  /// De naam van het scherm of de titel van het venster.
  final String label;

  /// True voor een venster, false voor een heel scherm.
  final bool isWindow;

  /// Een miniatuur (png/jpeg-bytes) voor in de kiezer, als het OS die geeft.
  final Uint8List? thumbnail;
}

/// Wat de media-laag over één remote track meldt. De track zelf identificeert
/// niet wíé hij is (bij Jitsi is de msid een willekeurige UUID) — de
/// provider-signalering bepaalt welke participant hem toebehoort, en een
/// track zónder die koppeling krijgt nooit een verzonnen eigenaar.
class MeetingRemoteTrack {
  const MeetingRemoteTrack({required this.track, this.active = true});

  final MeetingTrack track;

  /// `false` = de track eindigde (onRemoveStream/track ended).
  final bool active;
}

/// De liveness van de ICE/DTLS-verbinding naar de peer (de JVB). [live] is het
/// enige moment waarop een sessie "connected" mag claimen — het is het
/// mediapad-bewijs (acceptatie: nooit een schijnbaar verbonden call zonder
/// mediapad).
enum MeetingMediaLiveness { connecting, live, disrupted, dead, closed }

/// Een gerenderd videovlak als Flutter-texture — het enige wat de call-UI
/// nodig heeft (`Texture(textureId: …)`), zodat `lib/meetings/` geen
/// flutter_webrtc-type exposeert (#2535). [attachVideo] op de connection
/// levert hem; de houder disposet hem bij track-einde of sluiten.
abstract interface class MeetingVideoSurface {
  /// De platform-texture die `Texture` rendert.
  int get textureId;

  /// Ruimt de renderer op. Idempotent.
  Future<void> dispose();
}

/// Een SCTP-tekstkanaal naar de peer. Bij Jitsi is dit de
/// EndpointMessageTransport: de bridge-messages (ClientHello,
/// ReceiverVideoConstraints, DominantSpeakerMessage) lopen eroverheen als
/// JSON — zonder dit kanaal forwardt de JVB geen video (#2535). De
/// JSON-semantiek hoort bij de adapter; dit is alleen de pijp.
abstract interface class MeetingDataChannel {
  /// Binnenkomende tekstberichten, in volgorde. Binaire frames komen hier
  /// niet uit — de bridge spreekt alleen tekst.
  Stream<String> get messages;

  /// Stuur een tekstbericht naar de peer.
  Future<void> send(String text);

  /// Sluit het kanaal. Idempotent.
  Future<void> close();
}

/// Een uitvoerbestemming voor call-audio (koptelefoon, speakers, …), zoals
/// `Helper.audiooutputs` die meldt. [id] gaat naar [selectAudioOutput];
/// [label] is wat de gebruiker ziet.
class MeetingAudioOutput {
  const MeetingAudioOutput({required this.id, required this.label});

  final String id;
  final String label;
}

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
  /// [attachToSender] is alleen voor het delen (#2537): een camera die
  /// aangaat terwijl het scherm op de video-sender ligt, wordt opgehaald
  /// maar legt het scherm niet stil — die blijft op `-v0`.
  Future<({String trackId, int? ssrc})?> addLocalVideo({
    bool attachToSender = true,
  });

  /// Enable/disable a previously added local track (mute). The track keeps
  /// flowing; `enabled=false` is what jitsi's `muted` SourceInfo means.
  Future<void> setLocalTrackEnabled(String trackId, {required bool enabled});

  /// De huidige verzend-bron van een richting (`'audio'`/`'video'`) zoals
  /// de sender hem NU kent — voor de `source-add` bij de focus. Null zolang
  /// er geen track of nog geen ssrc is: libwebrtc wijst de ssrc pas toe
  /// zodra de track echt gaat zenden, dus meteen na `addLocal*` of
  /// `replaceTrack` is hij vaak nog leeg — daarom is dit een aparte,
  /// op-aankondigmoment lezing en géén veld op het attach-resultaat (#2541).
  /// [singleAttempt]: één lezing zonder te pollen — voor een bron die
  /// verder niets zendt (gemuteerd) is wachten op een ssrc zinloos.
  Future<MeetingLocalSource?> localSource(
    String kind, {
    bool singleAttempt = false,
  });

  /// De track-id van een lokale bron die wegvalt (mic/cam verdwenen,
  /// permissie ingetrokken). De adapter zet daarna SourceInfo én de
  /// participant bij — een weggevallen bron is geen gemuteerde bron meer.
  Stream<String> get localTrackLost;

  /// De deelbare schermbronnen die het systeem meldt (#2537): schermen en
  /// vensters met een miniatuur voor de kiezer. Leeg op platforms waar de
  /// browser zelf kiest (web) of waar opvragen niet kan — [addLocalScreen]
  /// zonder sourceId is dan de route.
  Future<List<MeetingScreenSource>> screenSources();

  /// Leg een schermbron op de vaste video-sender (#2537): het camerabeeld
  /// wordt vervangen, de m-line en de aangekondigde bron `<nick>-v0` blijven
  /// gelijk — zo legt Jitsi delen neer (dezelfde bron krijgt videoType
  /// 'desktop'). [sourceId] komt uit [screenSources]; null alleen waar de
  /// browser zelf kiest. De adapter hoeft geen extra source-add te sturen
  /// als er al een video-bron was, wél als -v0 er nog niet was.
  /// Null bij weigering, annuleren of bronverlies — de call blijft intact.
  Future<({String trackId, int? ssrc})?> addLocalScreen({String? sourceId});

  /// Stop het schermdelen: de sender terug op de bestaande camera-track als
  /// die er is, anders losgekoppeld; de display-capture wordt vrijgegeven.
  /// Idempotent — zonder lopende share een no-op.
  Future<void> stopScreenShare();

  /// Render een video-track (remote óf lokaal, op [MeetingTrack.id]) als
  /// texture. Null bij een onbekende of al geëindigde track — nooit een
  /// nepvlak (#2535). De connection ruimt de onderliggende renderer op bij
  /// [close]; de aanroeper disposet zijn eigen surface expliciet.
  Future<MeetingVideoSurface?> attachVideo(String trackId);

  /// De audio-uitvoerbestemmingen die het apparaat nu kent.
  Future<List<MeetingAudioOutput>> audioOutputs();

  /// Kies waar de call-audio heen gaat. Best-effort per platform — een
  /// onbekende of verdwenen id faalt stil (de OS-default geldt dan).
  Future<void> selectAudioOutput(String deviceId);

  /// Of deze binding gedecodeerde audiobronnen per deelnemer kan leveren
  /// (#2527). De huidige flutter_webrtc-binding kan dat niet.
  CallAudioCaptureFact get callAudioCapture;

  /// Start de tap. Een track-id is geen argument: zonder whole-call-feit
  /// komt er een lege stroom uit en wordt er niets opgenomen.
  Stream<CallAudioChunk> startCallAudioCapture();

  /// Stop de tap. Idempotent.
  Future<void> stopCallAudioCapture();

  /// Open een betrouwbaar SCTP-datachannel met [label] en geef hem zodra
  /// hij echt open staat (pas na DTLS/SCTP — daarom async). De offer moet
  /// een `m=application`-sectie hebben; de adapter kiest [label] (de JVB
  /// behandelt elk inkomend kanaal als endpoint-message transport).
  /// Faalt begrensd als het kanaal nooit opent.
  Future<MeetingDataChannel> openDataChannel(String label);

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
