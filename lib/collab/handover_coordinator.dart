// Owner-drop authority handover (`docs/design/COLLABORATION.md` §5.3) — the
// *policy* over the async WebDAV transport. [CollabSession] is the *mechanism*: it
// can be told to become or step down from the authority, but it decides nothing.
// This decides *when* to flip that role, from a beacon in the sidecar — because
// that decision needs the store and the poll cadence, which have no place in the
// pure session loop or the dumb transport pipe (§5.6). Being the authority's
// periodic driver, it also owns §5.2 **re-baselining**: every `rebaseEveryOps`
// op versions it publishes a fresh snapshot so a later joiner never replays the
// whole op log (see [_maybeRebaseline]).
//
// WebDAV-specific on purpose. It reads `transport.isCaughtUp` / `knownMaxSeq` —
// notions the loopback and a future Matrix transport do not share — so it is not
// written against the neutral [CollabTransport]. Keeping the mechanism neutral is
// exactly what lets the Matrix step (which brings real presence, §6.2) throw this
// coordinator away without touching [CollabSession].
//
// ## The beacon
// A last-write-wins blob beside the numbered log: `{authority, authorityIsOwner,
// tick}`. The current authority bumps `tick` every poll; a frozen tick is how a
// successor infers the authority dropped, since Fase 0.5 has no presence. The
// beacon is **advisory** — WebDAV write access is the only real gate on the
// sidecar, so a lying beacon can misdirect *version assignment* but never grants
// *persistence*: only the owner persists, and [isOwner] is a launch-role fact read
// by the provider's save path, never derived from the beacon.
//
// ## One atomic cycle
// [syncNow] runs `transport.poll()` then [_decide], in that fixed order, and the
// coordinator owns the poll timer (the transport's own timer is left unstarted).
// `isCaughtUp` is only meaningful straight after a poll, so binding the two into
// one step is what makes every transition reproducible by counting `syncNow()`s
// with no wall-clock — the seam the tests drive.
//
// ## Fail-closed
// On any uncertainty — a malformed or absent beacon, a store read that throws, a
// beacon write that fails — this never takes authority. A stalled session the
// owner can revive beats a split brain (§5.3). Concretely: authority is claimed
// *only after* the beacon write confirms (never before), and an incumbent whose
// heartbeat write keeps failing steps down rather than commit where no one can see
// it is the authority.
//
// ## Why a successor does not corrupt the version stream
// A successor resumes version assignment from its own [CollabSession.version], so
// it must already hold the highest version anyone has or a resumed version
// collides. Two guards gate a takeover:
//   • **caught up** — the last poll left no record unseen; and
//   • **sequence-steady** — the highest known sequence has not moved for a few
//     polls. This exists because WebDAV gives no cross-client read-your-writes: a
//     record the departing authority already wrote may not be listed yet.
//     Requiring the maximum to hold steady (alongside a frozen tick) makes an
//     unseen in-flight record unlikely before the successor resumes the sequence.
// The hand-back path (a returning owner reclaiming a *live* guest) requires only
// "caught up" — a live guest keeps appending, so demanding steadiness would stop
// the owner from ever taking back control; the brief version overlap that admits
// is the documented failover residual (§5.3).

import 'dart:async';
import 'dart:convert';

import '../utils/log.dart';
import 'collab_session.dart';
import 'collab_snapshot.dart';
import 'webdav_async_transport.dart';

/// Drives owner-drop authority handover for one [CollabSession] over a
/// [WebdavAsyncTransport]. Construct one per session after launch; the launch
/// helper owns it and disposes it with the session.
class HandoverCoordinator {
  HandoverCoordinator({
    required this.session,
    required this.transport,
    required this.isOwner,
    this.staleThreshold = 3,
    this.seqSteadyThreshold = 2,
    this.heartbeatFailThreshold = 3,
    this.claimSpread = 8,
    this.rebaseEveryOps = 100,
  });

  final CollabSession session;
  final WebdavAsyncTransport transport;

  /// Whether this participant launched as the deck's owner (host). A launch fact,
  /// never a beacon derivation: only the owner persists, and only the owner
  /// reclaims authority from a temporary stand-in. A guest is never the owner —
  /// it can be a *temporary* authority (keeping the session alive) but must not
  /// persist (§5.3).
  final bool isOwner;

  /// Polls a beacon tick may stay frozen before the authority is presumed gone.
  final int staleThreshold;

  /// Polls the highest known sequence must hold steady before a successor claims
  /// (the WebDAV list-lag guard).
  final int seqSteadyThreshold;

  /// Consecutive failed beacon writes before an incumbent authority steps down.
  final int heartbeatFailThreshold;

  /// Range of the deterministic per-participant claim backoff. Successors stagger
  /// their claims by `hash(participantId) % claimSpread` extra polls so the
  /// designated successor claims first; if it is also gone, the next one's longer
  /// wait fires (liveness), all without a roster (there is no presence to build
  /// one from).
  final int claimSpread;

