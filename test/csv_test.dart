import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/csv.dart';

void main() {
  group('parseCsvRows', () {
    test('a quoted field may contain a line break', () {
      // The reason this function exists: MITRE's CWE export wraps multi-line
      // descriptions in quotes, and tool/build_cwe_catalog.dart reads it.
      final rows = parseCsvRows('id,omschrijving\n1,"regel een\nregel twee"');
      expect(rows.length, 2);
      expect(rows[1], ['1', 'regel een\nregel twee']);
    });

    test('a quoted field may contain the delimiter', () {
      expect(parseCsvRows('a,"b,c",d').single, ['a', 'b,c', 'd']);
    });

    test('a doubled "" is one literal quote', () {
      expect(parseCsvRows('"zeg ""hoi""",1').single, ['zeg "hoi"', '1']);
    });

    test('unquoted fields are verbatim unless asked to trim', () {
      expect(parseCsvRows(' a , b ').single, [' a ', ' b ']);
      expect(parseCsvRows(' a , b ', trimUnquoted: true).single, ['a', 'b']);
    });

    test('a quoted field keeps its inner spaces even when trimming', () {
      expect(parseCsvRows('" a ",b', trimUnquoted: true).single, [' a ', 'b']);
    });

    test('a trailing line break adds no empty row', () {
      expect(parseCsvRows('a,b\nc,d\n').length, 2);
    });

    test('CRLF is normalised', () {
      expect(parseCsvRows('a,b\r\nc,d').length, 2);
      expect(parseCsvRows('a,b\r\nc,d')[1], ['c', 'd']);
    });

    test('empty input yields no rows at all', () {
      expect(parseCsvRows(''), isEmpty);
    });

    test('an unterminated quote runs to the end of the text', () {
      // Documented leniency, and the very reason parseCsvLine exists: over a
      // whole document a stray quote swallows everything after it.
      final rows = parseCsvRows('a,"b\nc,d');
      expect(rows.single, ['a', 'b\nc,d']);
    });

    test('another delimiter can be given', () {
      expect(parseCsvRows('a;b;c', delimiter: ';').single, ['a', 'b', 'c']);
      expect(parseCsvRows('a\tb', delimiter: '\t').single, ['a', 'b']);
    });
  });

  group('parseCsvLine', () {
    test('splitting first contains a stray quote to that line', () {
      // Same input as the parseCsvRows case above, but line by line: the
      // damage stops at the end of the broken line instead of eating the rest.
      expect(parseCsvLine('a,"b'), ['a', 'b']);
      expect(parseCsvLine('c,d'), ['c', 'd']);
    });

    test('trims unquoted cells by default', () {
      expect(parseCsvLine(' a , b '), ['a', 'b']);
    });

    test('an empty line is one empty cell, not zero cells', () {
      expect(parseCsvLine(''), ['']);
    });

    test('shares the quoting rules with parseCsvRows', () {
      expect(parseCsvLine('"Amsterdam, NL",10'), ['Amsterdam, NL', '10']);
      expect(parseCsvLine('"zeg ""hoi""",1'), ['zeg "hoi"', '1']);
    });
  });
}
