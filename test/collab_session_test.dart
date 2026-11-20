import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_session.dart';
import 'package:ocideck/collab/collab_session_controller.dart';
import 'package:ocideck/collab/collab_transport.dart';
import 'package:ocideck/collab/deck_op.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

class _TransientSendFailure implements CollabTransport {
  _TransientSendFailure(this.delegate);

  final CollabTransport delegate;
  final attemptedVersions = <int>[];
  bool? available;

  @override
  String get participantId => delegate.participantId;

  @override
  Stream<DeckOp> get ops => delegate.ops;

  @override
  Stream<LockEvent> get locks => delegate.locks;

  @override
  Future<void> sendOp(DeckOp op) async {
    attemptedVersions.add(op.version);
    if (available == false ||
        (available == null && attemptedVersions.length == 1)) {
      throw StateError('connection lost');
    }
    await delegate.sendOp(op);
  }

  @override
  Future<void> setLock(
    String slideId, {
    required bool held,
    bool forced = false,
  }) => delegate.setLock(slideId, held: held, forced: forced);

  @override
  Future<void> dispose() => delegate.dispose();
}

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

  test(
    'a failed authoritative send is retried before a later version',
    () async {
      final hub = LoopbackHub();
      final slide = baseSlide();
      final transport = _TransientSendFailure(hub.connect('owner'));
      final owner = CollabSession(
        initialDeck: deckWith(slide),
        transport: transport,
        isAuthority: true,
      );
      final peer = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('peer'),
        isAuthority: false,
      );
      addTearDown(owner.dispose);
      addTearDown(peer.dispose);

      await expectLater(
        owner.submit(
          SetSlideField(
            version: 0,
            authorId: 'owner',
            slideId: slide.id,
            field: SlideField.title,
            value: 'first',
          ),
        ),
        throwsStateError,
      );
      await owner.submit(
        SetSlideField(
          version: 0,
          authorId: 'owner',
          slideId: slide.id,
          field: SlideField.subtitle,
          value: 'second',
        ),
      );
      await pumpEventQueue();

      expect(transport.attemptedVersions, [1, 1, 2]);
      expect(peer.version, owner.version);
      expect(peer.deck.slides.single.title, 'first');
      expect(peer.deck.slides.single.subtitle, 'second');
    },
  );

  test('an idle authority recovers after more than three failed retries', () {
    final hub = LoopbackHub();
    final slide = baseSlide();
    final transport = _TransientSendFailure(hub.connect('owner'))
      ..available = false;
    late CollabSession owner;
    late CollabSession peer;
    fakeAsync((clock) {
      owner = CollabSession(
        initialDeck: deckWith(slide),
        transport: transport,
        isAuthority: true,
      );
      peer = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('peer'),
        isAuthority: false,
      );
      var failures = 0;
      owner
          .submit(
            SetSlideField(
              version: 0,
              authorId: 'owner',
              slideId: slide.id,
              field: SlideField.title,
              value: 'retained',
            ),
          )
          .catchError((Object _) {
            failures++;
          });
      clock.flushMicrotasks();
      expect(failures, 1);
      clock.elapse(const Duration(seconds: 8));
      expect(transport.attemptedVersions, [1, 1, 1, 1]);
      expect(peer.version, 0);
      clock.elapse(const Duration(minutes: 1));
      expect(transport.attemptedVersions, hasLength(7));
      transport.available = true;
      clock.elapse(const Duration(seconds: 30));
      expect(peer.deck.slides.single.title, 'retained');
      expect(peer.version, 1);
      expect(transport.attemptedVersions, List.filled(8, 1));
      owner.dispose();
      peer.dispose();
      clock.flushMicrotasks();
      expect(clock.pendingTimers, isEmpty);
    });
  });

  test(
    'failed guest field survives unrelated remote edit and can be resent',
    () async {
      final hub = LoopbackHub();
      final slide = baseSlide();
      final owner = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('owner'),
        isAuthority: true,
      );
      final transport = _TransientSendFailure(hub.connect('guest'));
      final guest = CollabSession(
        initialDeck: deckWith(slide),
        transport: transport,
        isAuthority: false,
      );
      var local = guest.deck;
      var failures = 0;
      final controller = CollabSessionController(
        session: guest,
        readDeck: () => local,
        writeDeck: (deck) => local = deck,
        onSubmitFailure: () => failures++,
      );
      addTearDown(owner.dispose);
      addTearDown(controller.dispose);
      local = local.copyWith(slides: [slide.copyWith(title: 'unsent')]);
      controller.onLocalEdit(local);
      await pumpEventQueue();
      expect(failures, 1);
      await owner.submit(
        SetSlideField(
          version: 0,
          authorId: 'owner',
          slideId: slide.id,
          field: SlideField.subtitle,
          value: 'remote',
        ),
      );
      await pumpEventQueue();
      expect(local.slides.single.title, 'unsent');
      expect(local.slides.single.subtitle, 'remote');
      // De volgende echte bewerking dient ook de nog niet ontvangen waarde in.
      local = local.copyWith(
        slides: [local.slides.single.copyWith(notes: 'next')],
      );
      controller.onLocalEdit(local);
      await pumpEventQueue();
      expect(owner.deck.slides.single.title, 'unsent');
      expect(owner.deck.slides.single.notes, 'next');
      expect(local.slides.single.title, 'unsent');
    },
  );

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

  group('CollabSession — mutable authority (owner-drop handover, §5.3)', () {
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

    test('a promoted follower resumes versioning without a gap', () async {
      // The owner drives the version up to 2, then drops.
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
      await owner.submit(
        SetSlideField(
          version: 0,
          authorId: 'owner',
          slideId: slide.id,
          field: SlideField.title,
          value: 'B',
        ),
      );
      await pumpEventQueue();
      expect(peer.version, 2, reason: 'the follower caught up to the owner');

      // Hand over: the owner steps down, the peer takes over.
      owner.stepDown();
      peer.becomeAuthority();
      expect(peer.isAuthority, isTrue);
      expect(owner.isAuthority, isFalse);

      // The new authority commits directly and resumes from version 2 — the next
      // version is 3, not a reset-to-1 that would collide with history.
      await peer.submit(
        SetSlideField(
          version: 0,
          authorId: 'peer',
          slideId: slide.id,
          field: SlideField.title,
          value: 'C',
        ),
      );
      await pumpEventQueue();

      expect(peer.version, 3, reason: 'resumed from 2, not reset');
      expect(peer.deck.slides.single.title, 'C');
      expect(
        owner.version,
        3,
        reason: 'the former owner, now a follower, applied v3',
      );
      expect(owner.deck.slides.single.title, 'C');
    });

    test(
      'after hand-over the former authority edits round-trip as intents',
      () async {
        owner.stepDown();
        peer.becomeAuthority();

        // The former owner is now a follower: its edit crosses as an intent for the
        // new authority to version, rather than being committed locally.
        await owner.submit(
          SetSlideField(
            version: 0,
            authorId: 'owner',
            slideId: slide.id,
            field: SlideField.subtitle,
            value: 'late note',
          ),
        );
        await pumpEventQueue();

        expect(
          peer.deck.slides.single.subtitle,
          'late note',
          reason: 'the new authority versioned the former owner\'s intent',
        );
        expect(peer.version, 1);
        expect(owner.deck.slides.single.subtitle, 'late note');
        expect(owner.version, 1);
      },
    );

    test('becomeAuthority and stepDown are idempotent', () async {
      peer.becomeAuthority();
      peer.becomeAuthority();
      expect(peer.isAuthority, isTrue);
      peer.stepDown();
      peer.stepDown();
      expect(peer.isAuthority, isFalse);
    });

    test(
      'flipping authority on a disposed session is a no-op, not a throw',
      () async {
        await peer.dispose();
        peer.becomeAuthority(); // no throw
        expect(peer.isAuthority, isFalse);
      },
    );
  });

  group('CollabSession — initial version (§5.2 re-baselining)', () {
    test('a session started at a non-zero version resumes from there', () async {
      // Both join from a baseline re-based at version 10 (a late joiner scenario).
      final hub = LoopbackHub();
      final slide = baseSlide();
      final owner = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('owner'),
        isAuthority: true,
        initialVersion: 10,
      );
      final peer = CollabSession(
        initialDeck: deckWith(slide),
        transport: hub.connect('peer'),
        isAuthority: false,
        initialVersion: 10,
      );
      expect(owner.version, 10);
      expect(peer.version, 10);

      // The authority's next op is version 11 (not 1), and the follower — also
      // starting at 10 — accepts it as the next in line.
      await owner.submit(
        SetSlideField(
          version: 0,
          authorId: 'owner',
          slideId: slide.id,
          field: SlideField.title,
          value: 'after rebaseline',
        ),
      );
      await pumpEventQueue();

      expect(
        owner.version,
        11,
        reason: 'assigned from the start version, not 1',
      );
      expect(peer.version, 11);
      expect(peer.deck.slides.single.title, 'after rebaseline');

      await owner.dispose();
      await peer.dispose();
    });

    test('rebaseTo jumps forward only (§5.2 strand-recovery)', () async {
      final hub = LoopbackHub();
      final session = CollabSession(
        initialDeck: deckWith(baseSlide()),
        transport: hub.connect('p'),
        isAuthority: false,
        initialVersion: 5,
      );

      // A lower (or equal) version is ignored — a stale or half-read snapshot can
      // never rewind the session or replay an op.
      final backward = Deck(
        title: 'x',
        slides: [Slide.create(SlideType.bullets)],
      );
      expect(session.rebaseTo(backward, 3), isFalse);
      expect(session.version, 5);

      // A higher version jumps: adopt its deck and version.
      final ahead = Deck(
        title: 'x',
        slides: [Slide.create(SlideType.bullets).copyWith(title: 'jumped')],
      );
      expect(session.rebaseTo(ahead, 12), isTrue);
      expect(session.version, 12);
      expect(session.deck.slides.single.title, 'jumped');

      await session.dispose();
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
