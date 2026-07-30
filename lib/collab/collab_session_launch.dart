// Assembling a live async collaboration session from the building blocks
// (`docs/design/COLLABORATION.md` §6.5 lifecycle, over the Fase 0.5 transport).
// The snapshot (§5.2), the transport (§10) and the session authority (§5.3) each
// stand alone and are tested alone; this is the thin seam that wires them into
// "start a session" / "join a session" so a caller — a provider, a menu action —
// does not have to know their internal order.
//
// Store-generic on purpose: both functions take a [CollabLogStore], so they run
// end-to-end in tests over [InMemoryCollabLogStore] and in production over
// [WebdavCollabLogStore]. The WebDAV-ness is entirely in which store the caller
// passes; nothing here talks to a network.
//
// v1 scope: the host is the authority and the joiner is a follower for the whole
// session (owner-drop handover is §5.3, a follow-up), and the baseline is taken
// at session start (version 0). Periodic re-baselining at a non-zero version
// (§5.2) needs the session to accept a starting version and is also a follow-up.

import 'dart:convert';

import '../models/deck.dart';
import 'collab_log_store.dart';
import 'collab_session.dart';
import 'collab_snapshot.dart';
import 'webdav_async_transport.dart';

/// Host a new session for [deck] over [store]: post the baseline others join
/// from, become the authority, and begin polling. The returned [CollabSession]
/// owns its transport; dispose it to end the session locally.
Future<CollabSession> hostCollabSession({
  required CollabLogStore store,
  required Deck deck,
  required String participantId,
  Duration pollInterval = const Duration(seconds: 5),
}) async {
  // Publish the baseline before anyone can join, so a joiner never sees ops
  // without the snapshot they are relative to.
  await store.writeSnapshot(
    jsonEncode(CollabSnapshot.capture(deck, 0).toJson()),
  );
  final transport = WebdavAsyncTransport(
    store: store,
    participantId: participantId,
    pollInterval: pollInterval,
  );
  final session = CollabSession(
    initialDeck: deck,
    transport: transport,
    isAuthority: true,
  );
  transport.start();
  return session;
}

/// Join the session on [store] as a follower. Reads the baseline, rebases
/// [localDeck] onto the authority's slides (adopting their ids, §5.5), catches
/// up on ops posted since, and begins polling. Throws [StateError] if no host
/// has posted a baseline yet.
Future<CollabSession> joinCollabSession({
  required CollabLogStore store,
  required Deck localDeck,
  required String participantId,
  Duration pollInterval = const Duration(seconds: 5),
}) async {
  final raw = await store.readSnapshot();
  if (raw == null) {
    throw StateError('no collaboration baseline in this sidecar yet');
  }
  final decoded = jsonDecode(raw);
  if (decoded is! Map<String, Object?>) {
    throw FormatException('baseline is not a JSON object');
  }
  final baseDeck = CollabSnapshot.fromJson(decoded).applyTo(localDeck);
  final transport = WebdavAsyncTransport(
    store: store,
    participantId: participantId,
    pollInterval: pollInterval,
  );
  final session = CollabSession(
    initialDeck: baseDeck,
    transport: transport,
    isAuthority: false,
  );
  transport.start();
  // One eager sync so the joiner reflects work done before it arrived, rather
  // than waiting a whole poll interval to catch up.
  await transport.poll();
  return session;
}
