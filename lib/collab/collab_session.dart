// The authority state machine and lock table of the collaboration layer
// (COLLABORATION.md §5.3–5.4). This is pure sync logic over a [CollabTransport];
// it has no network code of its own and is driven end-to-end in tests by a
// [LoopbackHub].
//
// Exactly one session in a room is the authority (P3). The authority assigns the
// monotonic [version] to every op — its own edits *and* the intents it receives
// from other participants — and rebroadcasts the authoritative op. Because every
// replica applies ops in [version] order, they all reproduce the authority's
// deck exactly, which is what lets this design sidestep CRDT/OT convergence.
//
// v1 scope, deliberately: a non-authority edit round-trips (it is sent as an
// intent and applied when the authoritative op echoes back) rather than being
// applied optimistically under a held lock — the latency-hiding half of §5.4 is
// a follow-up, and skipping it means there is never a local edit to roll back.
// A joiner from a re-baselined snapshot (§5.2) starts at a non-zero version via
// the constructor's `initialVersion`; from there the apply and resume rules below
// are unchanged.
//
// Owner-drop authority handover (§5.3) is built here as *mutable* authority: the
// role can flip after construction via [becomeAuthority] / [stepDown]. This class
// stays mechanism-neutral — it knows nothing of the beacon, the poll cadence, or
// who the owner is; a [HandoverCoordinator] one layer up decides *when* to flip it
// (that policy needs the WebDAV store and time, which have no place in this pure
// loop). Version *resumes* from the current [version]: a session that becomes the
// authority stamps the next op `version + 1`, so a successor that took over at the
// highest observed version continues the sequence without a gap or a collision.

import 'dart:async';

import '../models/deck.dart';
import 'collab_transport.dart';
import 'deck_op.dart';

class CollabSession {
  CollabSession({
    required Deck initialDeck,
    required this.transport,
    required bool isAuthority,
    int initialVersion = 0,
  }) : _deck = initialDeck,
       _authority = isAuthority,
       _version = initialVersion {
    _opSub = transport.ops.listen(_onRemoteOp);
    _lockSub = transport.locks.listen(_onRemoteLock);
  }

  final CollabTransport transport;

  /// Whether this session currently assigns versions (COLLABORATION.md §5.3).
  /// Mutable: owner-drop handover flips it via [becomeAuthority] / [stepDown].
  /// Persistence (only the owner may `saveDeck`) is gated on the launch *role*
  /// one layer up, not on this flag — a temporary authority has `isAuthority`
  /// true but must not persist.
  bool _authority;
  bool get isAuthority => _authority;

  Deck _deck;

  /// The highest version applied. Starts at the constructor's `initialVersion` —
  /// non-zero when a joiner begins from a re-baselined snapshot (§5.2), so it
  /// applies only ops above that version and (as authority) resumes assigning
  /// from there.
  int _version;
  final Map<String, String> _locks = {}; // slideId -> holding participantId
  late final StreamSubscription<DeckOp> _opSub;
  late final StreamSubscription<LockEvent> _lockSub;
  final _deckChanges = StreamController<Deck>.broadcast();
  final _lockChanges = StreamController<Map<String, String>>.broadcast();
  bool _disposed = false;

  /// The current deck as this session sees it.
  Deck get deck => _deck;

  /// Emits the new deck after every applied op.
  Stream<Deck> get deckChanges => _deckChanges.stream;

  /// The highest version this session has applied.
  int get version => _version;

  /// Who currently holds which slide lock (slideId -> participantId).
  Map<String, String> get locks => Map.unmodifiable(_locks);

  /// Emits the whole lock table after every change.
  Stream<Map<String, String>> get lockChanges => _lockChanges.stream;

  String get participantId => transport.participantId;

  /// Take over version assignment (owner-drop handover, §5.3). Idempotent. New
  /// commits resume from the current [version], so a successor that took over at
  /// the highest observed version continues the sequence without a gap. Whether
  /// this session is *allowed* to take over — caught up, the previous authority
  /// really gone — is the [HandoverCoordinator]'s call; this only flips the role.
  void becomeAuthority() {
    if (_disposed) return;
    _authority = true;
  }

