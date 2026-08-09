// Het gedeelde CollabTransport-contract — één set conformatietesten die over
// elke [CollabTransport]-implementatie draait (Loopback, Matrix, XMPP), naar
// hetzelfde patroon als `runGitForgeContract`
// (`docs/design/XMPP_COLLAB_TRANSPORT.md` §8: "Contract (shared): one
// CollabTransport conformance test over Loopback, Matrix and XMPP").
//
// Wat hier wordt beweerd is gedrag dat een *aanroeper* mag vertrouwen
// ongeacht welke transport eronder zit. Transport-specifieke details
// (crypto, gap-detectie, sync-cadans) horen in de eigen test van die
// transport, niet hier. De [CollabTransportPair.pump]-callback levert de
// implementatie-specifieke manier om in afwachting zijnde berichten af te
// leveren — `pumpEventQueue` voor push-based (Loopback, XMPP), `syncOnce` +
// `pumpEventQueue` voor pull-based (Matrix).

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_transport.dart';
import 'package:ocideck/collab/deck_op.dart';

/// Een paar [CollabTransport]s die met elkaar praten, plus de
/// implementatie-specifieke manier om berichten te laten stromen.
class CollabTransportPair {
  CollabTransportPair({
    required this.a,
    required this.b,
    required this.pump,
    required this.dispose,
  });

  final CollabTransport a;
  final CollabTransport b;

  /// Lever in afwachting zijnde berichten af — push-based (Loopback, XMPP)
  /// heeft alleen `pumpEventQueue`; pull-based (Matrix) roept hier `syncOnce`
  /// aan op beide kanten.
  final Future<void> Function() pump;

  /// Ruim beide transports op. Idempotent.
  final Future<void> Function() dispose;
}

/// Draai het CollabTransport-contract over één implementatie. [create]
/// levert een vers [CollabTransportPair] per test; de tearDown disposeert het.
void runCollabTransportContract(
  String name,
  Future<CollabTransportPair> Function() create,
) {
  group('$name honours the CollabTransport contract', () {
    late CollabTransportPair pair;

    setUp(() async {
      pair = await create();
    });

    tearDown(() async {
      await pair.dispose();
    });

    test('participantId is non-empty on both sides', () {
      expect(pair.a.participantId, isNotEmpty);
      expect(pair.b.participantId, isNotEmpty);
    });

    test('an op sent by a reaches b', () async {
      final received = <DeckOp>[];
      final sub = pair.b.ops.listen(received.add);
      await pair.a.sendOp(
        SetSlideField(
          version: 1,
          authorId: 'a',
          slideId: 's1',
          field: SlideField.title,
          value: 'hello',
        ),
      );
      await pair.pump();
      expect(received, hasLength(1));
      final op = received.single as SetSlideField;
      expect(op.value, 'hello');
      expect(op.slideId, 's1');
      await sub.cancel();
    });

    test('a lock event sent by a reaches b', () async {
      final received = <LockEvent>[];
      final sub = pair.b.locks.listen(received.add);
      await pair.a.setLock('slide-1', held: true);
      await pair.pump();
      expect(received, hasLength(1));
      expect(received.single.slideId, 'slide-1');
      expect(received.single.held, isTrue);
      await sub.cancel();
    });

    test('own ops are not echoed back to the sender', () async {
      final received = <DeckOp>[];
      final sub = pair.a.ops.listen(received.add);
      await pair.a.sendOp(
        SetSlideField(
          version: 1,
          authorId: 'a',
          slideId: 's1',
          field: SlideField.title,
          value: 'echo',
        ),
      );
      await pair.pump();
      expect(received, isEmpty);
      await sub.cancel();
    });

    test('own locks are not echoed back to the sender', () async {
      final received = <LockEvent>[];
      final sub = pair.a.locks.listen(received.add);
      await pair.a.setLock('slide-1', held: true);
      await pair.pump();
      expect(received, isEmpty);
      await sub.cancel();
    });

    test('dispose is idempotent', () async {
      await pair.a.dispose();
      await pair.a.dispose(); // geen throw
    });
  });
}