  /// How many op versions the authority lets pass before publishing a fresh
  /// baseline (§5.2). Threshold-driven in ops — no wall-clock — so a joiner never
  /// replays more than roughly this many ops. Smaller = cheaper joins but more
  /// snapshot writes; larger = the reverse.
  final int rebaseEveryOps;

  String get participantId => session.participantId;

  Timer? _timer;
  bool _disposed = false;
  bool _syncing = false;

  // Staleness of the observed authority, counted in polls (no wall-clock).
  int? _lastTick;
  int _stalePolls = 0;

  // Steadiness of the log's high-water mark, likewise in polls.
  int _lastKnownMaxSeq = -1;
  int _seqSteadyPolls = 0;

  // Consecutive failed heartbeat writes while this session is the authority.
  int _heartbeatFailures = 0;

  // The op version at the last baseline this session published (§5.2 re-baseline).
  int _lastRebaseVersion = 0;

  // The authority this coordinator last observed, to fire [authorityChanged].
  String? _lastAuthority;

  final _authorityChanged = StreamController<void>.broadcast();

  /// Emits whenever the observed authority (the beacon's `authority`) changes.
  /// Every participant re-submits its un-echoed local edits on this so intents
  /// lost to a dropped authority are re-driven to the new one (§5.3) — not just
  /// the successor's own edits, but any follower's.
  Stream<void> get authorityChanged => _authorityChanged.stream;

  /// Begin the poll+decide loop on [transport]'s poll interval. Idempotent; a
  /// no-op after [dispose]. The transport's own [WebdavAsyncTransport.start] must
  /// *not* also be running — this loop is the single cadence, so `isCaughtUp` is
  /// always read straight after the poll that set it.
  void start({Duration? interval}) {
    if (_disposed || _timer != null) return;
    _timer = Timer.periodic(
      interval ?? transport.pollInterval,
      (_) => syncNow(),
    );
  }

  /// One atomic cycle: sync the log, then re-decide the authority role, in that
  /// fixed order. Safe to call directly to advance one logical "tick" in tests.
  /// Overlapping calls (the timer firing again before a slow WebDAV cycle
  /// finished) are dropped, so the poll-counters advance exactly once per
  /// completed cycle — the whole decision, not just the poll, stays atomic.
  Future<void> syncNow() async {
    if (_disposed || _syncing) return;
    _syncing = true;
    try {
      await transport.poll();
      if (_disposed) return;
      await _decide();
    } finally {
      _syncing = false;
    }
  }

  Future<void> _decide() async {
    final _Beacon? beacon;
    try {
      final raw = await transport.store.readBeacon();
      beacon = raw == null ? null : _Beacon.tryParse(raw);
    } catch (e) {
      // A store read that threw: treat as unknown and change nothing. Never claim
      // on uncertainty (fail-closed).
      logWarning('collab.handover.readBeacon', e);
      return;
    }
    // No beacon (a session predating handover) or a malformed one: do not
    // interpret it. Malformed == absent == no-op; the role stays as launched.
    if (beacon == null) return;

    _observeAuthorityChange(beacon.authority);
    _updateStaleness(beacon.tick);
    _updateSeqSteadiness();

    if (_wantsAuthority(beacon)) {
      await _claimOrHeartbeat(beacon);
    } else if (session.isAuthority) {
      // We hold an authority the beacon no longer endorses (a returning owner, a
      // higher-priority peer took over): relinquish. Stepping down never causes a
      // split brain, so no guard is needed here.
      session.stepDown();
      _heartbeatFailures = 0;
    }
  }

  bool _wantsAuthority(_Beacon beacon) {
    if (beacon.authority == participantId) return true; // I hold it; heartbeat.

    final fresh = _stalePolls < staleThreshold;
    if (fresh) {
      // A live authority holds it. Only the owner reclaims — and only from a
      // *guest* stand-in (hand-back); everyone else defers. Caught-up is enough
      // here: a live guest keeps appending, so requiring a steady sequence would
      // stop the owner from ever taking back control.
      return isOwner && !beacon.authorityIsOwner && transport.isCaughtUp;
    }

    // The tick is frozen — the authority is presumed gone. The sequence will now
    // settle, so require it steady (the list-lag guard) as well as caught up, then
    // wait out this participant's deterministic backoff so successors do not all
    // claim at once.
    return transport.isCaughtUp &&
        _seqSteadyPolls >= seqSteadyThreshold &&
        _stalePolls >= staleThreshold + _claimBackoff();
  }

