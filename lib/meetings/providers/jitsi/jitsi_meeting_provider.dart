// The Jitsi adapter (#2533 recognition/preflight, #2534 join, #2535 media):
// recognition, deployment preflight, and the real join that returns a live
// [JitsiMeetingSession].
//
// What this provider does today, mapped onto the contract:
//
//   * [match] — PURE local recognition of `meet.jit.si` (+ subdomains of the
//     public deployment, suffix-safe) and of origins the user approved via a
//     [MeetingProviderProfile] (the resolver applies the profile; match() only
//     sees built-in hosts — see resolver for the profile half). No probing, no
//     shape-based decisions: any non-root path on a trusted host is a room,
//     because on a Jitsi deployment it literally is.
//
//   * [preflight] — a bounded, consented probe: fetch `config.js` through a
//     NetGuard-pinned socket, read the deployment's own declarations
//     (websocket ingress, XMPP domain, anonymous domain), open an anonymous
//     XMPP session to confirm guest access works, and DISCOVER the MUC
//     component via XEP-0030 — never assumed `conference.<domain>` (the
//     testbed calls it `muc.meet.jitsi`; hardcoding the convention is the bug
//     this layer exists to prevent).
//
//   * [join] — the real join (#2534): config.js again (never a cached
//     preflight), anonymous XMPP, MUC discovery, then [JitsiMeetingSession]
//     running conference-IQ → MUC → Jingle → ICE. Every failed step throws a
//     typed [MeetingJoinException].
//
// Trust boundaries (unchangeable here, per NATIVE_CALLS.md §7):
//   * every egress runs through NetGuard + socket pinning; a config.js that
//     points its `websocket` at an internal address hits the same wall —
//     `trustedInternal` comes only from the user-approved profile, never from
//     the deployment itself;
//   * media-E2EE is reported `off`: this adapter will speak JVB-SRTP without
//     Insertable-Streams E2EE — `unknown` would flatter it, `on` would lie;
//   * a different websocket host than the web origin is legitimate (split
//     deployments) — allowed, but DISCLOSED in [MeetingPreflight.egressOrigins]
//     rather than hidden.

import '../../../models/xmpp_settings.dart';
import '../../../xmpp/xmpp_disco.dart';
import '../../../xmpp/xmpp_frame_transport.dart';
import '../../../xmpp/xmpp_frame_transport_platform.dart';
import '../../../xmpp/xmpp_session.dart';
import '../../meeting_media_core.dart';
import '../../meeting_media_core_webrtc.dart';
import '../../meeting_nick.dart';
import '../../meeting_participant.dart';
import '../../meeting_provider.dart';
import 'jitsi_config.dart';
import 'jitsi_config_platform.dart';
import 'jitsi_meeting_session.dart';
import 'jitsi_signaling.dart' show jitsiCallFeatures;

/// Haalt de config.js-brontekst op — injecteerbaar zodat tests geen netwerk
/// hoeven. De live implementatie is [fetchJitsiConfig].
typedef JitsiConfigFetcher =
    Future<String> Function(
      Uri configUrl, {
      required bool allowPrivate,
      String pinnedCertSha256,
    });

/// De signalling-proef: anonieme sessie openen en het MUC-component
/// ontdekken. Injecteerbaar voor tests.
typedef JitsiSignallingProbe =
    Future<JitsiSignallingResult> Function(
      XmppSettings settings,
      String xmppDomain,
    );

/// De WebSocket-transport-opener voor join — injecteerbaar zodat tests de
/// gepinde-socket-code niet hoeven te draaien.
typedef JitsiTransportOpener =
    Future<XmppFrameTransport> Function(XmppSettings settings);

/// Uitkomst van de signalling-proef: het ontdekte MUC-component, of de
/// getypeerde reden waarom niet — direct in contracttermen, zodat de provider
/// niets meer hoeft te vertalen.
class JitsiSignallingResult {
  const JitsiSignallingResult.ok(this.mucComponent) : failure = null;
  const JitsiSignallingResult.failed(this.failure) : mucComponent = null;

  /// Het via XEP-0030 ontdekte MUC-component (bijv. `muc.meet.jitsi`).
  final String? mucComponent;
  final MeetingFailureReason? failure;
  bool get ok => failure == null;
}

