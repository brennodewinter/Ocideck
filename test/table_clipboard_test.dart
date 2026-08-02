import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/table_clipboard.dart';

void main() {
  group('parseClipboardTable', () {
    test('parses a spreadsheet (TSV) selection', () {
      expect(parseClipboardTable('Naam\tScore\nJan\t8\nPiet\t9'), [
        ['Naam', 'Score'],
        ['Jan', '8'],
        ['Piet', '9'],
      ]);
    });

    test('handles Windows line endings and the trailing newline', () {
      expect(parseClipboardTable('a\tb\r\nc\td\r\n'), [
        ['a', 'b'],
        ['c', 'd'],
      ]);
    });

    test('a single spreadsheet row is still a table', () {
      expect(parseClipboardTable('a\tb\tc'), [
        ['a', 'b', 'c'],
      ]);
    });

    test('pads ragged rows to a rectangle', () {
      expect(parseClipboardTable('a\tb\tc\nd\te'), [
        ['a', 'b', 'c'],
        ['d', 'e', ''],
      ]);
    });

    test('quoted cells may contain delimiters and newlines', () {
      expect(parseClipboardTable('"regel 1\nregel 2"\t"met\ttab"\nx\ty'), [
        ['regel 1\nregel 2', 'met\ttab'],
        ['x', 'y'],
      ]);
      expect(parseClipboardTable('"a ""quote"""\tb'), [
        ['a "quote"', 'b'],
      ]);
    });

    test('a space before the opening quote no longer breaks the cell', () {
      // The clipboard used to run its own splitter, which only opened a quoted
      // field when the cell was still empty — so this split on the inner comma.
      // Sharing the file reader's scan fixed that along the way.
      expect(parseClipboardTable('Plaats, Aantal\n "Amsterdam, NL", 3'), [
        ['Plaats', ' Aantal'],
        ['Amsterdam, NL', ' 3'],
      ]);
    });

    test('a quote inside a cell is still literal, not an opener', () {
      expect(parseClipboardTable('maat\tlengte\n5" pijp\t2'), [
        ['maat', 'lengte'],
        ['5" pijp', '2'],
      ]);
    });

    test('parses comma and semicolon CSV with consistent columns', () {
      expect(parseClipboardTable('Naam,Score\nJan,8'), [
        ['Naam', 'Score'],
        ['Jan', '8'],
      ]);
      expect(parseClipboardTable('Naam;Score\nJan;8'), [
        ['Naam', 'Score'],
        ['Jan', '8'],
      ]);
    });

    test('prefers the semicolon when commas are decimal separators', () {
      expect(parseClipboardTable('Prijs;Marge\n1,50;0,25\n2,00;0,30'), [
        ['Prijs', 'Marge'],
        ['1,50', '0,25'],
        ['2,00', '0,30'],
      ]);
    });

    test('parses a markdown table and drops the separator row', () {
      expect(parseClipboardTable('| Naam | Score |\n|---|---:|\n| Jan | 8 |'), [
        ['Naam', 'Score'],
        ['Jan', '8'],
      ]);
    });

    test('drops a GFM separator row with a single dash per cell', () {
      // GFM allows a single dash per cell. The clipboard path required
      // at least two dashes (`-{2,}`), so `| - | - |` was read as data
      // instead of a separator — inconsistent with markdown_table_codec.dart
      // which uses `-+`.
      expect(parseClipboardTable('| A | B |\n| - | - |\n| 1 | 2 |'), [
        ['A', 'B'],
        ['1', '2'],
      ]);
    });

    test('plain text is not a table', () {
      expect(parseClipboardTable('gewoon wat tekst'), isNull);
      expect(parseClipboardTable('regel een\nregel twee'), isNull);
      // A sentence with a comma stays a sentence.
      expect(parseClipboardTable('hallo, wereld'), isNull);
      // Inconsistent comma counts: prose, not CSV.
      expect(parseClipboardTable('een, twee en drie\nvier, vijf, zes'), isNull);
      expect(parseClipboardTable('   '), isNull);
    });
  });
}
