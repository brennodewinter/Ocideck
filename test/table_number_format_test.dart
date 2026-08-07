import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/table_number_format.dart';

void main() {
  group('formatTableCellNumber', () {
    test('formats integers with locale-specific grouping', () {
      expect(formatTableCellNumber('1234567', 'nl'), '1.234.567');
      expect(formatTableCellNumber('1234567', 'en'), '1,234,567');
    });

    test('formats decimals with locale-specific separators', () {
      expect(formatTableCellNumber('1234.5', 'nl'), '1.234,5');
      expect(formatTableCellNumber('1234.5', 'en'), '1,234.5');
    });

    test('leaves non-numbers unchanged', () {
      expect(formatTableCellNumber('hallo', 'nl'), 'hallo');
      expect(formatTableCellNumber('', 'nl'), '');
      expect(formatTableCellNumber('NVT', 'nl'), 'NVT');
    });

    test('leaves numbers unchanged when locale is empty', () {
      expect(formatTableCellNumber('1234.5', ''), '1234.5');
    });

    test('trims surrounding whitespace before parsing', () {
      expect(formatTableCellNumber('  1234  ', 'nl'), '1.234');
    });
  });

  group('isParseableNumber', () {
    test('true for integers and decimals', () {
      expect(isParseableNumber('42'), isTrue);
      expect(isParseableNumber('3.14'), isTrue);
      expect(isParseableNumber('  100  '), isTrue);
    });

    test('false for non-numbers and empty', () {
      expect(isParseableNumber(''), isFalse);
      expect(isParseableNumber('hallo'), isFalse);
      expect(isParseableNumber('NVT'), isFalse);
    });
  });
}