/// The Jitsi provider (`jitsi`). Construct once with the registered profiles
/// available at resolve-time — the resolver hands each match its profile, so
/// the provider itself stays stateless.
class JitsiMeetingProvider implements MeetingProvider {
  JitsiMeetingProvider({
    JitsiConfigFetcher? configFetcher,
    JitsiSignallingProbe? signallingProbe,
    MeetingMediaCore Function()? mediaCoreFactory,
    JitsiTransportOpener? transportOpener,
    String Function()? nickFactory,
  }) : _configFetcher = configFetcher ?? fetchJitsiConfig,
       _signallingProbe = signallingProbe ?? _liveSignallingProbe,
       _mediaCoreFactory = mediaCoreFactory ?? WebrtcMediaCore.new,
       _transportOpener = transportOpener ?? openXmppFrameTransport,
       _nickFactory = nickFactory ?? uniqueMeetingNick;

  final JitsiConfigFetcher _configFetcher;
  final JitsiSignallingProbe _signallingProbe;
  final MeetingMediaCore Function() _mediaCoreFactory;
  final JitsiTransportOpener _transportOpener;
  final String Function() _nickFactory;

  @override
  String get id => 'jitsi';

  /// The built-in public deployment. Everything else arrives via
  /// [MeetingProviderProfile]s — an origin the user (or their admin)
  /// explicitly approved.
  @override
  Set<String> get trustedHosts => const {'meet.jit.si'};

  @override
  MeetingLinkMatch? match(Uri invitation) {
    final host = invitation.host.toLowerCase();
    // Suffix-safe: `meet.jit.si` exact, of een subdomein ervan
    // (`beta.meet.jit.si` is dezelfde operator). `notmeet.jit.si` en
    // `meet.jit.si.evil.example` vallen buiten.
    final trusted = trustedHosts.any((t) => host == t || host.endsWith('.$t'));
    if (!trusted) return null;
    // Op een Jitsi-deployment ís elk non-root pad een kamer — herkenning is
    // hier niet "raadt een vorm", het is de deployment zelf.
    if (invitation.path.isEmpty || invitation.path == '/') return null;
    return MeetingLinkMatch(providerId: id, invitation: invitation);
  }

  @override
  Future<MeetingPreflight> preflight(MeetingLinkMatch link) async {
    final invitation = link.invitation;
    final profile = link.viaProfile;

    // Stap 1: de deploymentvertaling ophalen. `resolve('config.js')` vervangt
    // het kamernsegment — `https://host/meet/foo` → `https://host/meet/
    // config.js`, wat subpath-deployments vanzelf meeneemt.
    final configUrl = invitation.resolve('config.js');
    final String source;
    try {
      source = await _configFetcher(
        configUrl,
        allowPrivate: profile?.trustedInternal ?? false,
        pinnedCertSha256: profile?.pinnedCertSha256 ?? '',
      );
    } on JitsiConfigFetchException catch (e) {
      return _unavailable(e.toString());
    }

    // Stap 2: wat de deployment zélf declareert. Geen websocket → geen
    // signalling die wij spreken (BOSH wordt bewust niet geïmplementeerd);
    // geen XMPP-domein → onvolledige deployment. Het diagnosedetail is de
    // host die de deployment wél verklaarde — grof, zonder pad (contract:
    // diagnosticsDetail draagt geen volledige URL's).
    final config = parseJitsiConfig(source);
    final websocket = config.websocket;
    final domain = config.domain;
    if (websocket == null || websocket.isEmpty) {
      return _unsupported(Uri.tryParse(config.bosh ?? '')?.host);
    }
    if (domain == null || domain.isEmpty) {
      return _unsupported(Uri.tryParse(websocket)?.host);
    }

    // Stap 3: gasttoegang. Geen anonymousdomain = de deployment kent geen
    // anonieme kamers; een proef-connect zou dan alleen een auth-fout
    // opleveren — meld direct en eerlijk `accountRequired`.
    final anonymousDomain = config.anonymousDomain;
    if (anonymousDomain == null || anonymousDomain.isEmpty) {
      return MeetingPreflight(
        support: MeetingSupport.nativeClient,
        capabilities: _capabilities,
        e2ee: MeetingE2eeStatus.off,
        identityLabel: _nickFactory(),
        egressOrigins: _egress(invitation, websocket, config.muc),
        failureReason: MeetingFailureReason.accountRequired,
      );
    }

    // Stap 4: bewijs het — anonieme sessie openen en de MUC-component
    // ontdekken. Alles fail-closed: de proef houdt niets open.
    final settings = XmppSettings(
      serverUrl: websocket,
      domainOverride: anonymousDomain,
      trustedInternal: profile?.trustedInternal ?? false,
      pinnedCertSha256: profile?.pinnedCertSha256 ?? '',
    );
    final signalling = await _signallingProbe(settings, domain);
    if (!signalling.ok) {
      return MeetingPreflight(
        support: MeetingSupport.nativeClient,
        capabilities: _capabilities,
        e2ee: MeetingE2eeStatus.off,
        identityLabel: _nickFactory(),
        egressOrigins: _egress(invitation, websocket, config.muc),
        failureReason: signalling.failure,
      );
    }

    return MeetingPreflight(
      support: MeetingSupport.nativeClient,
      capabilities: _capabilities,
      e2ee: MeetingE2eeStatus.off,
      identityLabel: _nickFactory(),
      egressOrigins: _egress(invitation, websocket, signalling.mucComponent),
    );
  }

