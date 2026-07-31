import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_codec.dart';
import 'package:ocideck/collab/collab_log_store.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/collab_session_launch.dart';
import 'package:ocideck/collab/collab_snapshot.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/webdav_async_transport.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

// A long interval so the periodic sync never fires mid-test; every test drives
// the async log explicitly and disposes, which cancels the timers.
const _noTick = Duration(hours: 1);

Slide slide(String id, String title) =>
    Slide(id: id, type: SlideType.bullets, title: title);

/// Dispose a launch's coordinator and session (the order the provider uses).
Future<void> _end(CollabLaunch launch) async {
  await launch.coordinator.dispose();
  await launch.session.dispose();
}

void main() {
  group('hostCollabSession', () {
    test('posts a baseline and becomes the authority', () async {
      final store = InMemoryCollabLogStore();
      final deck = Deck(title: 'd', slides: [slide('a', 'one')]);
      final launch = await hostCollabSession(
        store: store,
        deck: deck,
        participantId: 'host',
        pollInterval: _noTick,
      );

      expect(await store.readSnapshot(), isNotNull);
      expect(
        await store.readBeacon(),
        isNotNull,
        reason: 'the host claims a beacon',
      );
      expect(launch.session.isAuthority, isTrue);
      expect(launch.session.deck.slides.single.id, 'a');

      await _end(launch);
    });

    test('resuming an existing session does not reset the baseline', () async {
      final store = InMemoryCollabLogStore();
      // A first host establishes the session and edits it up to version 1.
      final first = await hostCollabSession(
        store: store,
        deck: Deck(title: 'd', slides: [slide('a', 'one')]),
        participantId: 'host-1',
        pollInterval: _noTick,
      );
      await first.session.submit(
        const SetSlideField(
          version: 0,
          authorId: 'host-1',
          slideId: 'a',
          field: SlideField.title,
          value: 'edited',
        ),
      );
      final snapshotBefore = await store.readSnapshot();
      await _end(first);

      // The owner returns (a fresh participant id) and re-hosts. The baseline is
      // adopted, not overwritten, and the resumed session catches up to v1.
      final resumed = await hostCollabSession(
        store: store,
        deck: Deck(title: 'd', slides: [slide('local', 'one')]),
        participantId: 'host-2',
        pollInterval: _noTick,
      );

      expect(
        await store.readSnapshot(),
        snapshotBefore,
        reason: 'baseline kept',
      );
      expect(resumed.session.deck.slides.single.id, 'a');
      expect(resumed.session.deck.slides.single.title, 'edited');
      expect(resumed.session.version, 1, reason: 'caught up on the missed op');

      await _end(resumed);
    });
  });

  group('joinCollabSession', () {
    test('throws when no baseline has been posted', () async {
      final store = InMemoryCollabLogStore();
      expect(
        () => joinCollabSession(
          store: store,
          localDeck: Deck(title: 'd'),
          participantId: 'guest',
          pollInterval: _noTick,
        ),
        throwsStateError,
      );
    });

    test('adopts the authority slide-id space (§5.5)', () async {
      final store = InMemoryCollabLogStore();
      final host = await hostCollabSession(
        store: store,
        deck: Deck(title: 'd', slides: [slide('host-1', 'intro')]),
        participantId: 'host',
        pollInterval: _noTick,
      );

      // The guest opened the same content locally, but its parse gave a
      // different id.
      final guest = await joinCollabSession(
        store: store,
        localDeck: Deck(title: 'd', slides: [slide('guest-9', 'intro')]),
        participantId: 'guest',
        pollInterval: _noTick,
      );

      expect(guest.session.deck.slides.single.id, 'host-1');
      expect(guest.session.isAuthority, isFalse);

      await _end(host);
      await _end(guest);
    });

    test('catches up on ops posted before it joined', () async {
      final store = InMemoryCollabLogStore();
      final host = await hostCollabSession(
        store: store,
        deck: Deck(title: 'd', slides: [slide('a', 'before')]),
        participantId: 'host',
        pollInterval: _noTick,
      );

      // The host edits before anyone joins; the op lands in the log.
      await host.session.submit(
        const SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: 'a',
          field: SlideField.title,
          value: 'after',
        ),
      );
      expect(host.session.deck.slides.single.title, 'after');

      final guest = await joinCollabSession(
        store: store,
        localDeck: Deck(title: 'd', slides: [slide('local', 'before')]),
        participantId: 'guest',
        pollInterval: _noTick,
      );
      await pumpEventQueue();

      // The guest started from the baseline (title "before") and applied the
      // caught-up op, converging on the host's deck.
      expect(guest.session.deck.slides.single.id, 'a');
      expect(guest.session.deck.slides.single.title, 'after');

      await _end(host);
      await _end(guest);
    });

    test('a guest edit round-trips to the host and back', () async {
      final store = InMemoryCollabLogStore();
      final host = await hostCollabSession(
        store: store,
        deck: Deck(title: 'd', slides: [slide('a', 'x')]),
        participantId: 'host',
        pollInterval: _noTick,
      );
      final guest = await joinCollabSession(
        store: store,
        localDeck: Deck(title: 'd', slides: [slide('a', 'x')]),
        participantId: 'guest',
        pollInterval: _noTick,
      );

      // The guest (a follower) submits an edit — it crosses as an intent.
      await guest.session.submit(
        const SetSlideField(
          version: 0,
          authorId: 'guest',
          slideId: 'a',
          field: SlideField.title,
          value: 'edited',
        ),
      );

      // Deliberately reach into the transport to drive the async catch-up
      // deterministically instead of waiting on the timer.
      await _syncAll([host.session, guest.session]);
      expect(host.session.deck.slides.single.title, 'edited');
      await _syncAll([host.session, guest.session]);
      expect(guest.session.deck.slides.single.title, 'edited');

      await _end(host);
      await _end(guest);
    });
  });

  group('joining a re-baselined session (§5.2)', () {
    test(
      'a joiner starts from the latest snapshot and skips old records',
      () async {
        final inner = InMemoryCollabLogStore();
        final store = _CountingStore(inner);

        // A session re-baselined at version 3, seq 3: the baseline deck already
        // reflects three ops, and records 1..3 are the old ops it subsumes.
        final baseDeck = Deck(title: 'd', slides: [slide('a', 'v3')]);
        await store.writeSnapshot(
          jsonEncode(CollabSnapshot.capture(baseDeck, 3, 3).toJson()),
        );
        await store.append(1, 'old-1'); // subsumed — must never be read
        await store.append(2, 'old-2');
        await store.append(3, 'old-3');
        // One fresh op posted after the baseline: version 4 at sequence 4.
        await store.append(
          4,
          jsonEncode({
            'kind': 'op',
            'from': 'host',
            'op': deckOpToJson(
              const SetSlideField(
                version: 4,
                authorId: 'host',
                slideId: 'a',
                field: SlideField.title,
                value: 'v4',
              ),
            ),
          }),
        );

        final guest = await joinCollabSession(
          store: store,
          localDeck: Deck(title: 'd', slides: [slide('local', 'stale')]),
          participantId: 'guest',
          pollInterval: _noTick,
        );
        await pumpEventQueue();

        // Converged from the baseline (v3) + only the fresh op (v4).
        expect(guest.session.version, 4);
        expect(guest.session.deck.slides.single.title, 'v4');
        // The whole point of §5.2: the old records were never fetched.
        expect(store.reads, [
          4,
        ], reason: 'only the record posted after the baseline is read');

        await _end(guest);
      },
    );

    test('a resuming owner starts from the latest re-baselined snapshot', () async {
      final inner = InMemoryCollabLogStore();
      final store = _CountingStore(inner);

      // Re-baselined at version 5 / seq 8 — seq deliberately differs from version
      // (locks bumped the sequence), so swapping version and seq in the resume
      // path would be caught, not silently pass.
      final baseDeck = Deck(title: 'd', slides: [slide('a', 'v5')]);
      await store.writeSnapshot(
        jsonEncode(CollabSnapshot.capture(baseDeck, 5, 8).toJson()),
      );
      for (var s = 1; s <= 8; s++) {
        await store.append(s, 'subsumed-$s'); // must never be read
      }
      await store.append(
        9,
        jsonEncode({
          'kind': 'op',
          'from': 'host',
          'op': deckOpToJson(
            const SetSlideField(
              version: 6,
              authorId: 'host',
              slideId: 'a',
              field: SlideField.title,
              value: 'v6',
            ),
          ),
        }),
      );

      // A returning owner re-hosts; the baseline already exists, so it resumes.
      final resumed = await hostCollabSession(
        store: store,
        deck: Deck(title: 'd', slides: [slide('local', 'stale')]),
        participantId: 'owner-2',
        pollInterval: _noTick,
      );
      await pumpEventQueue();

      // Started at the baseline (version 5) and applied only the fresh op (v6);
      // never replayed versions 1..5.
      expect(resumed.session.version, 6);
      expect(resumed.session.deck.slides.single.title, 'v6');
      expect(
        store.reads,
        [9],
        reason: 'resumed above the baseline seq — the old records are skipped',
      );

      await _end(resumed);
    });
  });
}

/// Poll the underlying transport of every session and flush the streams, so a
/// test can advance the async log without waiting on the poll timer.
Future<void> _syncAll(List<CollabSession> sessions) async {
  for (final s in sessions) {
    await (s.transport as WebdavAsyncTransport).poll();
  }
  await pumpEventQueue();
}

/// An in-memory store that records which sequence numbers were actually
/// downloaded, so a test can prove a joiner never replayed the old log.
class _CountingStore implements CollabLogStore {
  _CountingStore(this._inner);
  final CollabLogStore _inner;
  final List<int> reads = [];

  @override
  Future<String> read(int seq) {
    reads.add(seq);
    return _inner.read(seq);
  }

  @override
  Future<List<int>> listSequences() => _inner.listSequences();
  @override
  Future<bool> append(int seq, String record) => _inner.append(seq, record);
  @override
  Future<void> delete(int seq) => _inner.delete(seq);
  @override
  Future<String?> readSnapshot() => _inner.readSnapshot();
  @override
  Future<void> writeSnapshot(String snapshot) => _inner.writeSnapshot(snapshot);
  @override
  Future<String?> readBeacon() => _inner.readBeacon();
  @override
  Future<void> writeBeacon(String beacon) => _inner.writeBeacon(beacon);
}
