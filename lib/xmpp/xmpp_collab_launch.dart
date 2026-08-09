// Assembling a live XMPP collaboration session from the bricks
// (`docs/design/XMPP_COLLAB_TRANSPORT.md` §5–6, §8, sub-plak 6): the XMPP
// counterpart of `matrix_session_launch.dart`. The crypto (`CollabCrypto`), the
// stanza channel + demux (`XmppStanzaChannel` + `CompanionDemux`), the data-
// plane (`XmppTransport`), the key exchange (`XmppKeyExchange`) and the snapshot
// channel (`XmppSnapshotChannel`) each stand alone and are tested alone; this
// is the thin seam that wires them into "host a session" / "join a session" so
// a caller — a provider, a menu action — does not have to know their internal
// order.
//
// Where it diverges from the Matrix launch (and why):
//
//   • **Push, not poll.** Matrix's `transport.syncOnce()` polls `/sync`; XMPP
//     is push — stanzas arrive on the demux and route to the bricks as they
//     come. So [XmppCollabLaunch.syncNow] does not poll the transport; it
//     drives the reactive side-effects that a poll would have triggered on
//     Matrix: the host keys any newcomer it has learned
//     ([XmppKeyExchange.ensureKeyed]) and re-sends the baseline to a just-
//     keyed newcomer (§6: a MUC gives no `/sync`-achtergrond, so the snapshot
//     comes *after* the keyshare); the guest retries a buffered snapshot and,
//     once one opens, starts its session on the authority's slide-id space
//     (§5.5).
//
//   • **NEW-6: two recovery paths.** A MUC has no resumable cursor, so a drop
//     is a gap. Which gap depends on *when* the drop happened:
//       - **Before keying** — the guest published device-keys but dropped
//         before the host keyed him; he holds no epoch key. On rejoin the
//         transport's gap→resync emission fails silently (`seal` throws
//         `no-epoch`), and the host's next [syncNow] → `ensureKeyed` re-keys
//         him (idempotent — a keyshare that went lost is not in `_keyed`).
//         No resync, no re-baseline; just re-keying.
//       - **After keying** — the guest holds an epoch key. On rejoin the
//         transport emits a sealed `<resync>`; the authority's
//         `onResyncRequested` re-baselines; the guest's `rebaselines` listener
//         re-bases (`CollabSession.rebaseTo`, forward-only). The admission
//         gate (`resyncApprovalGate`, NEW-1 §7) ensures a *departed* member
//         who still holds an old epoch key cannot force a deck-wide broadcast
//         — the gate tests current-approved-set membership, not
//         decryptability.
//
//   • **Presence + chat (sub-plak 7).** De resterende data-plane-kanalen rijden
//     nu ook over de draad: [XmppPresenceBeacon] (verzegelde slide-position,
//     latest-per-sender) en [XmppChat] (verzegeld + ondertekend + sealed-id-
//     dedup, §4). [syncNow] retryt beide bricks' buffers elke ronde, voor host
//     en guest — een joiner ziet presence/chat vóór zijn keyshare (§6).

import 'dart:async';

import '../collab/collab_crypto.dart';
import '../collab/collab_device_directory.dart';
import '../collab/collab_participant.dart';
import '../collab/collab_session.dart';
import '../collab/collab_snapshot.dart';
import '../models/deck.dart';
import 'companion_demux.dart';
import 'xmpp_chat.dart';
import 'xmpp_key_exchange.dart';
import 'xmpp_presence_beacon.dart';
import 'xmpp_session.dart';
import 'xmpp_snapshot.dart';
import 'xmpp_transport.dart';

/// A launched (or launching) XMPP session and the machinery behind it. The host
/// starts active; a guest starts inactive and its [session] appears once the
/// authority's baseline has been received and opened during a [syncNow].
class XmppCollabLaunch {
  XmppCollabLaunch._({
    required this.transport,
    required this.keyExchange,
    required this.snapshotChannel,
    required this.presence,
    required this.chat,
    required this.demux,
    required this.isHost,
    required Deck deck,
    CollabSession? initialSession,
  }) : _localDeck = deck,
       _session = initialSession {
    if (_session != null) _ready.complete(_session);
  }

