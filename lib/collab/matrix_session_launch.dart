// Assembling a live Matrix collaboration session from the bricks
// (`docs/design/SELF_ENCRYPTED_RELAY.md` §6.5 lifecycle, phase P-D). The crypto
// (P-A), the CS client (P-B), the relay transport (P-C), the key exchange and the
// snapshot channel (P-D) each stand alone and are tested alone; this is the thin
// seam that wires them into "host a session" / "join a session" so a caller — a
// provider, a menu action — does not have to know their internal order. It mirrors
// the WebDAV `hostCollabSession`/`joinCollabSession` (`collab_session_launch.dart`).
//
// The subtlety a live join must handle is ordering: a joiner sees the snapshot
// chunks (room timeline) before its key-share (a to-device message the authority
// sends only once it notices the joiner). So the join does not block on the
// snapshot; it syncs, and the snapshot channel keeps the reassembled baseline
// buffered until the key-share installs the epoch key, at which point
// [MatrixCollabLaunch.syncNow] retries the open and lazily starts the session. The
// authority side reacts symmetrically: each [syncNow] keys any newcomer it has
// learned ([MatrixKeyExchange.ensureKeyed]).

import 'dart:async';

import '../models/deck.dart';
import 'collab_crypto.dart';
import 'collab_session.dart';
import 'collab_snapshot.dart';
import 'matrix_client.dart';
import 'matrix_key_exchange.dart';
import 'matrix_relay_transport.dart';
import 'matrix_snapshot.dart';

/// A launched (or launching) Matrix session and the machinery behind it. The host
/// starts active; a guest starts inactive and its [session] appears once the
/// authority's snapshot has been received and opened during a [syncNow].
class MatrixCollabLaunch {
  MatrixCollabLaunch._({
    required this.transport,
    required this.keyExchange,
    required this.snapshotChannel,
    required this.isHost,
    required Deck deck,
    CollabSession? initialSession,
  }) : _localDeck = deck,
       _session = initialSession {
    if (_session != null) _ready.complete(_session);
  }

  final MatrixRelayTransport transport;
  final MatrixKeyExchange keyExchange;
  final MatrixSnapshotChannel snapshotChannel;
  final bool isHost;
  final Deck _localDeck;

  CollabSession? _session;
  Timer? _timer;
  bool _disposed = false;
  final _ready = Completer<CollabSession>();

  /// The live session, or null for a guest still waiting for the baseline.
  CollabSession? get session => _session;

  /// Whether the session has started (always true for a host; true for a guest
  /// once it has received and opened the baseline).
  bool get isActive => _session != null;

  /// Completes when the session starts — immediately for a host, and for a guest
  /// once [syncNow] has opened the baseline. The provider awaits this to wire the
  /// deck controller and mark the tab active without polling [isActive].
  Future<CollabSession> get sessionReady => _ready.future;

  /// Run one sync round and its side effects: the host keys any newcomer it has
  /// learned; a guest retries a buffered snapshot and, once one opens, starts its
  /// session on the authority's slide-id space (§5.5).
  Future<void> syncNow() async {
    if (_disposed) return;
    await transport.syncOnce();
    if (isHost) {
      await keyExchange.ensureKeyed();
      return;
    }
    await snapshotChannel.retryPending();
    if (_session == null && snapshotChannel.hasSnapshot) {
      final snapshot = await snapshotChannel.firstSnapshot;
      _session = CollabSession(
        initialDeck: snapshot.applyTo(_localDeck),
        transport: transport,
        isAuthority: false,
        initialVersion: snapshot.version,
      );
      if (!_ready.isCompleted) _ready.complete(_session);
    }
  }

  /// Begin syncing on [interval]; the periodic driver of [syncNow]. Idempotent.
  void start({Duration interval = const Duration(seconds: 1)}) {
    if (_disposed) return;
    _timer ??= Timer.periodic(interval, (_) => syncNow());
  }

