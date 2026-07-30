import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_log_store.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/collab_session_launch.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/webdav_async_transport.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

// A long interval so the periodic sync never fires mid-test; every test polls
// explicitly (join does) and disposes, which cancels the timer.
const _noTick = Duration(hours: 1);

Slide slide(String id, String title) =>
    Slide(id: id, type: SlideType.bullets, title: title);

void main() {
  group('hostCollabSession', () {
    test('posts a baseline and becomes the authority', () async {
      final store = InMemoryCollabLogStore();
      final deck = Deck(title: 'd', slides: [slide('a', 'one')]);
      final session = await hostCollabSession(
        store: store,
        deck: deck,
        participantId: 'host',
        pollInterval: _noTick,
      );

      expect(await store.readSnapshot(), isNotNull);
      expect(session.isAuthority, isTrue);
      expect(session.deck.slides.single.id, 'a');

      await session.dispose();
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

      expect(guest.deck.slides.single.id, 'host-1');
      expect(guest.isAuthority, isFalse);

      await host.dispose();
      await guest.dispose();
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
      await host.submit(
        const SetSlideField(
          version: 0,
          authorId: 'host',
          slideId: 'a',
          field: SlideField.title,
          value: 'after',
        ),
      );
      expect(host.deck.slides.single.title, 'after');

      final guest = await joinCollabSession(
        store: store,
        localDeck: Deck(title: 'd', slides: [slide('local', 'before')]),
        participantId: 'guest',
        pollInterval: _noTick,
      );
      await pumpEventQueue();

      // The guest started from the baseline (title "before") and applied the
      // caught-up op, converging on the host's deck.
      expect(guest.deck.slides.single.id, 'a');
      expect(guest.deck.slides.single.title, 'after');

      await host.dispose();
      await guest.dispose();
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
      await guest.submit(
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
      await _syncAll([host, guest]);
      expect(host.deck.slides.single.title, 'edited');
      await _syncAll([host, guest]);
      expect(guest.deck.slides.single.title, 'edited');

      await host.dispose();
      await guest.dispose();
    });
  });
}

/// Poll the underlying transport of every session and flush the streams, so a
/// test can advance the async log without waiting on the poll timer. The
/// sessions were built by the launch helpers over a shared store; their
/// transports pick up each other's records on poll.
Future<void> _syncAll(List<CollabSession> sessions) async {
  for (final s in sessions) {
    await (s.transport as WebdavAsyncTransport).poll();
  }
  await pumpEventQueue();
}
