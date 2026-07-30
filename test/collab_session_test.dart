import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/collab_transport.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

void main() {
  Slide baseSlide() => Slide.create(SlideType.bullets).copyWith(title: 'start');
  Deck deckWith(Slide s) => Deck(title: 'deck', slides: [s]);

  group('LoopbackHub / LoopbackTransport', () {
    test(
      'delivers a send to the others but never echoes to the sender',
      () async {
        final hub = LoopbackHub();
        final t1 = hub.connect('p1');
        final t2 = hub.connect('p2');
        final at1 = <DeckOp>[];
        final at2 = <DeckOp>[];
        t1.ops.listen(at1.add);
        t2.ops.listen(at2.add);

        await t1.sendOp(
          const RemoveSlide(version: 1, authorId: 'p1', slideId: 'x'),
        );
        await pumpEventQueue();

        expect(at1, isEmpty, reason: 'a sender must not hear its own op');
        expect(at2, hasLength(1));
        expect(at2.single.authorId, 'p1');

        await t1.dispose();
        await t2.dispose();
      },
    );

    test('a disposed transport rejects sends and stops delivering', () async {
      final hub = LoopbackHub();
      final t1 = hub.connect('p1');
      final t2 = hub.connect('p2');
      final at2 = <DeckOp>[];
      t2.ops.listen(at2.add);

      await t2.dispose();
      await t1.sendOp(
        const RemoveSlide(version: 1, authorId: 'p1', slideId: 'x'),
      );
      await pumpEventQueue();
      expect(at2, isEmpty, reason: 'a disposed member receives nothing');

      expect(
        () => t2.sendOp(
          const RemoveSlide(version: 1, authorId: 'p2', slideId: 'x'),
        ),
        throwsStateError,
      );
      await t1.dispose();
    });
  });

  group('CollabSession — op convergence', () {
    late LoopbackHub hub;
    late Slide slide;
    late CollabSession owner;
    late CollabSession peer;

    setUp(() {
      hub = LoopbackHub();
      slide = baseSlide();
      owner = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('owner'),
        isAuthority: true,
      );
      peer = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('peer'),
        isAuthority: false,
      );
    });

    tearDown(() async {
      await owner.dispose();
      await peer.dispose();
    });

    test(
      'an authority edit reaches the follower and bumps the version',
      () async {
        await owner.submit(
          SetSlideField(
            version: 0,
            authorId: 'owner',
            slideId: slide.id,
            field: SlideField.title,
            value: 'renamed',
          ),
        );
        await pumpEventQueue();

        expect(owner.deck.slides.single.title, 'renamed');
        expect(peer.deck.slides.single.title, 'renamed');
        expect(owner.version, 1);
        expect(peer.version, 1);
      },
    );

    test(
      'a follower edit round-trips through the authority and converges',
      () async {
        await peer.submit(
          SetSlideField(
            version: 0,
            authorId: 'peer',
            slideId: slide.id,
            field: SlideField.subtitle,
            value: 'from the peer',
          ),
        );
        await pumpEventQueue();

        expect(owner.deck.slides.single.subtitle, 'from the peer');
        expect(peer.deck.slides.single.subtitle, 'from the peer');
        // The authority assigned the version; both sides agree on it.
        expect(owner.version, 1);
        expect(peer.version, 1);
      },
    );

    test('a sequence of edits from both sides stays in one order', () async {
      await owner.submit(
        SetSlideField(
          version: 0,
          authorId: 'owner',
          slideId: slide.id,
          field: SlideField.title,
          value: 'A',
        ),
      );
      await pumpEventQueue();
      await peer.submit(
        SetSlideField(
          version: 0,
          authorId: 'peer',
          slideId: slide.id,
          field: SlideField.title,
          value: 'B',
        ),
      );
      await pumpEventQueue();

      // The authority serialised both; last writer (the peer's B, committed
      // second) wins on both replicas — and they agree.
      expect(owner.deck.slides.single.title, 'B');
      expect(peer.deck.slides.single.title, 'B');
      expect(owner.version, 2);
      expect(peer.version, 2);
    });

    test('an invalid op fails closed at the authority', () async {
      expect(
        () => owner.submit(
          const SetSlideField(
            version: 0,
            authorId: 'owner',
            slideId: 'no-such-slide',
            field: SlideField.title,
            value: 'x',
          ),
        ),
        throwsArgumentError,
      );
    });
  });

  group('CollabSession — locks', () {
    late LoopbackHub hub;
    late Slide slide;
    late CollabSession owner;
    late CollabSession peer;

    setUp(() {
      hub = LoopbackHub();
      slide = baseSlide();
      owner = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('owner'),
        isAuthority: true,
      );
      peer = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('peer'),
        isAuthority: false,
      );
    });

    tearDown(() async {
      await owner.dispose();
      await peer.dispose();
    });

    test('a claimed lock is visible to the other participant', () async {
      await peer.acquireLock(slide.id);
      await pumpEventQueue();
      expect(peer.locks[slide.id], 'peer');
      expect(owner.locks[slide.id], 'peer');

      await peer.releaseLock(slide.id);
      await pumpEventQueue();
      expect(peer.locks.containsKey(slide.id), isFalse);
      expect(owner.locks.containsKey(slide.id), isFalse);
    });

    test('the authority can force a lock open; a follower cannot', () async {
      await peer.acquireLock(slide.id);
      await pumpEventQueue();
      expect(owner.locks[slide.id], 'peer');

      await owner.forceUnlock(slide.id);
      await pumpEventQueue();
      expect(owner.locks.containsKey(slide.id), isFalse);
      expect(peer.locks.containsKey(slide.id), isFalse);

      expect(() => peer.forceUnlock(slide.id), throwsStateError);
    });
  });

  test('dispose is idempotent and blocks further use', () async {
    final hub = LoopbackHub();
    final session = CollabSession(
      initialDeck: deckWith(baseSlide()),
      transport: hub.connect('solo'),
      isAuthority: true,
    );
    await session.dispose();
    await session.dispose(); // no throw
    expect(
      () => session.submit(
        const RemoveSlide(version: 0, authorId: 'solo', slideId: 'x'),
      ),
      throwsStateError,
    );
  });
}
