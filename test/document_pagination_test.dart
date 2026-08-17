import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/document_pagination.dart';

/// Het verdelen van een doorlopend document over pagina's, op gemeten
/// blokhoogtes. De regel die het meeste uitmaakt: een blok dat nog op een
/// pagina past wordt niet doormidden gesneden.
void main() {
  const pageHeight = 100.0;

  List<double> offsets(List<double> heights) =>
      documentPageOffsets(blockHeights: heights, pageHeight: pageHeight);

  test('een document dat op één pagina past levert één pagina', () {
    expect(offsets([30, 30, 30]), [0]);
  });

  test('een blok dat er niet meer bij past schuift heel door', () {
    // 40 + 40 = 80 past; het derde blok zou tot 120 lopen, dus begint pagina 2
    // bij 80 — precies bij de bovenkant van dat blok, niet op 100.
    expect(offsets([40, 40, 40]), [0, 80]);
  });

  test('een blok dat exact volmaakt houdt de pagina heel', () {
    expect(offsets([50, 50, 10]), [0, 100]);
  });

  test('een blok hoger dan de pagina begint vers en loopt door', () {
    // 250 hoog vanaf 30: pagina's op 30, 130 en 230.
    expect(offsets([30, 250]), [0, 30, 130, 230]);
  });

  test('na een te hoog blok begint het volgende blok op een verse pagina', () {
    final result = offsets([30, 250, 20]);
    expect(result, [0, 30, 130, 230, 280]);
  });

  test('een leeg document is een lege pagina, geen nul pagina\'s', () {
    expect(offsets(const []), [0]);
  });

  test('een onzinnige paginahoogte levert geen eindeloze lijst', () {
    expect(documentPageOffsets(blockHeights: [10, 10], pageHeight: 0), [0]);
  });

  group('geforceerde einden', () {
    // Het formaat kent ze al: een `---` in de body is een pagina-einde, en de
    // hoofdstuk-instelling doet hetzelfde voor elke H1 (FILE_FORMAT.md §14.6).
    // De export honoreert beide; de weergave hoort dat ook te doen.
    test(
      'een geforceerd einde begint een verse pagina, ook met ruimte over',
      () {
        expect(
          documentPageOffsets(
            blockHeights: [20, 20, 20],
            pageHeight: 100,
            forcedBreakBefore: {2},
          ),
          [0, 40],
        );
      },
    );

    test('een geforceerd einde bovenaan een vel levert geen leeg vel op', () {
      // Blok 0 staat al bovenaan pagina 1; nog een breuk zou een leeg vel geven.
      expect(
        documentPageOffsets(
          blockHeights: [20, 20],
          pageHeight: 100,
          forcedBreakBefore: {0},
        ),
        [0],
      );
      // En twee breuken achter elkaar leveren één nieuw vel op, geen twee.
      expect(
        documentPageOffsets(
          blockHeights: [20, 20, 20],
          pageHeight: 100,
          forcedBreakBefore: {1, 2},
        ),
        [0, 20, 40],
      );
    });

    test('zonder geforceerde einden verandert er niets', () {
      expect(
        documentPageOffsets(blockHeights: [40, 40, 40], pageHeight: 100),
        documentPageOffsets(
          blockHeights: [40, 40, 40],
          pageHeight: 100,
          forcedBreakBefore: const {},
        ),
      );
    });
  });

  test('het aantal pagina\'s telt de vensters', () {
    expect(
      documentPageCount(blockHeights: [40, 40, 40], pageHeight: pageHeight),
      2,
    );
  });
}
