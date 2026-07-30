import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_log_store.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/collab_transport.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/collab/webdav_async_transport.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

/// A distinguishable op — RemoveSlide carries only a slide id, so a list of them
/// reads as an ordered sequence in the assertions.
RemoveSlide remove(String id, {int version = 1, String author = 'A'}) =>
    RemoveSlide(version: version, authorId: author, slideId: id);

void main() {
  group('InMemoryCollabLogStore contract', () {
    test(
      'first writer wins a sequence number, the second is told no',
      () async {
        final store = InMemoryCollabLogStore();
        expect(await store.append(1, 'a'), isTrue);
        expect(await store.append(1, 'b'), isFalse);
        expect(await store.read(1), 'a');
        expect(await store.append(2, 'b'), isTrue);
        expect(await store.listSequences(), [1, 2]);
      },
    );

    test('reading an empty slot throws', () async {
      final store = InMemoryCollabLogStore();
      expect(() => store.read(7), throwsStateError);
    });
  });

  group('WebdavAsyncTransport over a shared log', () {
    test('a poll delivers others sends but never the senders own', () async {
      final store = InMemoryCollabLogStore();
      final a = WebdavAsyncTransport(store: store, participantId: 'A');
      final b = WebdavAsyncTransport(store: store, participantId: 'B');
      final aOps = <DeckOp>[];
      final bOps = <DeckOp>[];
      a.ops.listen(aOps.add);
      b.ops.listen(bOps.add);

      await a.sendOp(remove('x'));
      await a.poll();
      await b.poll();
      await pumpEventQueue();

      expect(aOps, isEmpty, reason: 'a sender must not hear its own op');
      expect(bOps, hasLength(1));
      expect((bOps.single as RemoveSlide).slideId, 'x');

      await a.dispose();
      await b.dispose();
    });

    test('a late joiner catches up on the whole log in order', () async {
      final store = InMemoryCollabLogStore();
      final a = WebdavAsyncTransport(store: store, participantId: 'A');
      await a.sendOp(remove('a'));
      await a.sendOp(remove('b'));
      await a.sendOp(remove('c'));

      // b joins only now, having missed all three, and polls once.
      final b = WebdavAsyncTransport(store: store, participantId: 'B');
      final bOps = <DeckOp>[];
      b.ops.listen(bOps.add);
      await b.poll();
      await pumpEventQueue();

      expect(
        bOps.map((o) => (o as RemoveSlide).slideId),
        ['a', 'b', 'c'],
        reason: 'delivered strictly in log order',
      );

      await a.dispose();
      await b.dispose();
    });

    test('a gap holds delivery until the missing record arrives', () async {
      final store = InMemoryCollabLogStore();
      final b = WebdavAsyncTransport(store: store, participantId: 'B');
      final bOps = <DeckOp>[];
      b.ops.listen(bOps.add);

      // Seq 1 is still missing; only seq 2 exists (an out-of-order arrival).
      await store.append(
        2,
        '{"kind":"op","from":"A","op":'
        '{"op":"removeSlide","version":2,"authorId":"A","slideId":"two"}}',
      );
      await b.poll();
      await pumpEventQueue();
      expect(bOps, isEmpty, reason: 'must not deliver past a gap');

      // Now seq 1 lands; the next poll delivers 1 then 2, in order.
      await store.append(
        1,
        '{"kind":"op","from":"A","op":'
        '{"op":"removeSlide","version":1,"authorId":"A","slideId":"one"}}',
      );
      await b.poll();
      await pumpEventQueue();
      expect(bOps.map((o) => (o as RemoveSlide).slideId), ['one', 'two']);

      await b.dispose();
    });

    test('concurrent sends both land, at distinct sequence numbers', () async {
      final store = InMemoryCollabLogStore();
      final a = WebdavAsyncTransport(store: store, participantId: 'A');
      final b = WebdavAsyncTransport(store: store, participantId: 'B');

      await Future.wait([
        a.sendOp(remove('from-a', author: 'A')),
        b.sendOp(remove('from-b', author: 'B')),
      ]);

      expect(
        await store.listSequences(),
        [1, 2],
        reason: 'the conditional append forces the racers onto separate slots',
      );

      // Each hears exactly the other's op.
      final aOps = <DeckOp>[];
      final bOps = <DeckOp>[];
      a.ops.listen(aOps.add);
      b.ops.listen(bOps.add);
      await a.poll();
      await b.poll();
      await pumpEventQueue();
      expect(aOps.map((o) => (o as RemoveSlide).slideId), ['from-b']);
      expect(bOps.map((o) => (o as RemoveSlide).slideId), ['from-a']);

      await a.dispose();
      await b.dispose();
    });

    test('locks propagate, including the forced flag', () async {
      final store = InMemoryCollabLogStore();
      final a = WebdavAsyncTransport(store: store, participantId: 'A');
      final b = WebdavAsyncTransport(store: store, participantId: 'B');
      final bLocks = <LockEvent>[];
      b.locks.listen(bLocks.add);

      await a.setLock('s1', held: true);
      await a.setLock('s1', held: false, forced: true);
      await b.poll();
      await pumpEventQueue();

      expect(bLocks.map((e) => e.held), [true, false]);
      expect(bLocks.last.forced, isTrue);
      expect(bLocks.first.participantId, 'A');

      await a.dispose();
      await b.dispose();
    });

    test('a malformed record is skipped without wedging the log', () async {
      final store = InMemoryCollabLogStore();
      // A poison record lands first, then a good one from A at seq 2.
      await store.append(1, 'this is not json {');
      final a = WebdavAsyncTransport(store: store, participantId: 'A');
      await a.sendOp(remove('good')); // lands at seq 2 (seq 1 is taken)

      final b = WebdavAsyncTransport(store: store, participantId: 'B');
      final bOps = <DeckOp>[];
      b.ops.listen(bOps.add);
      await b.poll();
      await pumpEventQueue();

      expect(
        bOps.map((o) => (o as RemoveSlide).slideId),
        ['good'],
        reason: 'the poison record is skipped, the good one still arrives',
      );

      await a.dispose();
      await b.dispose();
    });

    test('a disposed transport rejects sends and stops delivering', () async {
      final store = InMemoryCollabLogStore();
      final a = WebdavAsyncTransport(store: store, participantId: 'A');
      final b = WebdavAsyncTransport(store: store, participantId: 'B');
      final bOps = <DeckOp>[];
      b.ops.listen(bOps.add);

      await b.dispose();
      expect(() => b.sendOp(remove('x')), throwsStateError);

      await a.sendOp(remove('y'));
      await b.poll(); // no-op after dispose
      await pumpEventQueue();
      expect(bOps, isEmpty);

      await a.dispose();
    });
  });

  group('CollabSession end-to-end over the async transport', () {
    test(
      'a follower intent round-trips to an applied authoritative op',
      () async {
        final store = InMemoryCollabLogStore();
        final deck = Deck(
          title: 'd',
          slides: [const Slide(id: 's1', type: SlideType.bullets, title: 'x')],
        );
        final ta = WebdavAsyncTransport(store: store, participantId: 'A');
        final tb = WebdavAsyncTransport(store: store, participantId: 'B');
        final owner = CollabSession(
          initialDeck: deck,
          transport: ta,
          isAuthority: true,
        );
        final guest = CollabSession(
          initialDeck: deck,
          transport: tb,
          isAuthority: false,
        );

        // The guest (a non-authority) submits an edit; it crosses as an intent.
        await guest.submit(
          const SetSlideField(
            version: 0,
            authorId: 'B',
            slideId: 's1',
            field: SlideField.title,
            value: 'edited',
          ),
        );

        // The owner polls, applies the intent and rebroadcasts the versioned op.
        await ta.poll();
        await pumpEventQueue();
        expect(owner.deck.slides.single.title, 'edited');
        expect(owner.version, 1);

        // The guest polls and converges on the authority's deck.
        await tb.poll();
        await pumpEventQueue();
        expect(guest.deck.slides.single.title, 'edited');
        expect(guest.version, 1);

        await owner.dispose();
        await guest.dispose();
      },
    );
  });
}
