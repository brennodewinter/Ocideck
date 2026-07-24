import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/table_layout_metrics.dart';
import 'package:ocideck/services/text_measurement.dart';

/// De tabel van het OpenKAT-managementoverzicht: één brede tekstkolom naast
/// vier korte, met koppen die langer zijn dan hun inhoud.
const _openkatRows = <List<String>>[
  ['#', 'Finding', 'Ernst', 'Systemen', 'Orgs'],
  ['1', 'SSL/TLS Certificate expired', 'critical', '6', '1'],
  ['2', 'Unencrypted website traffic', 'high', '31', '1'],
  ['3', 'Open database port(s) detected', 'high', '3', '1'],
  ['4', 'Uncommon open port(s) detected', 'medium', '34', '1'],
  ['5', 'Missing Content Security Policy (CSP) header', 'medium', '31', '3'],
];

const _tableWidth = 1126.0;
const _cellSize = 18.0;
const _font = 'Roboto';

double _headerNeed(String header) =>
    measureTextWordWidth(header, _cellSize, bold: true, fontFamily: _font) +
    _cellSize * kTableCellHPadFactor * 2;

List<double> _widths(List<List<String>> rows, int colCount) =>
    tableColumnWidths(
      rows: rows,
      colCount: colCount,
      tableWidth: _tableWidth,
      cellSize: _cellSize,
      font: _font,
    );

void main() {
  group('tableColumnWidths', () {
    // De bevinding: op tekenaantal verdeeld kreeg "Orgs" (4 tekens) minder
    // ruimte dan het woord breed is, brak de kop letter voor letter af, en zakte
    // de kolom onder haar eigen celmarge — waarna de tekst dwars over de
    // tabellijnen werd getekend.
    test('every column fits its own header word plus the cell padding', () {
      final widths = _widths(_openkatRows, 5);
      for (var c = 0; c < 5; c++) {
        expect(
          widths[c],
          greaterThanOrEqualTo(_headerNeed(_openkatRows.first[c])),
          reason: 'kolom "${_openkatRows.first[c]}" is te smal voor haar kop',
        );
      }
    });

    test('the columns together are exactly the table width', () {
      final widths = _widths(_openkatRows, 5);
      expect(
        widths.fold<double>(0, (a, b) => a + b),
        closeTo(_tableWidth, 1e-6),
      );
    });

    test('the text-heavy column still claims the largest share', () {
      final widths = _widths(_openkatRows, 5);
      expect(widths[1], greaterThan(widths[0]));
      expect(widths[1], greaterThan(widths[2]));
      expect(widths[1], greaterThan(widths[3]));
      expect(widths[1], greaterThan(widths[4]));
    });

    // Een rangnummerkolom hoort smal te blijven; ze werd een kwart slide breed
    // toen het "N van totaal"-bijschrift nog als inhoud van kolom 0 meetelde.
    test('a rank column stays narrow next to a wide text column', () {
      final widths = _widths(_openkatRows, 5);
      expect(widths[0], lessThan(_tableWidth * 0.1));
    });

    test('a header wider than the table is scaled back, never overflowed', () {
      final rows = <List<String>>[
        ['Onverbrekelijkwoordvanabsurdelengtezonderenkelespatie' * 3, 'B'],
        ['x', 'y'],
      ];
      final widths = _widths(rows, 2);
      expect(
        widths.fold<double>(0, (a, b) => a + b),
        lessThanOrEqualTo(_tableWidth + 1e-6),
      );
    });

    test('a table without rows or columns yields no widths', () {
      expect(_widths(const [], 0), isEmpty);
      expect(
        tableColumnWidths(
          rows: _openkatRows,
          colCount: 5,
          tableWidth: 0,
          cellSize: _cellSize,
          font: _font,
        ),
        hasLength(5),
      );
    });

    // Een lege kop mag de kolom niet tot nul knijpen: onder de celmarge tekent
    // de inhoud buiten haar eigen cel.
    test('an empty header still leaves room for a character', () {
      final widths = _widths(const [
        ['', 'Naam'],
        ['1', 'Aap'],
      ], 2);
      expect(widths[0], greaterThan(_cellSize * kTableCellHPadFactor * 2));
    });
  });

  group('tableBlockHeight', () {
    test('grows with the number of rows', () {
      double heightOf(List<List<String>> rows) => tableBlockHeight(
        rows: rows,
        colCount: 5,
        tableWidth: _tableWidth,
        cellSize: _cellSize,
        font: _font,
      );
      expect(
        heightOf(_openkatRows),
        greaterThan(heightOf(_openkatRows.sublist(0, 3))),
      );
    });
  });
}
