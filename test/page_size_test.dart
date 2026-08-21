import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';

/// Feature 3: ISO-216 paginamaties — de A/B/C-reeksen hebben de juiste
/// afmetingen, en de id-serialisatie round-tript.
void main() {
  group('PageSizeSpec — ISO-216 afmetingen', () {
    test('A4 is 210×297mm portret', () {
      const spec = PageSizeSpec.a4;
      final (w, h) = spec.dimensions;
      expect(w, 210.0);
      expect(h, 297.0);
      expect(spec.landscape, isFalse);
    });

    test('A4 landscape is 297×210mm', () {
      const spec = PageSizeSpec.a4Landscape;
      final (w, h) = spec.dimensions;
      expect(w, 297.0);
      expect(h, 210.0);
      expect(spec.landscape, isTrue);
    });

    test('A0 is 841×1189mm', () {
      const spec = PageSizeSpec(series: PaperSeries.a, number: 0);
      final (w, h) = spec.dimensions;
      expect(w, 841.0);
      expect(h, 1189.0);
    });

    test('B5 is 176×250mm', () {
      const spec = PageSizeSpec(series: PaperSeries.b, number: 5);
      final (w, h) = spec.dimensions;
      expect(w, 176.0);
      expect(h, 250.0);
    });

    test('C4 is 229×324mm (envelop)', () {
      const spec = PageSizeSpec(series: PaperSeries.c, number: 4);
      final (w, h) = spec.dimensions;
      expect(w, 229.0);
      expect(h, 324.0);
    });

    test('A10 is 26×37mm (kleinste)', () {
      const spec = PageSizeSpec(series: PaperSeries.a, number: 10);
      final (w, h) = spec.dimensions;
      expect(w, 26.0);
      expect(h, 37.0);
    });
  });

  group('PageSizeSpec — namen', () {
    test('cssName: A4 → "A4", A4 landscape → "A4 landscape"', () {
      expect(PageSizeSpec.a4.cssName, 'A4');
      expect(PageSizeSpec.a4Landscape.cssName, 'A4 landscape');
    });

    test('latexName: A4 → "a4paper", A4 landscape → "a4paper,landscape"', () {
      expect(PageSizeSpec.a4.latexName, 'a4paper');
      expect(PageSizeSpec.a4Landscape.latexName, 'a4paper,landscape');
    });

    test('sizeName is taalneutraal — de oriëntatie zit er niet in', () {
      // Het woord "liggend" hoort in de interface door l10n te gaan
      // (pageSizeLabel); het model levert alleen de maatnaam.
      expect(PageSizeSpec.a4.sizeName, 'A4');
      expect(PageSizeSpec.a4Landscape.sizeName, 'A4');
    });
  });

  group('PageSizeSpec — id round-trip', () {
    test('A4 portret → "A4" → A4 portret', () {
      const spec = PageSizeSpec.a4;
      expect(spec.id, 'A4');
      expect(PageSizeSpec.fromId(spec.id), spec);
    });

    test('A4 landscape → "A4L" → A4 landscape', () {
      const spec = PageSizeSpec.a4Landscape;
      expect(spec.id, 'A4L');
      expect(PageSizeSpec.fromId(spec.id), spec);
    });

    test('B5 → "B5" → B5', () {
      const spec = PageSizeSpec(series: PaperSeries.b, number: 5);
      expect(PageSizeSpec.fromId(spec.id), spec);
    });

    test('null of leeg → null', () {
      expect(PageSizeSpec.fromId(null), isNull);
      expect(PageSizeSpec.fromId(''), isNull);
    });

    test('ongeldig formaat → null', () {
      expect(PageSizeSpec.fromId('X4'), isNull);
      expect(PageSizeSpec.fromId('A99'), isNull);
    });
  });

  group('PageMargins', () {
    test('standaard: 25/25/20/20mm', () {
      const m = PageMargins();
      expect(m.topMm, 25);
      expect(m.bottomMm, 25);
      expect(m.leftMm, 20);
      expect(m.rightMm, 20);
    });

    test('uniform: 30mm rondom', () {
      const m = PageMargins.uniform(30);
      expect(m.topMm, 30);
      expect(m.bottomMm, 30);
      expect(m.leftMm, 30);
      expect(m.rightMm, 30);
    });

    test('cssMargin: "25mm 20mm 25mm 20mm" (top right bottom left)', () {
      const m = PageMargins();
      expect(m.cssMargin, '25mm 20mm 25mm 20mm');
    });

    test('latexMargin: "top=25mm,bottom=25mm,left=20mm,right=20mm"', () {
      const m = PageMargins();
      expect(m.latexMargin, 'top=25mm,bottom=25mm,left=20mm,right=20mm');
    });

    test('id round-trip', () {
      const m = PageMargins(topMm: 30, bottomMm: 25, leftMm: 15, rightMm: 20);
      expect(PageMargins.fromId(m.id), m);
    });
  });

  group('PageMargins — validatie (#1681)', () {
    test('isValid: standaardmarges zijn geldig', () {
      expect(const PageMargins().isValid, isTrue);
    });

    test('isValid: negatieve waarden zijn ongeldig', () {
      expect(const PageMargins(topMm: -1).isValid, isFalse);
      expect(const PageMargins(leftMm: -0.1).isValid, isFalse);
    });

    test('isValid: NaN en Infinity zijn ongeldig', () {
      expect(const PageMargins(topMm: double.nan).isValid, isFalse);
      expect(const PageMargins(rightMm: double.infinity).isValid, isFalse);
      expect(const PageMargins(bleedMm: double.nan).isValid, isFalse);
    });

    test('fromId: negatieve waarden vallen terug op null', () {
      expect(PageMargins.fromId('-1,25,20,20'), isNull);
    });

    test('fromId: NaN valt terug op null', () {
      expect(PageMargins.fromId('NaN,25,20,20'), isNull);
    });

    test('fromId: Infinity valt terug op null', () {
      expect(PageMargins.fromId('25,Infinity,20,20'), isNull);
    });

    test('fromId: geldige waarden blijven doorkomen', () {
      expect(
        PageMargins.fromId('30,25,15,20'),
        const PageMargins(topMm: 30, bottomMm: 25, leftMm: 15, rightMm: 20),
      );
    });
  });

  group('marginsFitPaper (#1681)', () {
    test('marges die binnen het vel passen', () {
      expect(marginsFitPaper(PageSizeSpec.a4, const PageMargins()), isTrue);
    });

    test('marges die samen breder zijn dan het vel', () {
      expect(
        marginsFitPaper(
          PageSizeSpec.a4,
          const PageMargins(leftMm: 200, rightMm: 200),
        ),
        isFalse,
      );
    });

    test('marges die samen hoger zijn dan het vel', () {
      expect(
        marginsFitPaper(
          PageSizeSpec.a4,
          const PageMargins(topMm: 200, bottomMm: 200),
        ),
        isFalse,
      );
    });

    test('marges die precies tot de minimum-textspiegel vullen', () {
      // A4 is 210×297; 10mm minimum → max 200mm horizontaal, 287mm verticaal.
      expect(
        marginsFitPaper(
          PageSizeSpec.a4,
          const PageMargins(leftMm: 100, rightMm: 100),
        ),
        isTrue,
      );
    });
  });

  group('PageSizeSpec — equality', () {
    test('zelfde reeks/nummer/landscape zijn gelijk', () {
      expect(PageSizeSpec.a4, PageSizeSpec.a4);
      expect(PageSizeSpec.a4 == PageSizeSpec.a4Landscape, isFalse);
    });
  });
}
