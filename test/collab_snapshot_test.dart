import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_log_store.dart';
import 'package:ocideck/collab/collab_snapshot.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';

Slide slide(String id, String title) =>
    Slide(id: id, type: SlideType.bullets, title: title, bullets: [title]);

void main() {
  group('CollabSnapshot', () {
    test('capture then applyTo restores the slides at a version', () {
      final deck = Deck(
        title: 'd',
        slides: [slide('a', 'one'), slide('b', 'two')],
      );
      final snap = CollabSnapshot.capture(deck, 5);
      expect(snap.version, 5);

      final rebased = snap.applyTo(Deck(title: 'blank'));
      expect(rebased.slides.map((s) => s.id), ['a', 'b']);
      expect(rebased.slides.map((s) => s.title), ['one', 'two']);
    });

    test('round-trips through JSON, ids and content intact', () {
      final deck = Deck(title: 'd', slides: [slide('x', 'hi')]);
      final r = CollabSnapshot.fromJson(
        CollabSnapshot.capture(deck, 2).toJson(),
      );
      expect(r.version, 2);
      expect(r.slides.single.id, 'x');
      expect(r.slides.single.title, 'hi');
      expect(r.slides.single.bullets, ['hi']);
    });

    test('gives a joiner the authority slide-id space (§5.5)', () {
      // Two participants opened the same content, so same structure but the ids
      // differ — every op is keyed by id, so without this they would desync.
      final authority = Deck(title: 'd', slides: [slide('auth-1', 'intro')]);
      final joinerLocal = Deck(title: 'd', slides: [slide('join-9', 'intro')]);

      final rebased = CollabSnapshot.capture(authority, 0).applyTo(joinerLocal);

      expect(
        rebased.slides.single.id,
        'auth-1',
        reason: 'the joiner adopts the authority ids',
      );
    });

    test('applyTo leaves the rest of the base deck untouched', () {
      final base = Deck(title: 'keep-me', theme: 'my-theme', author: 'ann');
      final rebased = CollabSnapshot.capture(
        Deck(title: 'other', slides: [slide('a', 'x')]),
        1,
      ).applyTo(base);
      expect(rebased.title, 'keep-me');
      expect(rebased.theme, 'my-theme');
      expect(rebased.author, 'ann');
      expect(rebased.slides.single.id, 'a');
    });

    group('fail-closed decoding', () {
      test('a non-int version throws', () {
        expect(
          () => CollabSnapshot.fromJson({'version': 'x', 'slides': []}),
          throwsFormatException,
        );
      });
      test('a non-list slides throws', () {
        expect(
          () => CollabSnapshot.fromJson({'version': 1, 'slides': 3}),
          throwsFormatException,
        );
      });
      test('a slide that is not an object throws', () {
        expect(
          () => CollabSnapshot.fromJson({
            'version': 1,
            'slides': ['not an object'],
          }),
          throwsFormatException,
        );
      });
    });
  });

  group('InMemoryCollabLogStore snapshot slot', () {
    test('reads null until written, then the last write', () async {
      final store = InMemoryCollabLogStore();
      expect(await store.readSnapshot(), isNull);
      await store.writeSnapshot('{"version":1}');
      expect(await store.readSnapshot(), '{"version":1}');
      await store.writeSnapshot('{"version":2}');
      expect(await store.readSnapshot(), '{"version":2}');
    });
  });
}
