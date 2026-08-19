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

  test(
    'alleen een pagina die bij een vervolgblok begint krijgt een markering',
    () {
      final heights = [30.0, 40.0, 40.0, 20.0];
      final pageOffsets = documentPageOffsets(
        blockHeights: heights,
        pageHeight: pageHeight,
      );

      expect(pageOffsets, [0, 70]);
      expect(
        documentContinuationPages(
          blockHeights: heights,
          pageOffsets: pageOffsets,
          continuationBlocks: {2},
        ),
        {1},
      );
      expect(
        documentContinuationPageBlocks(
          blockHeights: heights,
          pageOffsets: pageOffsets,
          continuationBlocks: {2},
        ),
        {1: 2},
      );
      expect(
        documentContinuationPages(
          blockHeights: heights,
          pageOffsets: pageOffsets,
          continuationBlocks: {1, 3},
        ),
        isEmpty,
        reason: 'een vervolgblok midden op een vel opent geen vervolgpagina',
      );
    },
  );

  test('een blok hoger dan de pagina begint vers en loopt door', () {
    // 250 hoog vanaf 30: pagina's op 30, 130 en 230.
    expect(offsets([30, 250]), [0, 30, 130, 230]);
  });

  test('vervolgvellen midden in één hoge tijdlijnkaart zijn herkenbaar', () {
    final pageOffsets = offsets([30, 250]);

    expect(
      documentContinuationPages(
        blockHeights: const [30, 250],
        pageOffsets: pageOffsets,
        continuationBlocks: const {},
        continuableBlocks: const {1},
      ),
      {2, 3},
    );
    expect(
      documentContinuationPageBlocks(
        blockHeights: const [30, 250],
        pageOffsets: pageOffsets,
        continuationBlocks: const {},
        continuableBlocks: const {1},
      ),
      {2: 1, 3: 1},
    );
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

  group('een kop blijft niet alleen onderaan een vel', () {
    // De regel: onder een kop moet op hetzelfde vel nog minstens minKeepHeight
    // aan inhoud passen (twee regels bodytekst), anders schuift de kop mee.
    List<double> keep(
      List<double> heights,
      Set<int> headings, {
      double minKeep = 20,
      Set<int> forced = const {},
    }) => documentPageOffsets(
      blockHeights: heights,
      pageHeight: pageHeight,
      forcedBreakBefore: forced,
      keepWithNext: headings,
      minKeepHeight: minKeep,
    );

    test('een kop onderaan schuift mee met de tekst eronder', () {
      // 80 vol, dan een kop van 15 (past nog) en een alinea van 30 (past niet).
      // Zonder de regel bleef de kop op vel 1 achter; nu begint vel 2 bij de kop.
      expect(keep([80, 15, 30], {1}), [0, 80]);
      expect(
        documentPageOffsets(blockHeights: [80, 15, 30], pageHeight: pageHeight),
        [0, 95],
      );
    });

    test('één losse regel onder de kop is niet genoeg', () {
      // Kop op 70, een regel van 10 past nog (tot 95), maar daarna is het vel
      // vol: de kop houdt maar 10 aan inhoud vast en minKeep is 20.
      expect(keep([70, 15, 10, 30], {1}), [0, 70]);
    });

    test('twee regels onder de kop zijn genoeg', () {
      // Kop op 60: onder de kop passen twee regels van 10 op hetzelfde vel, en
      // dan blijft hij staan waar hij staat.
      expect(keep([60, 15, 10, 10], {1}), [0]);
    });

    test('een kop bovenaan een vel schuift nooit door', () {
      // Anders zou hij een leeg vel openen, en de volgende ronde weer. Het te
      // hoge blok eronder schuift aan in plaats van een vers vel te eisen, dus
      // de vensters lopen gewoon vanaf 0.
      expect(keep([15, 200], {0}), [0, 100, 200]);
    });

    test('twee koppen op elkaar reizen als groep', () {
      // 60 vol, dan H1 (15) + H2 (15) en tekst (30) die niet meer past: beide
      // koppen gaan mee, niet alleen de onderste.
      expect(keep([60, 15, 15, 30], {1, 2}), [0, 60]);
    });

    test('een te hoge tabel neemt de kop erboven mee', () {
      // 60 vol, kop van 15, dan een blok van 250 dat op geen vel past. Zonder
      // deze regel eiste dat blok een vers vel en bleef de kop alleen achter.
      expect(keep([60, 15, 250], {1}), [0, 60, 160, 260]);
    });

    test('een geforceerd einde direct onder de kop houdt niets vast', () {
      // De tekst achter de breuk staat op het volgende vel, dus de kop zou
      // alleen achterblijven en schuift mee.
      expect(keep([60, 15, 30], {1}, forced: {2}), [0, 60, 75]);
    });

    test('zonder minKeepHeight verandert er niets aan de oude uitkomst', () {
      expect(
        documentPageOffsets(
          blockHeights: [80, 15, 30],
          pageHeight: pageHeight,
          keepWithNext: {1},
        ),
        documentPageOffsets(blockHeights: [80, 15, 30], pageHeight: pageHeight),
      );
    });
  });

  group('ruimte voor de voetnoten onderaan het vel', () {
    // De noot staat onderaan de bladzijde, maar de ruimte hoort bij het blok
    // dat hem aanhaalt: schuift dat blok door, dan schuift de noot mee.
    test('een blok met een noot heeft minder ruimte op het vel', () {
      // 40 + 40 past normaal (test hierboven), maar met 30 aan noot onder het
      // eerste blok is er nog 30 over en schuift het tweede door.
      expect(
        documentPageOffsets(
          blockHeights: [40, 40],
          pageHeight: pageHeight,
          reservedRoom: [30, 0],
        ),
        [0, 40],
      );
    });

    test('op het volgende vel is de ruimte weer vrij', () {
      // De noot hangt aan blok 0 en dus aan vel 1. Op vel 2 passen blok 1 en 2
      // gewoon samen — was de reservering aan de pagina blijven plakken, dan
      // had blok 2 een derde vel geopend.
      expect(
        documentPageOffsets(
          blockHeights: [40, 40, 40],
          pageHeight: pageHeight,
          reservedRoom: [30, 0, 0],
        ),
        [0, 40],
      );
    });

    test('zonder noten verandert er niets', () {
      expect(
        documentPageOffsets(
          blockHeights: [40, 40, 40],
          pageHeight: pageHeight,
          reservedRoom: const [],
        ),
        documentPageOffsets(blockHeights: [40, 40, 40], pageHeight: pageHeight),
      );
    });

    test('een kop telt de noten van de tekst eronder mee', () {
      // 60 vol, kop van 15, tekst van 10 met een noot van 30: samen past dat
      // niet meer, dus de kop schuift mee in plaats van alleen achter te
      // blijven.
      expect(
        documentPageOffsets(
          blockHeights: [60, 15, 10],
          pageHeight: pageHeight,
          keepWithNext: {1},
          minKeepHeight: 8,
          reservedRoom: [0, 0, 30],
        ),
        [0, 60],
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