  /// End the session locally: stop the loop, dispose the session (and with it the
  /// transport), or the bare transport if no session started. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    if (_session != null) {
      await _session!.dispose();
    } else {
      await transport.dispose();
    }
  }
}

/// Host a session others can join. Publishes this device's keys, opens epoch 0,
/// pushes the baseline others join from, and starts as the authority. The returned
/// launch keys newcomers on each [MatrixCollabLaunch.syncNow].
Future<MatrixCollabLaunch> hostMatrixSession({
  required MatrixClient client,
  required CollabCrypto crypto,
  required DevicePublicKeys ownKeys,
  required String roomId,
  required Deck deck,
}) async {
  final parts = _wire(
    client: client,
    crypto: crypto,
    ownKeys: ownKeys,
    roomId: roomId,
  );
  await parts.keyExchange.publishDeviceKeys();
  await parts.keyExchange.distributeEpoch(const []); // epoch 0, owner only
  await parts.snapshotChannel.sendSnapshot(CollabSnapshot.capture(deck, 0, 0));
  final session = CollabSession(
    initialDeck: deck,
    transport: parts.transport,
    isAuthority: true,
  );
  return MatrixCollabLaunch._(
    transport: parts.transport,
    keyExchange: parts.keyExchange,
    snapshotChannel: parts.snapshotChannel,
    isHost: true,
    deck: deck,
    initialSession: session,
  );
}

/// Join a session another author is hosting for this deck. Publishes this device's
/// keys and returns a launch whose session appears once [MatrixCollabLaunch.syncNow]
/// has received the key-share and opened the baseline; the guest then adopts the
/// authority's slide ids (§5.5) onto [localDeck].
Future<MatrixCollabLaunch> joinMatrixSession({
  required MatrixClient client,
  required CollabCrypto crypto,
  required DevicePublicKeys ownKeys,
  required String roomId,
  required Deck localDeck,
}) async {
  final parts = _wire(
    client: client,
    crypto: crypto,
    ownKeys: ownKeys,
    roomId: roomId,
  );
  await parts.keyExchange.publishDeviceKeys();
  return MatrixCollabLaunch._(
    transport: parts.transport,
    keyExchange: parts.keyExchange,
    snapshotChannel: parts.snapshotChannel,
    isHost: false,
    deck: localDeck,
  );
}

/// The directory, key exchange, snapshot channel and transport, wired so the
/// transport's single sync loop feeds both the key exchange (device state,
/// key-shares) and the snapshot channel (baseline chunks).
_SessionParts _wire({
  required MatrixClient client,
  required CollabCrypto crypto,
  required DevicePublicKeys ownKeys,
  required String roomId,
}) {
  final directory = MatrixDeviceDirectory();
  final keyExchange = MatrixKeyExchange(
    client: client,
    crypto: crypto,
    roomId: roomId,
    directory: directory,
    ownKeys: ownKeys,
  );
  final snapshotChannel = MatrixSnapshotChannel(
    client: client,
    crypto: crypto,
    roomId: roomId,
    directory: directory,
  );
  final transport = MatrixRelayTransport(
    client: client,
    crypto: crypto,
    roomId: roomId,
    resolvePeer: (id) async => directory.resolve(id),
    onSystemEvent: (event) async {
      await keyExchange.handleSystemEvent(event);
      await snapshotChannel.handleSystemEvent(event);
    },
    onToDevice: keyExchange.handleToDevice,
  );
  return _SessionParts(
    transport: transport,
    keyExchange: keyExchange,
    snapshotChannel: snapshotChannel,
  );
}

class _SessionParts {
  _SessionParts({
    required this.transport,
    required this.keyExchange,
    required this.snapshotChannel,
  });

  final MatrixRelayTransport transport;
  final MatrixKeyExchange keyExchange;
  final MatrixSnapshotChannel snapshotChannel;
}