  /// Relinquish version assignment and return to following the authority
  /// (hand-back when the owner returns, §5.3). Idempotent. Applied authoritative
  /// ops keep flowing in [version] order; [version] is left where it is.
  void stepDown() {
    if (_disposed) return;
    _authority = false;
  }

  /// Jump forward to a re-baselined snapshot (§5.2 strand-recovery): adopt its
  /// [deck] (the authority's slides) at [version]. **Forward-only** — a version
  /// at or below the current one is ignored, so a stale or half-read snapshot can
  /// never rewind the session or replay an op. Emits [deckChanges] so the tab
  /// re-reads the jumped-to state. Returns whether it jumped.
  bool rebaseTo(Deck deck, int version) {
    if (_disposed || version <= _version) return false;
    _deck = deck;
    _version = version;
    _deckChanges.add(_deck);
    return true;
  }

  /// Submit a local edit. Build [op] with `version: 0` (unassigned); the session
  /// fills the authoritative version. The authority commits immediately; a
  /// non-authority sends the intent and applies the authoritative op when it
  /// echoes back.
  Future<void> submit(DeckOp op) async {
    _ensureLive();
    if (isAuthority) {
      _commit(op);
    } else {
      await transport.sendOp(op); // version 0 = intent for the authority
    }
  }

  void _commit(DeckOp intent) {
    final op = intent.copyWithVersion(_version + 1);
    _deck = applyOp(_deck, op); // throws on an invalid op — fail-closed (P3)
    _version = op.version;
    _deckChanges.add(_deck);
    transport.sendOp(op); // authoritative, version >= 1
  }

  void _onRemoteOp(DeckOp op) {
    if (isAuthority) {
      // Anything reaching the authority is a non-authority intent; commit it so
      // it gets an authoritative version and is rebroadcast in order.
      _commit(op);
    } else if (op.version == _version + 1) {
      // Authoritative ops from the owner, applied strictly in version order. The
      // loopback delivers in send order; a gap (duplicate or reordering) is
      // dropped here rather than applied out of order. Matrix's canonical
      // ordering (§6.2) makes gaps a non-issue on the networked transport.
      _deck = applyOp(_deck, op);
      _version = op.version;
      _deckChanges.add(_deck);
    }
  }

  /// Claim the slide [slideId]'s lock (acquire on focus, §5.4).
  Future<void> acquireLock(String slideId) async {
    _ensureLive();
    _locks[slideId] = participantId;
    _lockChanges.add(locks);
    await transport.setLock(slideId, held: true);
  }

  /// Release a lock this session holds (release on blur / slide change).
  Future<void> releaseLock(String slideId) async {
    _ensureLive();
    if (_locks[slideId] == participantId) {
      _locks.remove(slideId);
      _lockChanges.add(locks);
    }
    await transport.setLock(slideId, held: false);
  }

  /// Authority-only: force a slide's lock open regardless of its holder (§5.4).
  /// The losing client learns of it through [lockChanges] — never a silent drop.
  Future<void> forceUnlock(String slideId) async {
    _ensureLive();
    if (!isAuthority) {
      throw StateError('only the session authority may forceUnlock');
    }
    _locks.remove(slideId);
    _lockChanges.add(locks);
    await transport.setLock(slideId, held: false, forced: true);
  }

  void _onRemoteLock(LockEvent event) {
    if (event.held) {
      _locks[event.slideId] = event.participantId;
    } else if (event.forced || _locks[event.slideId] == event.participantId) {
      _locks.remove(event.slideId);
    }
    _lockChanges.add(locks);
  }

  void _ensureLive() {
    if (_disposed) throw StateError('use of a disposed CollabSession');
  }

  /// Tear down subscriptions, streams and the transport. Idempotent.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _opSub.cancel();
    await _lockSub.cancel();
    await _deckChanges.close();
    await _lockChanges.close();
    await transport.dispose();
  }
}