  Future<void> _claimOrHeartbeat(_Beacon beacon) async {
    // Write the beacon FIRST; act as authority only once the claim is durable. A
    // failed write must never leave a phantom local authority (fail-closed).
    final nextTick = (_lastTick ?? beacon.tick) + 1;
    final next = _Beacon(
      authority: participantId,
      authorityIsOwner: isOwner,
      tick: nextTick,
    );
    try {
      await transport.store.writeBeacon(next.encode());
    } catch (e) {
      logWarning('collab.handover.writeBeacon', e);
      _heartbeatFailures++;
      if (session.isAuthority && _heartbeatFailures >= heartbeatFailThreshold) {
        // An incumbent that can no longer publish its liveness stops assigning
        // versions rather than committing where no one sees it is the authority.
        session.stepDown();
      }
      return; // Did not become / stay authority on this cycle.
    }
    // The claim is durable: take (or keep) authority and reset the counters so we
    // read our own fresh tick next cycle.
    _heartbeatFailures = 0;
    _lastTick = nextTick;
    _stalePolls = 0;
    session.becomeAuthority();
    await _maybeRebaseline();
  }

  /// Publish a fresh baseline once enough op versions have passed since the last
  /// one (§5.2), so a later joiner starts from it and never replays the whole op
  /// log. Any authority does this — it writes the sidecar snapshot, not the `.md`,
  /// so it is not the "persist" a temporary authority must avoid (§5.3). The seq
  /// stamped in is the transport's `lastSeq` (the highest record processed); the
  /// deck at `session.version` reflects everything up to it. It is fine if that
  /// seq lags the version's own record slightly — a joiner starting there just
  /// re-reads a few records and drops them at the version gate, since it applies
  /// only versions above `session.version`. seq is a fetch hint, not a
  /// correctness input.
  Future<void> _maybeRebaseline() async {
    if (session.version - _lastRebaseVersion < rebaseEveryOps) return;
    final snapshot = CollabSnapshot.capture(
      session.deck,
      session.version,
      transport.lastSeq,
    );
    try {
      await transport.store.writeSnapshot(jsonEncode(snapshot.toJson()));
      _lastRebaseVersion = session.version;
    } catch (e) {
      // A failed snapshot write is not fatal: the previous baseline still serves
      // joiners, and the next threshold crossing retries. Leave _lastRebaseVersion
      // where it is so the retry happens.
      logWarning('collab.handover.rebaseline', e);
    }
  }

  void _observeAuthorityChange(String authority) {
    if (_lastAuthority != null &&
        _lastAuthority != authority &&
        !_authorityChanged.isClosed) {
      _authorityChanged.add(null);
    }
    _lastAuthority = authority;
  }

  void _updateStaleness(int tick) {
    if (_lastTick == null || tick > _lastTick!) {
      _lastTick = tick;
      _stalePolls = 0;
    } else {
      // Tick unchanged (or a lower stale read): the authority has not advanced.
      _stalePolls++;
    }
  }

  void _updateSeqSteadiness() {
    final maxSeq = transport.knownMaxSeq;
    if (maxSeq != _lastKnownMaxSeq) {
      _lastKnownMaxSeq = maxSeq;
      _seqSteadyPolls = 0;
    } else {
      _seqSteadyPolls++;
    }
  }

  int _claimBackoff() => _stableHash(participantId) % claimSpread;

  /// A stable string hash — deliberately not [String.hashCode], which is seeded
  /// per run, so the successor order would differ between processes. This one is
  /// the same everywhere, which is what makes the "fixed order breaks ties" of
  /// §5.3 deterministic across participants.
  static int _stableHash(String s) {
    var h = 0;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }

  /// Stop the loop and release resources. Idempotent. Does not dispose the
  /// session — the launch helper's owner does that.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    await _authorityChanged.close();
  }
}

/// The parsed beacon. A top-level helper (not nested) so the coordinator class
/// stays a single responsibility; kept private to this library.
class _Beacon {
  const _Beacon({
    required this.authority,
    required this.authorityIsOwner,
    required this.tick,
  });

  /// The participant id currently assigning versions.
  final String authority;

  /// Whether that authority launched as the owner. A *coordination* label
  /// (owners reclaim from guests), never an *authorisation* — persistence is
  /// gated on the local launch role, not on this field.
  final bool authorityIsOwner;

  /// The liveness counter the authority bumps each poll.
  final int tick;

  String encode() => jsonEncode({
    'authority': authority,
    'authorityIsOwner': authorityIsOwner,
    'tick': tick,
  });

  /// Fail-closed decode: a beacon of the wrong shape returns `null`, and a
  /// syntactically invalid blob throws a [FormatException] from [jsonDecode].
  /// [HandoverCoordinator._decide] wraps this call and treats both the same — a
  /// no-op that never claims. That single fail-closed boundary lives in the
  /// caller, so there is no swallow-everything catch here.
  static _Beacon? tryParse(String raw) {
    final v = jsonDecode(raw);
    if (v is! Map) return null;
    final authority = v['authority'];
    final owner = v['authorityIsOwner'];
    final tick = v['tick'];
    if (authority is! String || owner is! bool || tick is! int) return null;
    return _Beacon(authority: authority, authorityIsOwner: owner, tick: tick);
  }
}
