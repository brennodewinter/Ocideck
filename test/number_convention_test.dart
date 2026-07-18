import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/number_convention.dart';

void main() {
  group('scanDecimalConvention — settled by evidence', () {
    test('a value carrying both marks settles it outright', () {
      expect(
        scanDecimalConvention(['1.234,56']).decided,
        DecimalConvention.comma,
      );
      expect(
        scanDecimalConvention(['1,234.56']).decided,
        DecimalConvention.dot,
      );
    });

    test('a group that is not three digits cannot be grouping', () {
      expect(scanDecimalConvention(['10,5']).decided, DecimalConvention.comma);
      expect(scanDecimalConvention(['10.5']).decided, DecimalConvention.dot);
    });

    test('a repeated mark can only be grouping', () {
      expect(
        scanDecimalConvention(['1,234,567']).decided,
        DecimalConvention.dot,
      );
      expect(
        scanDecimalConvention(['1.234.567']).decided,
        DecimalConvention.comma,
      );
    });

    test('one telling value settles the whole set', () {
      // This is the point of scanning the file rather than the cell: 1,234 on
      // its own says nothing, but its neighbour answers for it.
      final scan = scanDecimalConvention(['1,234', '10,5']);
      expect(scan.decided, DecimalConvention.comma);
      expect(scan.undecided, isEmpty);

      final other = scanDecimalConvention(['1,234', '10.5']);
      expect(other.decided, DecimalConvention.dot);
      expect(other.undecided, isEmpty);
    });
  });

  group('scanDecimalConvention — left to a human', () {
    test('only three-digit comma groups stays undecided', () {
      final scan = scanDecimalConvention(['1,234', '2,500', '12,000']);
      expect(scan.decided, isNull);
      expect(scan.undecided, ['1,234', '2,500', '12,000']);
    });

    test('a contradictory file is not resolved by majority', () {
      final scan = scanDecimalConvention(['10,5', '1,234,567']);
      expect(scan.decided, isNull);
    });

    test('a lone dot is never in doubt — the app writes its own CSV so', () {
      final scan = scanDecimalConvention(['1.234', '7']);
      expect(scan.decided, isNull);
      expect(scan.undecided, isEmpty, reason: 'no question is asked about it');
    });

    test('values without any mark raise nothing', () {
      final scan = scanDecimalConvention(['10', '12', '7']);
      expect(scan.decided, isNull);
      expect(scan.undecided, isEmpty);
    });

    test('non-numeric values carry no evidence and are not asked about', () {
      final scan = scanDecimalConvention(['12%', '€ 1.000', 'oops']);
      expect(scan.decided, isNull);
      expect(scan.undecided, isEmpty);
    });
  });

  group('parseNumberUnder', () {
    test('reads a grouped number under each convention', () {
      expect(parseNumberUnder('1.234,56', DecimalConvention.comma), 1234.56);
      expect(parseNumberUnder('1,234.56', DecimalConvention.dot), 1234.56);
    });

    test('resolves the ambiguous value both ways', () {
      expect(parseNumberUnder('1,234', DecimalConvention.dot), 1234);
      expect(parseNumberUnder('1,234', DecimalConvention.comma), 1.234);
    });

    test('plain values are untouched by either convention', () {
      expect(parseNumberUnder('7', DecimalConvention.comma), 7);
      expect(parseNumberUnder('7', DecimalConvention.dot), 7);
      expect(parseNumberUnder('-3', DecimalConvention.comma), -3);
    });

    test('non-numeric shapes fall through to Dart parsing', () {
      expect(parseNumberUnder('1e3', DecimalConvention.dot), 1000);
      expect(parseNumberUnder('12%', DecimalConvention.dot), isNull);
      expect(parseNumberUnder('oops', DecimalConvention.comma), isNull);
    });
  });
}