  final XmppTransport transport;
  final XmppKeyExchange keyExchange;
  final XmppSnapshotChannel snapshotChannel;
  final XmppPresenceBeacon presence;
  final XmppChat chat;
  final CompanionDemux demux;
  final bool isHost;
  final Deck _localDeck;

  CollabSession? _session;
  Timer? _timer;
  bool _disposed = false;
  final _ready = Completer<CollabSession>();
  StreamSubscription<CollabSnapshot>? _rebaselineSub;

  /// The last keyed-device count the host saw — to detect a newcomer just
  /// keyed by [XmppKeyExchange.ensureKeyed] and re-send the baseline (§6).
  int _lastKeyed = 0;

  /// The live session, or null for a guest still waiting for the baseline.
  CollabSession? get session => _session;

  /// Whether the session has started (always true for a host; true for a guest
  /// once it has received and opened the baseline).
  bool get isActive => _session != null;

  /// Completes when the session starts — immediately for a host, and for a
  /// guest once [syncNow] has opened the baseline.
  Future<CollabSession> get sessionReady => _ready.future;

  /// The devices in this session for the verification UI (§4.3): this device
  /// first (labelled with its device-id), then every verified peer, each with
  /// the fingerprint of its identity key to compare out-of-band.
  List<CollabParticipant> participants() {
    final own = keyExchange.ownKeys;
    return [
      CollabParticipant(
        userId: own.deviceId,
        deviceId: own.deviceId,
        identityKey: own.identityKey,
        fingerprint: deviceFingerprint(own.identityKey),
        isSelf: true,
        trust: TrustState.verified,
      ),
      // A device publishes its own `nl.ocideck.device`, so the key exchange
      // can read our own device back as a "peer". Drop it: it is already
      // listed as self above.
      for (final peer in keyExchange.peers)
        if (peer.keys.deviceId != own.deviceId)
          CollabParticipant(
            userId: peer.peerAddress,
            deviceId: peer.keys.deviceId,
            identityKey: peer.keys.identityKey,
            fingerprint: deviceFingerprint(peer.keys.identityKey),
            isSelf: false,
          ),
    ];
  }

  /// Announce dat dit device nu [slideId] bekijkt (§5 brick 4). Veilig te roepen
  /// vóór de sessie volledig draait; een ongewijzigde slide is een no-op.
  Future<void> announcePresence(String slideId) => presence.announce(slideId);

  /// Elke peer's laatst bekende positie, voor de presence-UI.
  List<PeerPresence> get presencePeers => presence.peers;

  /// Zet de callback die vuurt als een peer's presence verandert.
  set onPresenceChanged(void Function()? cb) => presence.onChanged = cb;

  /// Zend een chat-bericht naar de sessie (§5 brick 5). Lokaal meteen geëchood.
  Future<void> sendChat(String text) => chat.send(text);

  /// Het gesprek tot nu toe, oudste eerst.
  List<ChatMessage> get chatMessages => chat.messages;

  /// Zet de callback die vuurt als de chat-lijst groeit.
  set onChatChanged(void Function()? cb) => chat.onChanged = cb;

