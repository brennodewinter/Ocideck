import 'package:ocideck_form_core/src/form_rule_values.dart';
import 'package:test/test.dart';

void main() {
  group('parseRuleInt', () {
    test('plain digits only', () {
      expect(parseRuleInt('0'), 0);
      expect(parseRuleInt('80'), 80);
      expect(parseRuleInt('007'), 7);
      expect(parseRuleInt('999999999999'), 999999999999);
    });

    test('everything else is null', () {
      for (final bad in [
        '',
        ' 1',
        '1 ',
        '-1',
        '+1',
        '1.0',
        '1,0',
        '0x10',
        '1e3',
        '1_000',
        '9999999999999', // 13 digits: not exact on every platform
        'a',
        '١', // an Arabic-Indic digit is not an ASCII digit
      ]) {
        expect(parseRuleInt(bad), isNull, reason: '"$bad"');
      }
    });
  });

  group('parseRuleRange (FORM_INTAKE.md §4.7)', () {
    test('the four well-formed shapes', () {
      final exact = parseRuleRange('5')!;
      expect((exact.min, exact.max), (5, 5));
      final between = parseRuleRange('150..300')!;
      expect((between.min, between.max), (150, 300));
      final atLeast = parseRuleRange('150..')!;
      expect((atLeast.min, atLeast.max), (150, null));
      final atMost = parseRuleRange('..100')!;
      expect((atMost.min, atMost.max), (null, 100));
    });

    test('equal ends and zero are fine', () {
      expect(parseRuleRange('3..3'), isNotNull);
      expect(parseRuleRange('0..0'), isNotNull);
      expect(parseRuleRange('..0'), isNotNull);
    });

    test('the malformed ones from the design are all refused', () {
      for (final bad in [
        '150-300', // a hyphen is not the range operator
        '150…300', // a typographic ellipsis
        '300..150', // reversed
        '..', // nothing at all
        '-5..',
        '..-5',
        '1...3',
        '1 ..3',
        '1.. 3',
        ' 1..3',
        '1..3 ',
        '',
        'a..b',
        '1..b',
        '1.5..2',
        '1,5',
        '1..2..3',
      ]) {
        expect(parseRuleRange(bad), isNull, reason: '"$bad"');
      }
    });

    test('contains is inclusive at both ends', () {
      final r = parseRuleRange('150..300')!;
      expect(r.contains(149), isFalse);
      expect(r.contains(150), isTrue);
      expect(r.contains(300), isTrue);
      expect(r.contains(301), isFalse);
      expect(parseRuleRange('..100')!.contains(0), isTrue);
      expect(parseRuleRange('..100')!.contains(101), isFalse);
      expect(parseRuleRange('5..')!.contains(4), isFalse);
      expect(parseRuleRange('5..')!.contains(999999), isTrue);
      expect(parseRuleRange('5')!.contains(5), isTrue);
      expect(parseRuleRange('5')!.contains(6), isFalse);
    });

    test('toString writes the canonical form back', () {
      for (final s in ['5', '150..300', '150..', '..100']) {
        // `5` is stored as 5..5, and a point range prints as the point.
        expect(parseRuleRange(s)!.toString(), s);
      }
    });
  });

  group('isValidNumberText (§4.7)', () {
    test('digits with one optional . or , and an optional leading minus', () {
      for (final ok in [
        '0',
        '25',
        '-3',
        '2,5',
        '2.5',
        '-0,5',
        '007',
        '0.000001',
      ]) {
        expect(isValidNumberText(ok), isTrue, reason: ok);
      }
    });

    test(
      'hex, exponent, spaces, a bare or double mark and overflow are not',
      () {
        for (final bad in [
          '',
          '0x10',
          '1e2',
          '1E2',
          ' 25',
          '25 ',
          '2 5',
          '.5',
          '5.',
          ',5',
          '5,',
          '1,2,3',
          '1.2.3',
          '1.2,3',
          '--1',
          '+1',
          '-',
          '1_000',
          '1234567890123456', // 16 digits
          'NaN',
          'Infinity',
        ]) {
          expect(isValidNumberText(bad), isFalse, reason: '"$bad"');
        }
      },
    );

    test('fifteen digits are the limit, counting the fraction', () {
      expect(isValidNumberText('123456789012345'), isTrue);
      expect(isValidNumberText('1234567.12345678'), isTrue);
      expect(isValidNumberText('1234567.123456789'), isFalse);
    });
  });

  group('compareNumberText', () {
    test('orders by value, not by text, and treats , like .', () {
      expect(compareNumberText('2', '10'), lessThan(0));
      expect(compareNumberText('10', '2'), greaterThan(0));
      expect(compareNumberText('2,5', '2.5'), 0);
      expect(compareNumberText('2.50', '2.5'), 0);
      expect(compareNumberText('-1', '1'), lessThan(0));
      expect(compareNumberText('-2', '-10'), greaterThan(0));
      expect(compareNumberText('0.1', '0.09'), greaterThan(0));
      expect(compareNumberText('-0', '0'), 0);
      expect(compareNumberText('007', '7'), 0);
    });
  });

  group('isMultipleOfStep', () {
    test('exact decimal arithmetic, counted from the base', () {
      expect(
        isMultipleOfStep('0,3', '0', '0,1'),
        isTrue,
        reason: 'not so in doubles',
      );
      expect(isMultipleOfStep('0.35', '0', '0.1'), isFalse);
      expect(isMultipleOfStep('5', '1', '2'), isTrue);
      expect(isMultipleOfStep('4', '1', '2'), isFalse);
      expect(
        isMultipleOfStep('1', '1', '2'),
        isTrue,
        reason: 'the base itself',
      );
      expect(isMultipleOfStep('-10', '0', '5'), isTrue);
      expect(isMultipleOfStep('-12', '0', '5'), isFalse);
      expect(
        isMultipleOfStep('-1', '1', '2'),
        isTrue,
        reason: 'below the base',
      );
      expect(isMultipleOfStep('0', '0', '7'), isTrue);
      expect(isMultipleOfStep('1,5', '0,5', '0,5'), isTrue);
      expect(isMultipleOfStep('0,0000001', '0', '0,0000001'), isTrue);
    });
  });

  group('isValidCalendarDate (§4.7)', () {
    test('real dates in the canonical shape', () {
      for (final ok in [
        '2026-11-01',
        '2024-02-29',
        '2000-02-29',
        '1999-12-31',
        '0001-01-01',
        '9999-12-31',
      ]) {
        expect(isValidCalendarDate(ok), isTrue, reason: ok);
      }
    });

    test('impossible dates and every non-canonical spelling are refused', () {
      for (final bad in [
        '2026-02-30',
        '2026-02-29',
        '1900-02-29', // 1900 is not a leap year
        '2026-13-01',
        '2026-00-10',
        '2026-04-31',
        '2026-01-00',
        '0000-01-01',
        '20261101',
        '+2026-11-01',
        '2026-1-1',
        '26-11-01',
        '2026/11/01',
        '2026-11-01 ',
        ' 2026-11-01',
        '2026-11-01T00:00',
        '',
      ]) {
        expect(isValidCalendarDate(bad), isFalse, reason: '"$bad"');
      }
    });
  });

  group('parseRuleList', () {
    test('splits on the separator and trims each item', () {
      expect(parseRuleList('A|B|C', '|').items, ['A', 'B', 'C']);
      expect(parseRuleList('Quick Fix | Zoet ', '|').items, [
        'Quick Fix',
        'Zoet',
      ]);
      expect(parseRuleList('only', '|').items, ['only']);
      expect(parseRuleList('a,b', ',').items, ['a', 'b']);
    });

    test('an empty item or a duplicate is an error with a reason', () {
      expect(parseRuleList('A||B', '|').error, 'empty-item');
      expect(parseRuleList('|A', '|').error, 'empty-item');
      expect(parseRuleList('A|', '|').error, 'empty-item');
      expect(parseRuleList('A| |B', '|').error, 'empty-item');
      expect(parseRuleList('', '|').error, 'empty-item');
      expect(parseRuleList('A|B|A', '|').error, 'duplicate-item');
      expect(parseRuleList('A| A', '|').error, 'duplicate-item');
    });

    test('duplicates are case-sensitive', () {
      expect(parseRuleList('a|A', '|').items, ['a', 'A']);
    });
  });
}
