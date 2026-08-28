import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/services/callout_reference_allocator.dart';

void main() {
  group('nextFreeReference', () {
    test('empty sets → A', () {
      expect(nextFreeReference({}, {}), 'A');
    });

    test('skips letters used by callouts', () {
      expect(nextFreeReference({'A'}, {}), 'B');
    });

    test('skips letters used by prose', () {
      expect(nextFreeReference({}, {'A'}), 'B');
    });

    test('skips both callout and prose letters', () {
      expect(nextFreeReference({'B'}, {'A', 'C'}), 'D');
    });

    test('returns null when all 26 letters are taken', () {
      final all = {for (var i = 0; i < 26; i++) String.fromCharCode(65 + i)};
      expect(nextFreeReference(all, {}), isNull);
    });

    test('returns null when all 26 are split across both sets', () {
      final callouts = {
        for (var i = 0; i < 13; i++) String.fromCharCode(65 + i),
      };
      final prose = {for (var i = 13; i < 26; i++) String.fromCharCode(65 + i)};
      expect(nextFreeReference(callouts, prose), isNull);
    });

    test('first free after existing callouts', () {
      expect(nextFreeReference({'A', 'B'}, {}), 'C');
    });
  });

  group('trailingReferenceLetters', () {
    test('no matches → empty set', () {
      expect(
        trailingReferenceLetters(['just text', 'another bullet']),
        isEmpty,
      );
    });

    test('single match', () {
      expect(trailingReferenceLetters(['some text (A)']), {'A'});
    });

    test('multiple matches', () {
      expect(trailingReferenceLetters(['first (A)', 'second (B)']), {'A', 'B'});
    });

    test('no space before paren → no match', () {
      expect(trailingReferenceLetters(['text(A)']), isEmpty);
    });

    test('lowercase → no match', () {
      expect(trailingReferenceLetters(['text (a)']), isEmpty);
    });

    test('mid-string match → no match', () {
      expect(trailingReferenceLetters(['(A) text here']), isEmpty);
    });

    test('deduplicates identical letters', () {
      expect(trailingReferenceLetters(['one (A)', 'two (A)']), {'A'});
    });
  });

  group('calloutLetters', () {
    test('empty → empty set', () {
      expect(calloutLetters([]), isEmpty);
    });

    test('single callout', () {
      final callouts = [
        const ImageCallout(reference: 'A', targets: [CalloutPoint(0.5, 0.5)]),
      ];
      expect(calloutLetters(callouts), {'A'});
    });

    test('multiple callouts', () {
      final callouts = [
        const ImageCallout(reference: 'A', targets: [CalloutPoint(0.5, 0.5)]),
        const ImageCallout(reference: 'B', targets: [CalloutPoint(0.3, 0.3)]),
      ];
      expect(calloutLetters(callouts), {'A', 'B'});
    });

    test('duplicates collapse into a set', () {
      final callouts = [
        const ImageCallout(reference: 'A', targets: [CalloutPoint(0.5, 0.5)]),
        const ImageCallout(reference: 'A', targets: [CalloutPoint(0.3, 0.3)]),
      ];
      expect(calloutLetters(callouts), {'A'});
    });
  });
}