  /// Run one reactive round and its side-effects. The transport is push-driven
  /// (the demux routes stanzas as they arrive), so this does not poll — it
  /// drives the side-effects a Matrix poll would have triggered: the host keys
  /// any newcomer it has learned and re-sends the baseline to a just-keyed
  /// newcomer (§6); the guest retries a buffered snapshot and, once one opens,
  /// starts its session on the authority's slide-id space (§5.5). Presence en
  /// chat retryen hun buffers elke ronde — een joiner ziet ze vóór zijn keyshare.
  Future<void> syncNow() async {
    if (_disposed) return;
    // Short-circuit: als geen brick pending-entries heeft, is er niets te
    // retryen — sla de retry-calls over en bespaar CPU-wakeups op een idle
    // sessie (#1423). De host's ensureKeyed + re-baseline logica loopt nog
    // steeds (een newcomer kan tussentijds zijn goedgekeurd).
    final anyPending =
        presence.hasPending || chat.hasPending || snapshotChannel.hasPending;
    if (anyPending) {
      // Presence/chat kunnen aankomen vóór de epoch-sleutel (zelfde stroom als
      // de keyshare, of een eerdere) — retry de buffers elke ronde, host en
      // guest.
      await presence.retryPending();
      await chat.retryPending();
    }
    if (isHost) {
      await keyExchange.ensureKeyed();
      // A newcomer was just keyed — re-send the baseline so he can start (§6:
      // a MUC gives no `/sync`-achtergrond, so the snapshot comes after the
      // keyshare). Existing keyed devices see it as a forward-only re-
      // baseline and ignore it if their version is already ≥.
      if (_session != null && keyExchange.keyedDeviceCount > _lastKeyed) {
        _lastKeyed = keyExchange.keyedDeviceCount;
        await snapshotChannel.sendSnapshot(
          CollabSnapshot.capture(_session!.deck, _session!.version, 0),
        );
      }
      return;
    }
    if (snapshotChannel.hasPending) await snapshotChannel.retryPending();
    if (_session == null && snapshotChannel.hasSnapshot) {
      final snapshot = await snapshotChannel.firstSnapshot;
      _session = CollabSession(
        initialDeck: snapshot.applyTo(_localDeck),
        transport: transport,
        isAuthority: false,
        initialVersion: snapshot.version,
      );
      // §4 re-baseline: a later snapshot (after a post-keying drop+resync)
      // re-bases the session forward-only.
      _rebaselineSub = snapshotChannel.rebaselines.listen((snap) {
        if (_session != null) {
          _session!.rebaseTo(snap.applyTo(_session!.deck), snap.version);
        }
      });
      if (!_ready.isCompleted) _ready.complete(_session);
    }
  }

  /// Begin syncing on [interval]; the periodic driver of [syncNow]. Idempotent.
  void start({Duration interval = const Duration(seconds: 1)}) {
    if (_disposed) return;
    _timer ??= Timer.periodic(interval, (_) => syncNow());
  }

  /// End the session locally: stop the loop, dispose the session (and with it
  /// the transport), or the bare transport if no session started. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _rebaselineSub?.cancel();
    _rebaselineSub = null;
    if (_session != null) {
      await _session!.dispose();
    } else {
      await transport.dispose();
    }
    await snapshotChannel.dispose();
    await presence.dispose();
    await chat.dispose();
    await keyExchange.dispose();
    await demux.dispose();
  }
}

/// Host a session others can join. Publishes this device's keys, opens epoch 0,
/// pushes the baseline others join from, and starts as the authority. The
/// returned launch keys newcomers on each [XmppCollabLaunch.syncNow] and re-
/// baselines on a sealed `<resync>` (NEW-6 post-keying recovery, §4).
Future<XmppCollabLaunch> hostXmppSession({
  required XmppStanzaChannel stanzaChannel,
  required CollabCrypto crypto,
  required DevicePublicKeys ownKeys,
  required String roomJid,
  required Deck deck,
  required String ownUserId,
}) async {
  final parts = _wire(
    stanzaChannel: stanzaChannel,
    crypto: crypto,
    ownKeys: ownKeys,
    roomJid: roomJid,
    ownUserId: ownUserId,
    onReconnected: null, // authority does not resync-request on reconnect
  );
  await parts.keyExchange.publishDeviceKeys();
  await parts.keyExchange.distributeEpoch(const []); // epoch 0, owner only
  await parts.snapshotChannel.sendSnapshot(CollabSnapshot.capture(deck, 0, 0));
  final session = CollabSession(
    initialDeck: deck,
    transport: parts.transport,
    isAuthority: true,
  );
  // Authority-side: a coalesced `<resync>` request arrived → re-baseline (§4).
  // The admission gate (NEW-1 §7) ensures only current-approved-set members
  // can trigger it — a departed member still holds an old epoch key but is
  // no longer approved.
  parts.transport.onResyncRequested = () async {
    await parts.snapshotChannel.sendSnapshot(
      CollabSnapshot.capture(session.deck, session.version, 0),
    );
  };
  parts.transport.resyncApprovalGate = parts.keyExchange.isApproved;
  return XmppCollabLaunch._(
    transport: parts.transport,
    keyExchange: parts.keyExchange,
    snapshotChannel: parts.snapshotChannel,
    presence: parts.presence,
    chat: parts.chat,
    demux: parts.demux,
    isHost: true,
    deck: deck,
    initialSession: session,
  ); // _lastKeyed stays 0 — distributeEpoch([]) keys no one, so the first
  // ensureKeyed that keys a newcomer triggers a baseline re-send
}

