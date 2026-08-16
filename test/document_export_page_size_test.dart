import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/services/latex/latex_preamble.dart';
import 'package:ocideck/services/export_metadata.dart';

/// Feature 3: de paginamaat en marges komen terecht in de LaTeX-preamble
/// (`\documentclass` + `\usepackage[…]{geometry}`) en in de HTML `@page`-CSS.
void main() {
  group('articlePreamble — paginamaat en marges', () {
    test('A4 portret met standaardmarges', () {
      const meta = ExportDocumentMetadata(title: 'Test');
      final preamble = articlePreamble(meta);
      expect(preamble, contains('a4paper'));
      expect(preamble, contains('geometry'));
      // Eén standaard voor alle uitvoervormen: de preamble-default moet
      // letterlijk die van PageMargins zijn. Stond hier eerder 25mm rondom
      // hardgecodeerd, terwijl de export zelf `const PageMargins()`
      // doorgeeft — de test dekte dan een marge die niemand ooit kreeg.
      expect(preamble, contains(const PageMargins().latexMargin));
      expect(preamble, contains('top=25mm'));
      expect(preamble, contains('left=20mm'));
    });

    test('A3 landscape met aangepaste marges', () {
      const meta = ExportDocumentMetadata(title: 'Test');
      const spec = PageSizeSpec(
        series: PaperSeries.a,
        number: 3,
        landscape: true,
      );
      const margins = PageMargins(
        topMm: 30,
        bottomMm: 30,
        leftMm: 25,
        rightMm: 25,
      );
      final preamble = articlePreamble(
        meta,
        pageSize: spec,
        pageMargins: margins,
      );
      expect(preamble, contains('a3paper,landscape'));
      expect(preamble, contains('top=30mm'));
      expect(preamble, contains('left=25mm'));
    });

    test('B5 met uniforme 15mm marges', () {
      const meta = ExportDocumentMetadata(title: 'Test');
      const spec = PageSizeSpec(series: PaperSeries.b, number: 5);
      final preamble = articlePreamble(
        meta,
        pageSize: spec,
        pageMargins: const PageMargins.uniform(15),
      );
      expect(preamble, contains('b5paper'));
      expect(preamble, contains('top=15mm'));
      expect(preamble, contains('bottom=15mm'));
      expect(preamble, contains('left=15mm'));
      expect(preamble, contains('right=15mm'));
    });
  });

  group('PageSizeSpec — CSS @page naam', () {
    test('A4 → cssName "A4"', () {
      expect(PageSizeSpec.a4.cssName, 'A4');
    });

    test('A4 landscape → cssName "A4 landscape"', () {
      expect(PageSizeSpec.a4Landscape.cssName, 'A4 landscape');
    });
  });

  group('PageMargins — CSS margin', () {
    test('standaard → "25mm 20mm 25mm 20mm"', () {
      expect(const PageMargins().cssMargin, '25mm 20mm 25mm 20mm');
    });

    test('uniform 30mm → "30mm 30mm 30mm 30mm"', () {
      expect(const PageMargins.uniform(30).cssMargin, '30mm 30mm 30mm 30mm');
    });
  });
}
