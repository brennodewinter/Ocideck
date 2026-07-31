// The realtime collaboration transport over a Matrix room used as an encrypted
// relay (`docs/design/SELF_ENCRYPTED_RELAY.md` §7, phase P-C). It composes the
// two lower bricks — [MatrixClient] for carriage (P-B) and [CollabCrypto] for
// confidentiality (P-A) — behind the same [CollabTransport] seam that
// `LoopbackTransport` and `WebdavAsyncTransport` implement. So the
// authority/version/lock logic in `collab_session.dart` drives it **unchanged**:
// the only thing that changes below the seam is that events now travel sealed
// through a homeserver that sees ciphertext (P4).
//
// Shape mirrors `WebdavAsyncTransport`: a participant never hears its own sends
// (matched on the sealed envelope's `sender_device`), and inbound events are
// applied strictly as the server delivers them — which for Matrix is canonical,
// gap-free order (§6.2), so no sequence bookkeeping is needed here. Unlike the
// WebDAV log there is no numbered store: the room *is* the ordered log, and
// [syncOnce] pulls the next batch. [start] runs the periodic sync; the tests call
// [syncOnce] directly for a deterministic, wall-clock-free drive.
//
// **Fail-closed.** A malformed, forged, wrongly-addressed or un-openable event is
// logged and dropped — never applied, never allowed to wedge the stream or desync
// the session (§11). This is what keeps a hostile homeserver from doing anything
// worse than withholding or reordering (which the version rule already tolerates).
//
// **Scope of P-C.** This carries the op/lock data plane and opens it with keys the
// session already holds. Establishing those keys over the wire — publishing device
// keys as room state, distributing the epoch key via to-device key-shares, and the
// presence-based handover — is the session lifecycle, wired in P-D/P-E. Here the
// crypto arrives already keyed and peers are resolved through [resolvePeer], so the
// sealed data plane can be driven and tested end to end on its own.

import 'dart:async';

import '../utils/log.dart';
import 'collab_codec.dart';
import 'collab_crypto.dart';
import 'collab_transport.dart';
import 'deck_op.dart';
import 'matrix_client.dart';

/// Resolves a sender device id to its (binding-verified) public keys, so an
/// inbound sealed event can be opened and its signature checked. In production
/// this is backed by the room's `nl.ocideck.device` state (P-D); in tests it is a
/// small in-memory directory. Returns null for an unknown device, which drops the
/// event fail-closed.
typedef PeerResolver = Future<DevicePublicKeys?> Function(String senderDevice);

/// A [CollabTransport] over an encrypted Matrix room. Construct one per
/// participant against a shared [roomId]; [crypto] must already hold the session
/// epoch key (see the P-C scope note above).
class MatrixRelayTransport implements CollabTransport {
  MatrixRelayTransport({
    required MatrixClient client,
    required CollabCrypto crypto,
    required this.roomId,
    required PeerResolver resolvePeer,
    this.onSystemEvent,
    this.onToDevice,
    this.syncInterval = const Duration(seconds: 1),
  }) : _matrix = client,
       _e2ee = crypto,
       _resolver = resolvePeer;

  static const opEventType = 'nl.ocideck.op';
  static const lockEventType = 'nl.ocideck.lock';

  final MatrixClient _matrix;
  final CollabCrypto _e2ee;
  final String roomId;
  final PeerResolver _resolver;

  /// Called for each timeline event that is not an op or a lock — the room state
  /// the session lifecycle cares about (device keys, authority beacon). The relay
  /// owns the single sync loop, so it forwards these rather than each collaborator
  /// running its own loop and fighting over the sync token. Null in the P-C tests,
  /// wired to the key exchange (P-D) in a live session.
  final Future<void> Function(MatrixTimelineEvent event)? onSystemEvent;

  /// Called for each to-device message — the key-share carrier (§4.3). Same
  /// single-loop reasoning as [onSystemEvent].
  final Future<void> Function(MatrixToDeviceEvent event)? onToDevice;

  /// How often [start]'s loop syncs. Realtime-ish; the server long-polls, so this
  /// is the gap between rounds, not a busy-poll.
  final Duration syncInterval;

  final _ops = StreamController<DeckOp>.broadcast();
  final _locks = StreamController<LockEvent>.broadcast();

