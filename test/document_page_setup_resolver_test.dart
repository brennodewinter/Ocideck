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
}
