import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_collab_field_parity.dart';

/// Guards the gate that guards the collaboration surface (#1803).
///
/// The bug this exists for was not a wrong line of code — it was a *missing
/// direction*. Two parity tests both asked "is everything in `SlideField`
/// handled?", nobody asked "is every syncable `Slide` field in `SlideField`?",
/// and `imageZoom` fell through the gap for two weeks without a single gate
/// noticing.
///
/// A gate nobody has watched fail is not known to guard anything, so every rule
/// below is checked in both directions: silent on the real repository, and
/// loud on a planted violation.
void main() {
  group('slideFieldNames', () {
    test('reads the final fields declared on class Slide', () {
      const source = '''
class SlideTypeMeta {
  final String decoy;
}

class Slide {
  final String id;
  final int imageZoom;
  final List<String> bullets;
  Slide({this.id = ''});
}

class Other {
  final String notMine;
}
''';
      expect(slideFieldNames(source), ['id', 'imageZoom', 'bullets']);
    });

    test('a missing class is an error, not an empty list', () {
      // Silently returning nothing would make the gate pass forever the day
      // someone renames the class.
      expect(() => slideFieldNames('class NotSlide {}'), throwsStateError);
    });
  });

  group('slideFieldEnumNames', () {
    test('reads the enum entries, ignoring comments', () {
      const source = '''
enum SlideField {
  // — String —
  title,
  imageSize,
  imageZoom, // int
}
''';
      expect(slideFieldEnumNames(source), ['title', 'imageSize', 'imageZoom']);
    });
  });

  group('parityProblems', () {
    const deliberate = {'id': 'identity'};
    const baseline = {'anchor'};

    test('is silent when every field is classified', () {
      expect(
        parityProblems(
          fields: ['id', 'title', 'anchor'],
          synced: {'title'},
          deliberate: deliberate,
          baseline: baseline,
        ),
        isEmpty,
      );
    });

    test('a new unclassified field fails — the imageZoom case', () {
      final problems = parityProblems(
        fields: ['id', 'title', 'anchor', 'imageZoom'],
        synced: {'title'},
        deliberate: deliberate,
        baseline: baseline,
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('imageZoom'));
      expect(problems.single, contains('Not classified'));
    });

    test('the baseline may not keep a field that is now synced', () {
      final problems = parityProblems(
        fields: ['id', 'title', 'anchor'],
        synced: {'title', 'anchor'},
        deliberate: deliberate,
        baseline: baseline,
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('anchor'));
      expect(problems.single, contains('Now synced'));
    });

    test('an entry for a field that no longer exists fails', () {
      final problems = parityProblems(
        fields: ['id', 'title'],
        synced: {'title'},
        deliberate: deliberate,
        baseline: baseline,
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('No longer a field'));
    });

    test('the enum may not name something Slide does not have', () {
      final problems = parityProblems(
        fields: ['id', 'title'],
        synced: {'title', 'ghost'},
        deliberate: deliberate,
        baseline: const {},
      );
      expect(problems, hasLength(1));
      expect(problems.single, contains('ghost'));
    });
  });

  group('the real repository', () {
    late List<String> fields;
    late Set<String> synced;

    setUpAll(() {
      fields = slideFieldNames(
        File('lib/models/slide.dart').readAsStringSync(),
      );
      synced = slideFieldEnumNames(
        File('lib/collab/deck_op.dart').readAsStringSync(),
      ).toSet();
    });

    test('every Slide field is classified', () {
      expect(parityProblems(fields: fields, synced: synced), isEmpty);
    });

    test('imageZoom syncs on edit, which is the whole point of #1803', () {
      expect(synced, contains('imageZoom'));
      expect(unsyncedBaseline, isNot(contains('imageZoom')));
    });

    test('every deliberate exclusion carries a reason', () {
      // An empty reason is how "deliberate" quietly becomes "forgotten".
      for (final entry in deliberatelyNotSynced.entries) {
        expect(
          entry.value.trim().length,
          greaterThan(20),
          reason: '${entry.key} needs a real reason, not a placeholder',
        );
      }
    });

    test('the two lists do not overlap', () {
      expect(
        unsyncedBaseline.intersection(deliberatelyNotSynced.keys.toSet()),
        isEmpty,
        reason: 'a field is either a decision or debt, never both',
      );
    });
  });
}
