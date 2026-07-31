// The async collaboration transport (`docs/design/COLLABORATION.md` §10, Fase
// 0.5): asynchronous co-authoring over the Nextcloud/WebDAV a user already
// configured, with no new dependency, no AGPL and no Rust — the recommended
// step while real-time Matrix stays parked (assurance/ketenkeuring-matrix-*.md,
// #976/#991).
//
// It implements the same [CollabTransport] pipe as `LoopbackTransport`, so the
// authority/versioning/lock logic in `collab_session.dart` drives it unchanged.
// The difference from the loopback is that this transport is *durable and
// asynchronous*: sends are appended to a numbered log on the WebDAV source
// ([CollabLogStore]) and arrivals are discovered by polling, so a participant
// who was offline catches up on the missed records the next time it polls —
// the "no missed-event buffering" caveat of the loopback (§6.2) is exactly what
// the log removes here.
//
// Two decisions worth stating:
//   • **Ordering is the sequence number.** Records are delivered strictly in
//     ascending sequence, and the poll stops at the first gap rather than
//     delivering out of order, because [CollabSession] applies authoritative
//     ops in `version` order and drops anything out of sequence (§5.3).
//   • **A participant never hears its own sends** (the [CollabTransport]
//     contract). Each record is tagged with the writer's [participantId]; the
//     poll skips the writer's own records, and remembers the sequence numbers
//     it wrote so it need not even fetch them back.
//
// The transport is written against [CollabLogStore], not WebDAV, so tests drive
// it with an in-memory store; [WebdavCollabLogStore] is the production binding.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import '../utils/log.dart';
import 'collab_codec.dart';
import 'collab_log_store.dart';
import 'collab_transport.dart';
import 'deck_op.dart';

/// A [CollabTransport] over an append-only log on the WebDAV source. Construct
/// one per participant against a [store] shared by the session (the same store
/// path is what makes them one session). Call [poll] to sync now, or let the
/// periodic timer do it; [start] begins the timer.
class WebdavAsyncTransport implements CollabTransport {
  WebdavAsyncTransport({
    required this.store,
    required this.participantId,
    this.pollInterval = const Duration(seconds: 5),
    int initialSeq = 0,
  }) : _lastSeq = initialSeq,
       _knownMaxSeq = initialSeq;

  final CollabLogStore store;

  @override
  final String participantId;

  /// How often the periodic sync runs once [start] is called. Async, not
  /// real-time: a few seconds is the intended cadence, not milliseconds.
  final Duration pollInterval;

  final _ops = StreamController<DeckOp>.broadcast();
  final _locks = StreamController<LockEvent>.broadcast();

  /// The highest sequence number delivered (or skipped) in strict order. The
  /// next poll resumes at `_lastSeq + 1`. Starts at the constructor's
  /// `initialSeq` — non-zero when a joiner begins from a re-baselined snapshot
  /// (§5.2) and so must skip the records that snapshot already subsumes.
  int _lastSeq;

  /// The highest sequence number seen at all, used to pick where to append.
  int _knownMaxSeq;

  /// Sequence numbers this transport wrote, so the poll skips fetching them back
  /// only to discard its own sends.
  final Set<int> _ownSeqs = {};

  Timer? _timer;
  bool _polling = false;
  bool _disposed = false;

  // Serialises this transport's own appends so it picks sequence numbers one at
  // a time instead of racing itself when sendOp/setLock overlap.
  Future<void> _appendChain = Future<void>.value();

  @override
  Stream<DeckOp> get ops => _ops.stream;

  @override
  Stream<LockEvent> get locks => _locks.stream;

  /// True when the last [poll] left no records unseen: every present sequence up
  /// to the highest known one has been delivered (or skipped as this
  /// participant's own). The [HandoverCoordinator] gates a takeover on this so a
  /// successor only assigns versions once its [CollabSession.version] is the
  /// highest anyone holds — resumed versions then cannot collide (§5.3).
  ///
  /// It reflects only what the *last* listing showed. WebDAV gives no
  /// cross-client read-your-writes, so a record another participant just appended
  /// may not be listed yet; the coordinator therefore also requires the known
  /// maximum to hold *steady* across several polls before claiming, not just this
  /// flag once. WebDAV-specific on purpose — it means nothing for the loopback or
  /// a future Matrix transport, so it stays off [CollabTransport].
  bool get isCaughtUp => _lastSeq >= _knownMaxSeq;