/// Join a session another author is hosting for this deck. Publishes this
/// device's keys and returns a launch whose session appears once
/// [XmppCollabLaunch.syncNow] has received the key-share and opened the
/// baseline; the guest then adopts the authority's slide ids (§5.5) onto
/// [localDeck]. [onReconnected] is the follower-side reconnect signal (from
/// `XmppSession.onReconnected` or a test fake) that feeds the transport's
/// gap→resync (NEW-6 post-keying recovery, §4).
Future<XmppCollabLaunch> joinXmppSession({
  required XmppStanzaChannel stanzaChannel,
  required CollabCrypto crypto,
  required DevicePublicKeys ownKeys,
  required String roomJid,
  required Deck localDeck,
  required String ownUserId,
  Stream<void>? onReconnected,
}) async {
  final parts = _wire(
    stanzaChannel: stanzaChannel,
    crypto: crypto,
    ownKeys: ownKeys,
    roomJid: roomJid,
    ownUserId: ownUserId,
    onReconnected: onReconnected,
  );
  await parts.keyExchange.publishDeviceKeys();
  return XmppCollabLaunch._(
    transport: parts.transport,
    keyExchange: parts.keyExchange,
    snapshotChannel: parts.snapshotChannel,
    presence: parts.presence,
    chat: parts.chat,
    demux: parts.demux,
    isHost: false,
    deck: localDeck,
  );
}

/// The directory, key exchange, snapshot channel, presence beacon, chat,
/// transport and demux, wired so the demux's single subscription fans out to
/// each brick by namespace.
_WireResult _wire({
  required XmppStanzaChannel stanzaChannel,
  required CollabCrypto crypto,
  required DevicePublicKeys ownKeys,
  required String roomJid,
  required String ownUserId,
  Stream<void>? onReconnected,
}) {
  final demux = CompanionDemux(channel: stanzaChannel);
  final directory = CollabDeviceDirectory();
  final keyExchange = XmppKeyExchange(
    stanzaChannel: stanzaChannel,
    companionDemux: demux,
    crypto: crypto,
    roomJid: roomJid,
    directory: directory,
    ownKeys: ownKeys,
  );
  final snapshotChannel = XmppSnapshotChannel(
    stanzaChannel: stanzaChannel,
    companionDemux: demux,
    crypto: crypto,
    roomJid: roomJid,
    directory: directory,
  );
  final presence = XmppPresenceBeacon(
    stanzaChannel: stanzaChannel,
    companionDemux: demux,
    crypto: crypto,
    roomJid: roomJid,
    directory: directory,
  );
  final chat = XmppChat(
    stanzaChannel: stanzaChannel,
    companionDemux: demux,
    crypto: crypto,
    roomJid: roomJid,
    directory: directory,
    ownUserId: ownUserId,
  );
  final transport = XmppTransport(
    stanzaChannel: stanzaChannel,
    companionDemux: demux,
    crypto: crypto,
    roomJid: roomJid,
    peerResolver: (id) async => directory.resolve(id),
    onReconnected: onReconnected,
  );
  // Wire de key-change callback: als een nieuwe device-sleutel of epoch-
  // sleutel wordt geïnstalleerd, retry de transport zijn deferred backlog
  // (#1424). Zonder deze callback zou de backlog alleen bij elke nieuwe
  // op/lock-stanza worden gesweept — O(N²) bij een vloed stanzas.
  keyExchange.onKeyInstalled = transport.notifyKeyChanged;
  return _WireResult(
    demux: demux,
    directory: directory,
    keyExchange: keyExchange,
    snapshotChannel: snapshotChannel,
    presence: presence,
    chat: chat,
    transport: transport,
  );
}

class _WireResult {
  _WireResult({
    required this.demux,
    required this.directory,
    required this.keyExchange,
    required this.snapshotChannel,
    required this.presence,
    required this.chat,
    required this.transport,
  });

  final CompanionDemux demux;
  final CollabDeviceDirectory directory;
  final XmppKeyExchange keyExchange;
  final XmppSnapshotChannel snapshotChannel;
  final XmppPresenceBeacon presence;
  final XmppChat chat;
  final XmppTransport transport;
}
