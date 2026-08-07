import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/table_cell_navigation.dart';

void main() {
  group('nextTableCell', () {
    test('moves right within a row', () {
      expect(nextTableCell(0, 0, 3, 3), (row: 0, col: 1));
      expect(nextTableCell(0, 1, 3, 3), (row: 0, col: 2));
    });

    test('wraps to the first cell of the next row', () {
      expect(nextTableCell(0, 2, 3, 3), (row: 1, col: 0));
      expect(nextTableCell(1, 2, 3, 3), (row: 2, col: 0));
    });

    test('returns null on the last cell — signal to add a row', () {
      expect(nextTableCell(2, 2, 3, 3), isNull);
    });

    test('single cell grid returns null immediately', () {
      expect(nextTableCell(0, 0, 1, 1), isNull);
    });
  });

  group('prevTableCell', () {
    test('moves left within a row', () {
      expect(prevTableCell(0, 2, 3), (row: 0, col: 1));
      expect(prevTableCell(0, 1, 3), (row: 0, col: 0));
    });

    test('wraps to the last cell of the previous row', () {
      expect(prevTableCell(1, 0, 3), (row: 0, col: 2));
      expect(prevTableCell(2, 0, 3), (row: 1, col: 2));
    });

    test('returns null at the first cell — no wrapping past the start', () {
      expect(prevTableCell(0, 0, 3), isNull);
    });
  });
}
