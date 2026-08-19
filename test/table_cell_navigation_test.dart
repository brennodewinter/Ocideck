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
  group('tableArrowTarget', () {
    // #4: een pijltje in een tabelcel deed niets herkenbaars — het bewoog de
    // cursor binnen de cel en liep daarna dood. Een mens verwacht een
    // rekenblad: eerst door de tekst, dan naar de buurcel.
    //
    // #1565: en aan de rand van de tabel is "niets te doen" niet hetzelfde als
    // "binnen de cel". In de visuele documentmodus staat de cel in een
    // Quill-embed; een doorgelaten toets belandt daar bij de omliggende editor,
    // die er de cursor van het document mee verzet. Vandaar drie uitkomsten.
    ({TableArrowMove move, int row, int col, TableCaret caret}) move(
      TableArrow arrow, {
      int row = 1,
      int col = 1,
      bool atStart = false,
      bool atEnd = false,
      bool firstLine = true,
      bool lastLine = true,
    }) => tableArrowTarget(
      arrow: arrow,
      row: row,
      col: col,
      rowCount: 3,
      colCount: 3,
      atTextStart: atStart,
      atTextEnd: atEnd,
      onFirstLine: firstLine,
      onLastLine: lastLine,
    );

    test('midden in de tekst blijft de cursor in de cel', () {
      expect(move(TableArrow.left).move, TableArrowMove.inCell);
      expect(move(TableArrow.right).move, TableArrowMove.inCell);
    });

    test('aan de rand van de tekst springt hij naar de buurcel', () {
      expect(move(TableArrow.left, atStart: true), (
        move: TableArrowMove.toCell,
        row: 1,
        col: 0,
        caret: TableCaret.end,
      ));
      expect(move(TableArrow.right, atEnd: true), (
        move: TableArrowMove.toCell,
        row: 1,
        col: 2,
        caret: TableCaret.start,
      ));
    });

    test('op en neer gaan een rij, met de cel geselecteerd', () {
      expect(move(TableArrow.up), (
        move: TableArrowMove.toCell,
        row: 0,
        col: 1,
        caret: TableCaret.selectAll,
      ));
      expect(move(TableArrow.down), (
        move: TableArrowMove.toCell,
        row: 2,
        col: 1,
        caret: TableCaret.selectAll,
      ));
    });

    test('een meerregelige cel laat je er eerst doorheen lopen', () {
      expect(move(TableArrow.up, firstLine: false).move, TableArrowMove.inCell);
      expect(
        move(TableArrow.down, lastLine: false).move,
        TableArrowMove.inCell,
      );
    });

    test(
      'aan de rand van de tabel houdt de toets op — hij loopt niet door',
      () {
        for (final target in [
          move(TableArrow.left, col: 0, atStart: true),
          move(TableArrow.right, col: 2, atEnd: true),
          move(TableArrow.up, row: 0),
          move(TableArrow.down, row: 2),
        ]) {
          expect(target.move, TableArrowMove.atEdge);
        }
      },
    );
  });
}
