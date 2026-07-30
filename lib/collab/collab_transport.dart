// The transport seam of the collaboration layer (COLLABORATION.md §5.6, P6).
//
// The sync/authority/lock logic in `collab_session.dart` is written against this
// thin interface, not against any network stack, so it can be built and unit-
// tested with no infrastructure. [LoopbackHub] is the in-process implementation
// used by the tests and the "two local windows" precedent (COLLABORATION.md §3);
// a Matrix implementation (`matrix_transport.dart`) and a WebDAV async one come
// later, behind this same interface.
//
// A transport is a dumb pipe: it carries already-formed events between
// participants and does not interpret them. Ordering, versioning and authority
// live one layer up in [CollabSession] — the transport only guarantees that what
// one participant sends, the others receive.

import 'dart:async';

import 'deck_op.dart';

/// A lock event: a participant claims ([held] true) or releases ([held] false)
/// the exclusive right to edit the slide [slideId]. Per COLLABORATION.md §5.4 a
/// held slide-lock makes its holder the sole writer of that slide, so edits are
/// local and conflict-free while the lock is held.
class LockEvent {
  const LockEvent({
    required this.slideId,
    required this.held,
    required this.participantId,
    this.forced = false,
  });

  final String slideId;
  final bool held;
  final String participantId;

  /// A release the authority imposed on a lock it does not hold (§5.4's
  /// `ForceUnlock`). Followers honour it regardless of who holds the lock,
  /// where an ordinary release only clears a lock its own holder gives up.
  final bool forced;
}

/// The pipe the collaboration layer sends and receives over. Implementations:
/// [LoopbackTransport] (in-process, tests), later a Matrix and a WebDAV one.
abstract interface class CollabTransport {
  /// This participant's stable id within the session.
  String get participantId;

  /// Broadcast [op] to the other participants.
  Future<void> sendOp(DeckOp op);

  /// Ops arriving from other participants, in the order the transport delivered
  /// them. Never includes this participant's own [sendOp]s.
  Stream<DeckOp> get ops;

  /// Broadcast a lock claim/release. [forced] marks an authority-imposed
  /// release of a lock it does not hold (see [LockEvent.forced]).
  Future<void> setLock(String slideId, {required bool held, bool forced});

  /// Lock events from other participants.
  Stream<LockEvent> get locks;

  /// Detach from the pipe and release its resources. Idempotent.
  Future<void> dispose();
}

/// An in-process relay: every [LoopbackTransport] created by [connect] delivers
/// each other transport's sends, and never echoes a participant's own sends back
/// to itself. This is the whole transport layer for tests and for the single-
/// machine two-window case, with the same surface a networked transport exposes.
class LoopbackHub {
  final List<LoopbackTransport> _members = [];

  /// Join the hub as [participantId] and get a transport bound to it.
  LoopbackTransport connect(String participantId) {
    final t = LoopbackTransport._(this, participantId);
    _members.add(t);
    return t;
  }

  void _broadcastOp(LoopbackTransport from, DeckOp op) {
    for (final m in _members) {
      if (!identical(m, from)) m._deliverOp(op);
    }
  }

  void _broadcastLock(LoopbackTransport from, LockEvent event) {
    for (final m in _members) {
      if (!identical(m, from)) m._deliverLock(event);
    }
  }

  void _remove(LoopbackTransport t) => _members.remove(t);
}

/// A single participant's end of a [LoopbackHub]. Create it with
/// [LoopbackHub.connect], not directly.
class LoopbackTransport implements CollabTransport {
  LoopbackTransport._(this._hub, this.participantId);

  final LoopbackHub _hub;

  @override
  final String participantId;

  // Broadcast so a late listener (a session that subscribes after connecting)
  // still works; the hub only relays live, so no missed-event buffering is
  // promised here — that is Matrix's job (§6.2), not the loopback's.
  final _ops = StreamController<DeckOp>.broadcast();
  final _locks = StreamController<LockEvent>.broadcast();
  bool _disposed = false;

  @override
  Stream<DeckOp> get ops => _ops.stream;

  @override
  Stream<LockEvent> get locks => _locks.stream;

  @override
  Future<void> sendOp(DeckOp op) async {
    _ensureLive();
    _hub._broadcastOp(this, op);
  }

  @override
  Future<void> setLock(
    String slideId, {
    required bool held,
    bool forced = false,
  }) async {
    _ensureLive();
    _hub._broadcastLock(
      this,
      LockEvent(
        slideId: slideId,
        held: held,
        participantId: participantId,
        forced: forced,
      ),
    );
  }

  void _deliverOp(DeckOp op) {
    if (!_disposed) _ops.add(op);
  }

  void _deliverLock(LockEvent event) {
    if (!_disposed) _locks.add(event);
  }

  void _ensureLive() {
    if (_disposed) {
      throw StateError('sendOp/setLock on a disposed LoopbackTransport');
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _hub._remove(this);
    await _ops.close();
    await _locks.close();
  }
}