  /// The highest sequence number any poll has seen present. The coordinator
  /// watches this for the steadiness the previous getter describes.
  int get knownMaxSeq => _knownMaxSeq;

  /// The highest sequence number processed in strict order — everything at or
  /// below it has been delivered (or was this participant's own send). The
  /// authority stamps this into a re-baselined snapshot (§5.2) so a later joiner
  /// resumes just above it.
  int get lastSeq => _lastSeq;

  /// Begin polling on [pollInterval]. Idempotent; a no-op after [dispose].
  void start() {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(pollInterval, (_) => poll());
  }

  @override
  Future<void> sendOp(DeckOp op) {
    _ensureLive();
    return _appendRecord({
      'kind': 'op',
      'from': participantId,
      'op': deckOpToJson(op),
    });
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
    return _appendRecord({
      'kind': 'lock',
      'from': participantId,
      'lock': lockEventToJson(event),
    });
  }

  /// Read any records appended since the last sync and deliver the ones written
  /// by other participants, strictly in sequence order. Safe to call directly
  /// ("sync now") or from the timer; overlapping calls are collapsed.
  Future<void> poll() async {
    if (_disposed || _polling) return;
    _polling = true;
    try {
      final present = (await store.listSequences()).toSet();
      if (present.isNotEmpty) {
        _knownMaxSeq = math.max(_knownMaxSeq, present.reduce(math.max));
      }
      var seq = _lastSeq + 1;
      while (present.contains(seq)) {
        if (_disposed) return;
        if (!_ownSeqs.contains(seq)) {
          // A store failure here (network) propagates and leaves _lastSeq put,
          // so the record is retried next poll rather than skipped.
          final record = await store.read(seq);
          _dispatch(seq, record);
        }
        _lastSeq = seq;
        seq++;
      }
    } catch (e) {
      // Transient WebDAV trouble: keep _lastSeq where it is and try next tick.
      logWarning('collab.webdav.poll', e);
    } finally {
      _polling = false;
    }
  }

  void _dispatch(int seq, String record) {
    // A single malformed record must not wedge the whole log: decode it in
    // isolation, and on failure skip it (the outer loop still advances) rather
    // than retrying a poison record forever. Well-formed writers never produce
    // one; this only fires on corruption or a record kind from a newer version.
    try {
      final env = jsonDecode(record);
      if (env is! Map<String, Object?>) {
        throw FormatException('log record is not an object');
      }
      if (env['from'] == participantId) return; // own send (belt-and-braces)
      switch (env['kind']) {
        case 'op':
          _ops.add(deckOpFromJson(_asObject(env['op'])));
        case 'lock':
          _locks.add(lockEventFromJson(_asObject(env['lock'])));
        default:
          // An unknown kind (a future record type) is skipped, not fatal.
          break;
      }
    } catch (e) {
      logWarning('collab.webdav.record.$seq', e);
    }
  }

  Future<void> _appendRecord(Map<String, Object?> envelope) {
    final record = jsonEncode(envelope);
    final done = _appendChain.then((_) => _appendWithRetry(record));
    // Keep the chain alive even if this append failed, so a later send is not
    // permanently blocked by an earlier error.
    _appendChain = done.then((_) {}, onError: (_) {});
    return done;
  }

  Future<void> _appendWithRetry(String record) async {
    var seq = _knownMaxSeq + 1;
    while (true) {
      _ensureLive();
      if (await store.append(seq, record)) {
        _ownSeqs.add(seq);
        _knownMaxSeq = math.max(_knownMaxSeq, seq);
        return;
      }
      // Someone else took this slot; refresh the high-water mark and retry
      // above it. Each miss strictly raises seq, so this terminates.
      final present = await store.listSequences();
      _knownMaxSeq = present.isEmpty ? 0 : present.reduce(math.max);
      seq = _knownMaxSeq + 1;
    }
  }

  Map<String, Object?> _asObject(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return value.map((k, v) => MapEntry(k.toString(), v));
    throw FormatException('expected an object, got ${value.runtimeType}');
  }

  void _ensureLive() {
    if (_disposed) {
      throw StateError('use of a disposed WebdavAsyncTransport');
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