  String? _since;
  Timer? _timer;
  bool _syncing = false;
  bool _disposed = false;

  /// The participant id is this device's id — the same value the crypto stamps
  /// into every sealed envelope as `sender_device`, so own-echo suppression and
  /// the collab layer's participant identity line up.
  @override
  String get participantId => _e2ee.deviceId;

  @override
  Stream<DeckOp> get ops => _ops.stream;

  @override
  Stream<LockEvent> get locks => _locks.stream;

  @override
  Future<void> sendOp(DeckOp op) async {
    _ensureLive();
    final sealed = await _e2ee.seal(
      {'kind': 'op', 'from': participantId, 'op': deckOpToJson(op)},
      room: roomId,
      type: opEventType,
      // Authoritative ops (version assigned) carry the authority's signature
      // (P3 anti-impersonation); a follower's intent (version 0) need not.
      signed: op.version > 0,
    );
    await _matrix.sendEvent(
      roomId: roomId,
      type: opEventType,
      content: sealed.toContent(),
    );
  }

  @override
  Future<void> setLock(
    String slideId, {
    required bool held,
    bool forced = false,
  }) async {
    _ensureLive();
    final event = LockEvent(
      slideId: slideId,
      held: held,
      participantId: participantId,
      forced: forced,
    );
    final sealed = await _e2ee.seal(
      {'kind': 'lock', 'from': participantId, 'lock': lockEventToJson(event)},
      room: roomId,
      type: lockEventType,
      signed: false,
    );
    await _matrix.sendEvent(
      roomId: roomId,
      type: lockEventType,
      content: sealed.toContent(),
    );
  }

  /// Begin syncing on [syncInterval]. Idempotent; a no-op after [dispose].
  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(syncInterval, (_) => syncOnce());
  }

  /// Run one sync round: fetch the events since the last batch and dispatch the
  /// ones from other participants. Safe to call directly ("sync now") or from the
  /// timer; overlapping calls are collapsed.
  Future<void> syncOnce() async {
    if (_disposed || _syncing) return;
    _syncing = true;
    try {
      final result = await _matrix.sync(since: _since);
      _since = result.nextBatch;
      for (final event in result.timeline) {
        if (_disposed) return;
        await _dispatch(event);
      }
      for (final event in result.toDevice) {
        if (_disposed) return;
        await onToDevice?.call(event);
      }
    } on MatrixException catch (e) {
      // Transient server trouble: keep the since token and try next round.
      logWarning('collab.matrix.sync', e);
    } finally {
      _syncing = false;
    }
  }

  Future<void> _dispatch(MatrixTimelineEvent event) async {
    if (event.type != opEventType && event.type != lockEventType) {
      // Not our data plane — hand room state (device keys, beacon) to whoever
      // registered for it (the key exchange, P-D). Own errors are the handler's.
      await onSystemEvent?.call(event);
      return;
    }
    try {
      final sealed = SealedEnvelope.fromContent(event.content);
      if (sealed.senderDevice == participantId) return; // own send
      final sender = await _resolver(sealed.senderDevice);
      if (sender == null) {
        logWarning('collab.matrix.unknownSender', sealed.senderDevice);
        return;
      }
      final envelope = await _e2ee.open(
        sealed,
        room: roomId,
        type: event.type,
        sender: sender,
      );
      _emit(event.type, envelope);
    } on Exception catch (e) {
      // Malformed/forged/un-openable: drop it fail-closed. One poison event must
      // not wedge the stream or desync the session (§11). A well-formed peer
      // never produces one; this fires on corruption or an attack.
      logWarning('collab.matrix.dispatch', e);
    }
  }

  void _emit(String type, Map<String, Object?> envelope) {
    switch (type) {
      case opEventType:
        _ops.add(deckOpFromJson(_asObject(envelope['op'])));
      case lockEventType:
        _locks.add(lockEventFromJson(_asObject(envelope['lock'])));
    }
  }

  Map<String, Object?> _asObject(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.map((k, v) => MapEntry('$k', v));
    throw const FormatException('expected an object in a sealed envelope');
  }

  void _ensureLive() {
    if (_disposed) {
      throw StateError('use of a disposed MatrixRelayTransport');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _ops.close();
    await _locks.close();
  }
}
