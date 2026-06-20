import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/user_notes_codec.dart';

void main() {
  group('UserNotesCodec', () {
    test('encodes nothing when there are no notes', () {
      final slides = [Slide.create(SlideType.bullets)];
      expect(UserNotesCodec.encode(slides, {}), isNull);
    });

    test('encodes nothing when notes are empty or whitespace', () {
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final slides = [slide];
      expect(UserNotesCodec.encode(slides, {slide.id: '   '}), isNull);
    });

    test('round-trips notes for the same deck', () {
      final slides = [
        Slide.create(SlideType.bullets).copyWith(title: 'A'),
        Slide.create(SlideType.bullets).copyWith(title: 'B'),
      ];
      final notes = {slides[1].id: 'Mijn cursusnotitie'};
      final json = UserNotesCodec.encode(slides, notes)!;
      final back = UserNotesCodec.decode(json, slides);
      expect(back.keys, [slides[1].id]);
      expect(back[slides[1].id], 'Mijn cursusnotitie');
    });

    test('re-anchors notes to the matching slide after reordering', () {
      final a = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final b = Slide.create(SlideType.bullets).copyWith(title: 'B');
      final json = UserNotesCodec.encode([a, b], {a.id: 'notitie A'})!;

      final a2 = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final b2 = Slide.create(SlideType.bullets).copyWith(title: 'B');
      final back = UserNotesCodec.decode(json, [b2, a2]);
      expect(back.containsKey(a2.id), isTrue);
      expect(back[a2.id], 'notitie A');
      expect(back.containsKey(b2.id), isFalse);
    });

    test('re-anchors after insert at the front', () {
      final a = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final b = Slide.create(SlideType.bullets).copyWith(title: 'B');
      final json = UserNotesCodec.encode([a, b], {b.id: 'notitie B'})!;

      final intro = Slide.create(SlideType.title).copyWith(title: 'Intro');
      final a2 = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final b2 = Slide.create(SlideType.bullets).copyWith(title: 'B');
      final back = UserNotesCodec.decode(json, [intro, a2, b2]);
      expect(back[b2.id], 'notitie B');
    });

    test('drops notes when the slide content changed', () {
      final a = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final json = UserNotesCodec.encode([a], {a.id: 'behoud mij niet'})!;
      final edited = Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'A (changed)');
      final back = UserNotesCodec.decode(json, [edited]);
      expect(back, isEmpty);
    });

    test('does not attach orphaned notes to the wrong slide', () {
      final a = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final json = UserNotesCodec.encode([a], {a.id: 'alleen voor A'})!;
      final onlyB = Slide.create(SlideType.bullets).copyWith(title: 'B');
      final back = UserNotesCodec.decode(json, [onlyB]);
      expect(back, isEmpty);
    });
  });
}
