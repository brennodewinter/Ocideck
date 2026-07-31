// Assembling a live async collaboration session from the building blocks
// (`docs/design/COLLABORATION.md` §6.5 lifecycle, over the Fase 0.5 transport).
// The snapshot (§5.2), the transport (§10), the session authority (§5.3) and the
// handover coordinator (§5.3) each stand alone and are tested alone; this is the
// thin seam that wires them into "start a session" / "join a session" so a caller
// — a provider, a menu action — does not have to know their internal order.
//
// Store-generic on purpose: both functions take a [CollabLogStore], so they run
// end-to-end in tests over [InMemoryCollabLogStore] and in production over
// [WebdavCollabLogStore]. The WebDAV-ness is entirely in which store the caller
// passes; nothing here talks to a network.
//
// Owner-drop handover (§5.3) is wired here: the host writes an authority beacon,
// every session gets a [HandoverCoordinator] that drives the poll+decide loop, and
// the coordinator — not the transport's own timer — owns the poll cadence, so
// `isCaughtUp` is always read straight after its poll.
//
// Snapshot re-baselining (§5.2) is wired here too: a joiner (and a resuming owner)
// reads the *latest* baseline and starts its session and transport at that
// baseline's version and sequence, so it fetches only the records posted since —
// never the whole op log. The authority refreshes that baseline periodically from
// inside the coordinator. A fresh session's first baseline is at version 0, seq 0.
//
// A returning owner re-hosts: [hostCollabSession] is resume-aware. If a baseline
// already exists the host does not reset it — it adopts it, catches up on the ops
// posted while it was gone, and its coordinator reclaims authority from whatever
// stand-in was keeping the session alive (the hand-back of §5.3).

import 'dart:convert';

import '../models/deck.dart';
import 'collab_log_store.dart';
import 'collab_session.dart';
import 'collab_snapshot.dart';
import 'handover_coordinator.dart';
import 'webdav_async_transport.dart';

/// A launched session and the coordinator that keeps its authority live. The
/// caller owns both: dispose the [coordinator] and then the [session] to end the
/// session locally (the provider does this in its teardown).
class CollabLaunch {
  const CollabLaunch({required this.session, required this.coordinator});

  final CollabSession session;
  final HandoverCoordinator coordinator;
}

/// Host a session others can join, or resume ownership of one already in progress.
///
/// Fresh (no baseline yet): publish the baseline others join from, become the
/// authority, and write the initial beacon. Resuming (a baseline exists — the
/// owner is returning after a drop): adopt the existing baseline, start as a
/// follower, and let the coordinator reclaim authority once caught up (§5.3
/// hand-back). Either way the returned coordinator owns the poll loop.
Future<CollabLaunch> hostCollabSession({
  required CollabLogStore store,
  required Deck deck,
  required String participantId,
  Duration pollInterval = const Duration(seconds: 5),
}) async {
  // All the store I/O that can throw runs *before* any transport, session or
  // coordinator exists, so a WebDAV failure mid-launch cannot leak a half-built
  // session whose stream subscriptions no one disposes.
  final existing = await store.readSnapshot();
  final Deck baseDeck;
  final bool startAsAuthority;
  final int initialVersion;
  final int initialSeq;
  if (existing == null) {
    // Fresh session: publish the baseline before anyone can join (so a joiner
    // never sees ops without the snapshot they are relative to) and claim the
    // authority beacon, then start as the authority at version 0.
    await store.writeSnapshot(
      jsonEncode(CollabSnapshot.capture(deck, 0, 0).toJson()),
    );
    await store.writeBeacon(
      _initialBeacon(authority: participantId).encodeInitial(),
    );
    baseDeck = deck;
    startAsAuthority = true;
    initialVersion = 0;
    initialSeq = 0;
  } else {
    // Resuming ownership: adopt the existing baseline's slide-id space (§5.5) and
    // start as a follower *at the baseline's version and sequence* (§5.2), so the
    // owner resumes from the latest re-baseline instead of replaying from zero.
    // The coordinator reclaims authority after catching up.
    final snapshot = _snapshotFrom(existing);
    baseDeck = snapshot.applyTo(deck);
    startAsAuthority = false;
    initialVersion = snapshot.version;
    initialSeq = snapshot.seq;
  }
  final transport = WebdavAsyncTransport(
    store: store,
    participantId: participantId,
    pollInterval: pollInterval,
    initialSeq: initialSeq,
  );
  final session = CollabSession(
    initialDeck: baseDeck,
    transport: transport,
    isAuthority: startAsAuthority,
    initialVersion: initialVersion,
  );
  final coordinator = HandoverCoordinator(
    session: session,
    transport: transport,
    isOwner: true,
  );
  coordinator.start();
  // One eager cycle: heartbeat the fresh beacon, or (when resuming) catch up on
  // the missed ops and reclaim authority. It swallows its own I/O errors, so it
  // cannot throw past this point and strand the session.
  await coordinator.syncNow();
  return CollabLaunch(session: session, coordinator: coordinator);
}

/// Join the session on [store] as a follower. Reads the baseline, rebases [deck]
/// onto the authority's slides (adopting their ids, §5.5), catches up on ops
/// posted since, and begins the poll loop. Throws [StateError] if no host has
/// posted a baseline yet. A guest is never the owner: its coordinator can make it
/// a *temporary* authority if the owner drops, but it never persists (§5.3).
Future<CollabLaunch> joinCollabSession({
  required CollabLogStore store,
  required Deck localDeck,
  required String participantId,
  Duration pollInterval = const Duration(seconds: 5),
}) async {
  final raw = await store.readSnapshot();
  if (raw == null) {
    throw StateError('no collaboration baseline in this sidecar yet');
  }
  // Start from the latest baseline's version and sequence (§5.2): the transport
  // resumes just above the snapshot's seq, so the joiner fetches only the records
  // posted since — never the whole op log.
  final snapshot = _snapshotFrom(raw);
  final baseDeck = snapshot.applyTo(localDeck);
  final transport = WebdavAsyncTransport(
    store: store,
    participantId: participantId,
    pollInterval: pollInterval,
    initialSeq: snapshot.seq,
  );
  final session = CollabSession(
    initialDeck: baseDeck,
    transport: transport,
    isAuthority: false,
    initialVersion: snapshot.version,
  );
  final coordinator = HandoverCoordinator(
    session: session,
    transport: transport,
    isOwner: false,
  );
  coordinator.start();
  // One eager cycle so the joiner reflects work done before it arrived (and reads
  // the current authority) rather than waiting a whole poll interval.
  await coordinator.syncNow();
  return CollabLaunch(session: session, coordinator: coordinator);
}

CollabSnapshot _snapshotFrom(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('baseline is not a JSON object');
  }
  return CollabSnapshot.fromJson(decoded);
}

_InitialBeacon _initialBeacon({required String authority}) =>
    _InitialBeacon(authority);

/// The host's opening beacon. A tiny top-level helper so the launch functions do
/// not reach into the coordinator's private [beacon] shape; the wire form matches
/// what [HandoverCoordinator] reads.
class _InitialBeacon {
  const _InitialBeacon(this.authority);
  final String authority;

  String encodeInitial() =>
      jsonEncode({'authority': authority, 'authorityIsOwner': true, 'tick': 1});
}
