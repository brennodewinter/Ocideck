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

/// What [MatrixRelayTransport._tryApply] decided about one op/lock event.
enum _ApplyOutcome { applied, permanentDrop, retryLater }

/// An op/lock event held back because its key-state was not yet in hand,
/// carrying how many sync rounds it has already waited (see the backlog cap).
class _DeferredEvent {
  _DeferredEvent(this.event, this.rounds);

  final MatrixTimelineEvent event;
  final int rounds;
}

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

  /// Serialises this transport's own sends so the sealed PUTs reach the room in
  /// the order the ops were created, even when [sendOp]/[setLock] calls overlap.
  /// The seal and the HTTP PUT are both async, so two fire-and-forget sends (the
  /// authority rebroadcasts several ops per edit without awaiting) could race and
  /// commit version 2 before version 1 — a follower only accepts `version + 1`,
  /// so the reordered op is dropped and the decks diverge (#1040). Matrix has no
  /// numbered append-chain like WebDAV; this queue is the equivalent.
  Future<void> _sendChain = Future<void>.value();

  /// Op/lock events that arrived before the key-state needed to open them — the
  /// sender's device keys or the epoch key-share — e.g. an authority edit made
  /// before the joiner was keyed. At an initial sync the timeline op and the
  /// key-state can land in the same round, and the since-cursor advances past
  /// the op regardless; without this backlog a valid op would be dropped as an
  /// "unknown sender" and lost for good, leaving the guest a version behind
  /// (#1041). Retried in arrival order after each sync once more key-state is
  /// processed. Bounded, and each entry is dropped fail-closed after
  /// [_maxDeferralRounds] fruitless retries so a hostile homeserver cannot pin
  /// memory by replaying undecryptable events.
  final List<_DeferredEvent> _deferred = [];
  static const int _maxDeferred = 256;
  static const int _maxDeferralRounds = 16;

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
  Future<void> sendOp(DeckOp op) {
    _ensureLive();
    return _serializeSend('op', () async {
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
    });
  }

  /// Append [send] to the serial [_sendChain] so it runs strictly after every
  /// earlier send this transport issued. A failure is logged (controlled
  /// reporting, not a silent drop) and does not wedge the chain — a later send
  /// still runs — while the returned future still surfaces the error to a caller
  /// that awaits it.
  Future<void> _serializeSend(String kind, Future<void> Function() send) {
    final done = _sendChain.then((_) => send());
    _sendChain = done.then(
      (_) {},
      onError: (Object e) => logWarning('collab.matrix.send.$kind', e),
    );
    return done;
  }

  @override
  Future<void> setLock(
    String slideId, {
    required bool held,
    bool forced = false,
  }) {
    _ensureLive();
    final event = LockEvent(
      slideId: slideId,
      held: held,
      participantId: participantId,
      forced: forced,
    );
    // Locks share the serial chain with ops so their relative order is preserved
    // too (a lock and the edit it guards must not cross on the wire).
    return _serializeSend('lock', () async {
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
    });
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
      // Key-state before data. Room state (device keys, authority beacon) and
      // to-device key-shares are handled first, so a sealed op that depends on
      // them can be opened in the same round rather than dropped as an unknown
      // sender while the cursor moves past it (#1041). Op/lock events are set
      // aside and dispatched after, replaying any earlier backlog first.
      final data = <MatrixTimelineEvent>[];
      for (final event in result.timeline) {
        if (_disposed) return;
        if (event.type == opEventType || event.type == lockEventType) {
          data.add(event);
        } else {
          // Room state — device keys, beacon — for the key exchange (P-D). Its
          // own errors are the handler's.
          await onSystemEvent?.call(event);
        }
      }
      for (final event in result.toDevice) {
        if (_disposed) return;
        await onToDevice?.call(event);
      }
      await _dispatchData(data);
    } on MatrixException catch (e) {
      // Transient server trouble: keep the since token and try next round.
      logWarning('collab.matrix.sync', e);
    } finally {
      _syncing = false;
    }
  }

  /// Dispatch op/lock events: the deferred backlog first (so cross-sync order is
  /// preserved), then the [fresh] ones. An event that still cannot be opened —
  /// its sender or epoch key not yet in hand — is re-deferred, bounded by count
  /// and by retry rounds, rather than dropped and lost.
  Future<void> _dispatchData(List<MatrixTimelineEvent> fresh) async {
    final backlog = List<_DeferredEvent>.from(_deferred);
    _deferred.clear();
    final queue = <MatrixTimelineEvent>[
      for (final d in backlog) d.event,
      ...fresh,
    ];
    final rounds = {for (final d in backlog) d.event.eventId: d.rounds};
    for (final event in queue) {
      if (_disposed) return;
      if (await _tryApply(event) == _ApplyOutcome.retryLater) {
        final next = (rounds[event.eventId] ?? 0) + 1;
        if (next <= _maxDeferralRounds) {
          _deferred.add(_DeferredEvent(event, next));
        } else {
          // Exhausted its retries: a forged event, or key-state that never came.
          // Drop it fail-closed rather than retry forever (§11).
          logWarning('collab.matrix.deferred.expired', event.eventId);
        }
      }
    }
    if (_deferred.length > _maxDeferred) {
      _deferred.removeRange(0, _deferred.length - _maxDeferred);
    }
  }

  /// Try to open and emit one op/lock event. Distinguishes a permanent drop
  /// (malformed, or our own echo) from a retryable miss (sender not yet known,
  /// or the sealed envelope not yet openable because the epoch key is still in
  /// flight). Forged and not-yet-keyed both surface as retryable — they are
  /// indistinguishable here — so the caller bounds how long they are retried.
  Future<_ApplyOutcome> _tryApply(MatrixTimelineEvent event) async {
    final SealedEnvelope sealed;
    try {
      sealed = SealedEnvelope.fromContent(event.content);
    } on Exception catch (e) {
      logWarning('collab.matrix.malformed', e);
      return _ApplyOutcome.permanentDrop;
    }
    if (sealed.senderDevice == participantId) {
      return _ApplyOutcome.permanentDrop; // own send
    }
    final sender = await _resolver(sealed.senderDevice);
    if (sender == null) {
      return _ApplyOutcome.retryLater; // device-state not seen yet
    }
    try {
      final envelope = await _e2ee.open(
        sealed,
        room: roomId,
        type: event.type,
        sender: sender,
      );
      _emit(event.type, envelope);
      return _ApplyOutcome.applied;
    } on Exception catch (e) {
      // Not-yet-installed epoch key (retry) or a forged/corrupt event (drop).
      logWarning('collab.matrix.open', e);
      return _ApplyOutcome.retryLater;
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
