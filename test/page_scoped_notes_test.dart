import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/page_scoped_notes.dart';

void main() {
  group('user note keys', () {
    test('slide-wide key when not multi-page', () {
      expect(
        userNoteStorageKey('abc', 2, multiPage: false),
        'abc',
      );
    });

    test('page key when multi-page', () {
      expect(
        userNoteStorageKey('abc', 2, multiPage: true),
        'abc#p2',
      );
    });

    test('slideHasUserNotes finds page-specific notes', () {
      final notes = {'slide1#p1': 'page two'};
      expect(slideHasUserNotes(notes, 'slide1'), isTrue);
      expect(slideHasUserNotes(notes, 'slide2'), isFalse);
    });
  });

  group('speaker notes per page', () {
    test('single page returns raw text', () {
      expect(speakerNoteForPage('Hello', 0, 1), 'Hello');
    });

    test('round-trips page sections', () {
      const raw = '''
<!-- ocideck_page:1 -->
First page note

<!-- ocideck_page:2 -->
Second page note
''';
      expect(speakerNoteForPage(raw, 0, 3), 'First page note');
      expect(speakerNoteForPage(raw, 1, 3), 'Second page note');
      expect(speakerNoteForPage(raw, 2, 3), '');

      final updated = updateSpeakerNoteForPage(raw, 1, 3, 'Updated page 2');
      expect(speakerNoteForPage(updated, 1, 3), 'Updated page 2');
      expect(speakerNoteForPage(updated, 0, 3), 'First page note');
    });

    test('update clears empty page', () {
      const raw = '<!-- ocideck_page:2 -->\nOnly page 2';
      final updated = updateSpeakerNoteForPage(raw, 1, 2, '');
      expect(updated, isEmpty);
    });
  });
}
