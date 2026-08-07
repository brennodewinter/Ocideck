import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_blocks.dart';

/// De gedeelde GFM-tabel- en ` ```chart `-primitieven (`markdown_blocks.dart`):
/// één bron voor de weergave, de editor, de deck-bridge, de HTML-export en de
/// grafiek-hydratie. Deze test legt hun contract vast, los van al die callers.
void main() {
  group('looksLikeTableRow', () {
    test('een regel die (na trimmen) met | begint én een | bevat', () {
      expect(looksLikeTableRow('| a | b |'), isTrue);
      expect(looksLikeTableRow('   | a |  '), isTrue); // trimt intern
    });
    test('geen pijp-rij', () {
      expect(looksLikeTableRow('gewone tekst'), isFalse);
      expect(looksLikeTableRow('a | b'), isFalse); // begint niet met |
      expect(looksLikeTableRow(''), isFalse);
    });
  });

  group('isTableDelimiter', () {
    test('de scheidingsrij onder een kop', () {
      expect(isTableDelimiter('| --- | --- |'), isTrue);
      expect(isTableDelimiter('|:--|--:|'), isTrue);
      expect(isTableDelimiter('  | - | - |  '), isTrue);
    });
    test('een gewone rij of tekst is geen scheidingsrij', () {
      expect(isTableDelimiter('| Naam | BSN |'), isFalse); // geen streepjes
      expect(isTableDelimiter('geen tabel'), isFalse);
    });
  });

  group('splitTableRow', () {
    test('splitst op onontsnapte pijp en trimt de cellen', () {
      expect(splitTableRow('| a | b | c |'), ['a', 'b', 'c']);
    });
    test('een ontsnapte pijp blijft als \\| in de cel', () {
      expect(splitTableRow(r'| a\|b | c |'), [r'a\|b', 'c']);
    });
  });

  test('gfmTableCells ontsnapt de pijp-escape weg', () {
    expect(gfmTableCells([r'| a\|b | c |', '| d | e |']), [
      ['a|b', 'c'],
      ['d', 'e'],
    ]);
  });

  group('rowsToGfmTable', () {
    test('kop, scheiding, body', () {
      expect(
        rowsToGfmTable([
          ['H1', 'H2'],
          ['1', '2'],
        ]),
        '| H1 | H2 |\n| --- | --- |\n| 1 | 2 |',
      );
    });
    test('leeg raster geeft lege tekst', () {
      expect(rowsToGfmTable(const []), '');
    });
    test('pijp in cel ontsnapt, ragged rij aangevuld', () {
      final out = rowsToGfmTable([
        ['a|b', 'c', 'd'],
        ['x'],
      ]);
      expect(out.split('\n').first, r'| a\|b | c | d |');
      expect(out.split('\n').last, '| x |  |  |');
    });
    test('splitTableRow en rowsToGfmTable zijn elkaars omgekeerde', () {
      const line = '| Naam | Waarde |';
      expect(rowsToGfmTable([splitTableRow(line)]).split('\n').first, line);
    });
  });

  group('chartFencePattern', () {
    test('vangt een ```chart-blok en levert de kale spec in groep 1', () {
      final m = chartFencePattern.firstMatch('# K\n\n```chart\nSPEC\n```\n');
      expect(m, isNotNull);
      expect(m!.group(1), 'SPEC');
    });
    test('telt meerdere blokken', () {
      const src = '```chart\nA\n```\n\ntekst\n\n```chart\nB\n```\n';
      final specs = chartFencePattern
          .allMatches(src)
          .map((m) => m.group(1))
          .toList();
      expect(specs, ['A', 'B']);
    });
  });
}
