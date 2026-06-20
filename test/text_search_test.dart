import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/text_search.dart';

void main() {
  group('findAllMatches', () {
    test('finds all non-overlapping matches', () {
      final matches = findAllMatches('foo bar foo', 'foo');
      expect(matches, [
        const TextMatchRange(0, 3),
        const TextMatchRange(8, 11),
      ]);
    });

    test('returns empty list for empty query', () {
      expect(findAllMatches('hello', ''), isEmpty);
    });

    test('is case insensitive by default', () {
      final matches = findAllMatches('Hello hello', 'hello');
      expect(matches.length, 2);
    });

    test('respects case sensitivity', () {
      final matches = findAllMatches(
        'Hello hello',
        'hello',
        caseSensitive: true,
      );
      expect(matches, [const TextMatchRange(6, 11)]);
    });
  });

  group('nextMatchIndex', () {
    test('wraps around by default', () {
      expect(nextMatchIndex(2, 3), 0);
    });

    test('returns -1 when there are no matches', () {
      expect(nextMatchIndex(-1, 0), -1);
    });

    test('does not wrap when disabled', () {
      expect(nextMatchIndex(2, 3, wrap: false), 2);
    });
  });

  group('previousMatchIndex', () {
    test('wraps around by default', () {
      expect(previousMatchIndex(0, 3), 2);
    });

    test('returns -1 when there are no matches', () {
      expect(previousMatchIndex(0, 0), -1);
    });
  });

  group('replaceRange', () {
    test('replaces the given range', () {
      expect(
        replaceRange('hello world', const TextMatchRange(6, 11), 'dart'),
        'hello dart',
      );
    });
  });

  group('replaceAllInText', () {
    test('replaces all occurrences', () {
      final result = replaceAllInText('foo bar foo', 'foo', 'baz');
      expect(result.text, 'baz bar baz');
      expect(result.count, 2);
    });

    test('returns zero replacements for empty query', () {
      final result = replaceAllInText('hello', '', 'x');
      expect(result.text, 'hello');
      expect(result.count, 0);
    });
  });
}