  /// Echte deelname (#2534): dezelfde deploymentvertaling als [preflight] —
  /// join vertrouwt nooit op een eerdere preflight-uitkomst (die kan verlopen
  /// of nooit gedraaid zijn) — dan anonieme sessie, MUC-discovery, en de
  /// [JitsiMeetingSession] die conference-IQ → MUC → Jingle → ICE orkestreert.
  /// Elke mislukte stap werpt [MeetingJoinException] met een getypeerde reden.
  @override
  Future<MeetingSession> join(MeetingJoinRequest request) async {
    final invitation = request.link.invitation;
    final profile = request.link.viaProfile;

    final String source;
    try {
      source = await _configFetcher(
        invitation.resolve('config.js'),
        allowPrivate: profile?.trustedInternal ?? false,
        pinnedCertSha256: profile?.pinnedCertSha256 ?? '',
      );
    } on JitsiConfigFetchException catch (e) {
      throw MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        e.toString(),
      );
    } on UnsupportedError catch (e) {
      throw MeetingJoinException(
        MeetingFailureReason.meetingTypeUnsupported,
        e.message,
      );
    }

    final config = parseJitsiConfig(source);
    final websocket = config.websocket;
    final domain = config.domain;
    if (websocket == null ||
        websocket.isEmpty ||
        domain == null ||
        domain.isEmpty) {
      throw const MeetingJoinException(
        MeetingFailureReason.meetingTypeUnsupported,
        'deployment zonder websocket/xmpp-domain',
      );
    }
    final anonymousDomain = config.anonymousDomain;
    if (anonymousDomain == null || anonymousDomain.isEmpty) {
      throw const MeetingJoinException(
        MeetingFailureReason.accountRequired,
        'geen gasttoegang',
      );
    }
    // De kamer is het pad van de link — match() vereist al een non-root pad.
    final room = invitation.path.replaceAll('/', '');
    if (room.isEmpty) {
      throw const MeetingJoinException(
        MeetingFailureReason.meetingTypeUnsupported,
        'link zonder kamer',
      );
    }

