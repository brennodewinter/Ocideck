import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/git/version_diff.dart';

/// Twee uitgebrachte versies naast elkaar (§9.5). Een deck heeft geen slide-id's,
/// dus de koppeling moet het van inhoud hebben: identieke slides vinden elkaar
/// (ook verschoven), een bijgewerkte slide hoort als *dezelfde* slide te worden
/// herkend — niet als een toevoeging plus een verwijdering.
void main() {
  Slide bullets(String title, List<String> items) =>
      Slide.create(SlideType.bullets).copyWith(title: title, bullets: items);

  Deck deckOf(List<Slide> slides) => Deck(title: 'Kwartaal', slides: slides);

  group('diffDeckVersions', () {
    test('an identical deck reports no changes', () {
      final slides = [
        bullets('Eén', const ['a']),
        bullets('Twee', const ['b']),
      ];
      final diff = diffDeckVersions(deckOf(slides), deckOf(slides));

      expect(diff.hasChanges, isFalse);
      expect(diff.changes, hasLength(2));
      expect(
        diff.changes.every((c) => c.kind == SlideChangeKind.unchanged),
        isTrue,
      );
    });

    test('an appended slide is added, the rest untouched', () {
      final before = deckOf([
        bullets('Eén', const ['a']),
      ]);
      final after = deckOf([
        bullets('Eén', const ['a']),
        bullets('Twee', const ['b']),
      ]);

      final diff = diffDeckVersions(before, after);

      expect(diff.addedCount, 1);
      expect(diff.removedCount, 0);
      final added = diff.changes.firstWhere(
        (c) => c.kind == SlideChangeKind.added,
      );
      expect(added.after!.title, 'Twee');
      expect(added.afterIndex, 1);
    });

    test('a dropped slide is removed, at the place it stood', () {
      final before = deckOf([
        bullets('Eén', const ['a']),
        bullets('Twee', const ['b']),
      ]);
      final after = deckOf([
        bullets('Eén', const ['a']),
      ]);

      final diff = diffDeckVersions(before, after);

      expect(diff.removedCount, 1);
      expect(diff.addedCount, 0);
      final removed = diff.changes.firstWhere(
        (c) => c.kind == SlideChangeKind.removed,
      );
      expect(removed.before!.title, 'Twee');
      expect(removed.beforeIndex, 1);
    });

    test('a reordered slide is moved, not added-and-removed', () {
      final one = bullets('Eén', const ['a']);
      final two = bullets('Twee', const ['b']);
      final diff = diffDeckVersions(deckOf([one, two]), deckOf([two, one]));

      expect(diff.addedCount, 0);
      expect(diff.removedCount, 0);
      expect(diff.movedCount, 2);
      expect(diff.hasChanges, isTrue);
    });

    test('an edited slide is one change, with the differing fields', () {
      // Dit is het venijn: zonder gelijkenis-koppeling zou dit als een
      // toevoeging én een verwijdering lezen, en dat is geen bruikbare diff.
      final before = deckOf([
        bullets('Kwartaalcijfers', const ['omzet groeit', 'marge stabiel']),
      ]);
      final after = deckOf([
        bullets('Kwartaalcijfers', const [
          'omzet groeit sterk',
          'marge stabiel',
        ]),
      ]);

      final diff = diffDeckVersions(before, after);

      expect(diff.editedCount, 1);
      expect(diff.addedCount, 0);
      expect(diff.removedCount, 0);
      final edited = diff.changes.single;
      expect(edited.before, isNotNull);
      expect(edited.after, isNotNull);
      expect(edited.fields, isNotEmpty, reason: 'de gewijzigde velden');
    });

    test('a wholly different slide is a replacement, not an edit', () {
      final before = deckOf([
        bullets('Omzet', const ['cijfers']),
      ]);
      final after = deckOf([
        bullets('Volstrekt ander onderwerp', const ['niets gemeen hiermee']),
      ]);

      final diff = diffDeckVersions(before, after);

      expect(diff.editedCount, 0);
      expect(diff.addedCount, 1);
      expect(diff.removedCount, 1);
    });

    test('slides of a different type never pair up as an edit', () {
      final before = deckOf([
        bullets('Zelfde tekst', const ['zelfde']),
      ]);
      final after = deckOf([
        Slide.create(SlideType.title).copyWith(title: 'Zelfde tekst'),
      ]);

      final diff = diffDeckVersions(before, after);

      expect(diff.editedCount, 0);
      expect(diff.addedCount, 1);
      expect(diff.removedCount, 1);
    });

    test('an empty older version makes every slide an addition', () {
      final diff = diffDeckVersions(
        deckOf(const []),
        deckOf([
          bullets('Eén', const ['a']),
          bullets('Twee', const ['b']),
        ]),
      );
      expect(diff.addedCount, 2);
      expect(diff.removedCount, 0);
    });

    test('repeated identical slides pair up nearest-first, not crosswise', () {
      final same = bullets('Herhaald', const ['x']);
      final before = deckOf([
        same,
        bullets('Midden', const ['m']),
        same,
      ]);
      final after = deckOf([
        same,
        bullets('Midden', const ['m']),
        same,
      ]);

      final diff = diffDeckVersions(before, after);
      expect(diff.hasChanges, isFalse);
      expect(diff.movedCount, 0);
    });
  });
}
