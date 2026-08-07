import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/utils/table_pagination.dart';

void main() {
  group('splitTableSlidePages', () {
    test('returns null for a table that fits on one page', () {
      final slide = Slide.create(SlideType.table).copyWith(
        tableRows: [
          ['Kop', 'Waarde'],
          ['A', '1'],
          ['B', '2'],
        ],
      );
      expect(splitTableSlidePages(slide), isNull);
    });

    test('returns null for a header-only table', () {
      final slide = Slide.create(SlideType.table).copyWith(
        tableRows: [
          ['Kop', 'Waarde'],
        ],
      );
      expect(splitTableSlidePages(slide), isNull);
    });

    test('returns null for a non-table slide', () {
      final slide = Slide.create(SlideType.bullets);
      expect(splitTableSlidePages(slide), isNull);
    });

    test('splits a long table into pages with the header repeated', () {
      final rows = [
        ['Kop', 'Waarde'],
        for (var i = 1; i <= 25; i++) ['Rij $i', '$i'],
      ];
      final slide = Slide.create(SlideType.table).copyWith(tableRows: rows);
      final pages = splitTableSlidePages(slide);

      expect(pages, isNotNull);
      expect(pages!.length, 3); // 12 + 12 + 1 = 25 data rows → 3 pages

      // Elke pagina begint met de koprij.
      for (final page in pages) {
        expect(page.tableRows.first, ['Kop', 'Waarde']);
      }

      // Pagina 1: 12 data-rijen, pagina 2: 12, pagina 3: 1.
      expect(pages[0].tableRows.length, 13); // kop + 12
      expect(pages[1].tableRows.length, 13);
      expect(pages[2].tableRows.length, 2); // kop + 1

      // De eerste pagina erft de oorspronkelijke slide; vervolgpagina's
      // hebben continuesSplit: true.
      expect(pages[0].continuesSplit, slide.continuesSplit);
      expect(pages[1].continuesSplit, isTrue);
      expect(pages[2].continuesSplit, isTrue);
    });

    test('respects a custom rowsPerPage', () {
      final rows = [
        ['Kop', 'Waarde'],
        for (var i = 1; i <= 10; i++) ['Rij $i', '$i'],
      ];
      final slide = Slide.create(SlideType.table).copyWith(tableRows: rows);
      final pages = splitTableSlidePages(slide, rowsPerPage: 4);

      expect(pages, isNotNull);
      expect(pages!.length, 3); // 4 + 4 + 2 = 10 data rows → 3 pages
      expect(pages[0].tableRows.length, 5); // kop + 4
      expect(pages[1].tableRows.length, 5);
      expect(pages[2].tableRows.length, 3); // kop + 2
    });
  });
}