    final settings = XmppSettings(
      serverUrl: websocket,
      domainOverride: anonymousDomain,
      trustedInternal: profile?.trustedInternal ?? false,
      pinnedCertSha256: profile?.pinnedCertSha256 ?? '',
    );
    final XmppFrameTransport transport;
    try {
      transport = await _transportOpener(settings);
    } on XmppConnectException catch (e) {
      throw MeetingJoinException(
        MeetingFailureReason.providerUnavailable,
        e.toString(),
      );
    }
    // `live` wordt pas gevuld als de sessie staat; onRejoin vuurt alleen op
    // een drop van een live sessie, dus de chicken-egg lost vanzelf op.
    JitsiMeetingSession? live;
    final session = XmppSession(
      transport: transport,
      settings: settings,
      reconnectTransportFactory: () => _transportOpener(settings),
      onRejoin: (_) => live?.rejoin() ?? Future.value(false),
      // Jicofo ontdekt onze endpoint-features via disco#info — zonder dat
      // antwoord komt de session-initiate zonder data-content (#2535).
      discoFeatures: jitsiCallFeatures,
    );
    try {
      final connected = await session.connect();
      if (!connected.ok) {
        throw MeetingJoinException(switch (connected.failure!) {
          XmppSessionFailure.noUsableMechanism ||
          XmppSessionFailure.badCredentials =>
            MeetingFailureReason.accountRequired,
          _ => MeetingFailureReason.providerUnavailable,
        }, connected.detail);
      }
      final disco = XmppDisco(channel: session);
      final muc = await disco.findMucComponent(domain);
      if (!muc.ok) {
        throw MeetingJoinException(
          muc.failure == DiscoFailure.notFound
              ? MeetingFailureReason.meetingTypeUnsupported
              : MeetingFailureReason.providerUnavailable,
          'geen muc-component',
        );
      }
      live = await JitsiMeetingSession.start(
        channel: session,
        mediaCore: _mediaCoreFactory(),
        roomJid: '$room@${muc.value!}',
        focusJid: 'focus.$domain',
        displayName: request.displayName,
        startMuted: request.startMuted,
        startCameraOff: request.startCameraOff,
        closeSession: session.close,
        nickFactory: _nickFactory,
      );
      return live;
    } on Object {
      await session.close();
      rethrow;
    }
  }

  /// De deployment kan alles — dit beschrijft wat de server biedt, niet wat
  /// er nu live is; echte sporen meldt de sessie pas als ze er zijn (#2534+).
  static const _capabilities = MeetingCapabilities(
    audio: true,
    video: true,
    screenShare: true,
    chat: true,
    roster: true,
  );

  MeetingPreflight _unavailable(String? detail) => MeetingPreflight(
    support: MeetingSupport.nativeClient,
    capabilities: _capabilities,
    e2ee: MeetingE2eeStatus.off,
    failureReason: MeetingFailureReason.providerUnavailable,
    diagnosticsDetail: detail,
  );

  MeetingPreflight _unsupported(String? detail) => MeetingPreflight(
    support: MeetingSupport.unsupported,
    capabilities: const MeetingCapabilities(),
    e2ee: MeetingE2eeStatus.off,
    failureReason: MeetingFailureReason.meetingTypeUnsupported,
    diagnosticsDetail: detail,
  );

  /// De oorsprongen die verkeer ontvangen — eerlijk incl. een afwijkende
  /// websocket-host en het ontdekte MUC-component.
  List<String> _egress(Uri invitation, String websocket, String? muc) {
    final out = <String>['${invitation.scheme}://${invitation.authority}'];
    final ws = Uri.tryParse(websocket);
    if (ws != null && ws.hasScheme) {
      final wsOrigin = '${ws.scheme}://${ws.authority}';
      if (!out.contains(wsOrigin)) out.add(wsOrigin);
    }
    if (muc != null && muc.isNotEmpty) out.add('xmpp:$muc');
    return out;
  }
}

/// De live signalling-proef: WebSocket → SASL-anonymous → XEP-0030-walk naar
/// de MUC-component. Houdt per ontwerp niets open; de sessie sluit altijd.
Future<JitsiSignallingResult> _liveSignallingProbe(
  XmppSettings settings,
  String xmppDomain,
) async {
  final XmppFrameTransport transport;
  try {
    transport = await openXmppFrameTransport(settings);
  } on XmppConnectException {
    return const JitsiSignallingResult.failed(
      MeetingFailureReason.providerUnavailable,
    );
  }
  final session = XmppSession(transport: transport, settings: settings);
  try {
    final result = await session.connect();
    if (!result.ok) {
      return JitsiSignallingResult.failed(switch (result.failure!) {
        // Geen anoniem mechanisme = accounts vereist; een geweigerde
        // anonymous-auth is het bewijs dat gasten hier niet mogen.
        XmppSessionFailure.noUsableMechanism ||
        XmppSessionFailure.badCredentials =>
          MeetingFailureReason.accountRequired,
        _ => MeetingFailureReason.providerUnavailable,
      });
    }
    final disco = XmppDisco(channel: session);
    final muc = await disco.findMucComponent(xmppDomain);
    if (!muc.ok) {
      return JitsiSignallingResult.failed(
        muc.failure == DiscoFailure.notFound
            ? MeetingFailureReason.meetingTypeUnsupported
            : MeetingFailureReason.providerUnavailable,
      );
    }
    return JitsiSignallingResult.ok(muc.value!);
  } finally {
    await session.close();
  }
}
