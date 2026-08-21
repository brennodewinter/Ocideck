import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/document_style.dart';

/// De volgorde van gelden: wat het document zelf draagt wint van de instelling.
/// Maat en marges gelden los van elkaar.
void main() {
  const settings = AppSettings(
    documentPageSize: PageSizeSpec(series: PaperSeries.a, number: 5),
    documentPageMargins: PageMargins(topMm: 10, bottomMm: 10),
  );

  test('zonder sleutels geldt de instelling', () {
    final setup = effectiveDocumentPageSetup(settings, '# Kop\n');
    expect(setup.size, const PageSizeSpec(series: PaperSeries.a, number: 5));
    expect(setup.margins?.topMm, 10);
  });

  test('het document wint van de instelling', () {
    const source = '---\npapersize: a3\n---\n\n# Kop\n';
    final setup = effectiveDocumentPageSetup(settings, source);
    expect(setup.size, const PageSizeSpec(series: PaperSeries.a, number: 3));
  });

  test('alleen een maat in het document laat de marges met rust', () {
    const source = '---\npapersize: a3\n---\n\n# Kop\n';
    final setup = effectiveDocumentPageSetup(settings, source);
    expect(
      setup.margins?.topMm,
      10,
      reason: 'de marges komen dan nog uit de instelling',
    );
  });

  test('alleen marges in het document laten de maat met rust', () {
    const source = '---\ngeometry: top=40mm,bottom=40mm\n---\n\n# Kop\n';
    final setup = effectiveDocumentPageSetup(settings, source);
    expect(setup.size, const PageSizeSpec(series: PaperSeries.a, number: 5));
    expect(setup.margins?.topMm, 40);
  });

  // ── #1681: marges die niet binnen het vel passen vallen terug ──────
  group('content-area fallback (#1681)', () {
    test('marges breder dan het vel vallen terug op de instellingen', () {
      // A5 is 148×210mm; left=200 + right=200 = 400 > 148.
      const source =
          '---\ngeometry: top=25mm,bottom=25mm,left=200mm,right=200mm\n---\n\n# Kop\n';
      final setup = effectiveDocumentPageSetup(settings, source);
      expect(
        setup.margins?.leftMm,
        20,
        reason:
            'de instellingen-marges gelden, niet de ongeldige document-marges',
      );
    });

    test('marges hoger dan het vel vallen terug op de instellingen', () {
      const source =
          '---\ngeometry: top=200mm,bottom=200mm,left=20mm,right=20mm\n---\n\n# Kop\n';
      final setup = effectiveDocumentPageSetup(settings, source);
      expect(
        setup.margins?.topMm,
        10,
        reason: 'de instellingen-marges gelden (topMm=10)',
      );
    });

    test('geldige marges blijven doorkomen', () {
      const source = '---\ngeometry: top=40mm,bottom=40mm\n---\n\n# Kop\n';
      final setup = effectiveDocumentPageSetup(settings, source);
      expect(setup.margins?.topMm, 40);
    });
  });
}
