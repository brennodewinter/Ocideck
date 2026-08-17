import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/services/export_metadata.dart';
import 'package:ocideck/services/latex/latex_preamble.dart';

/// Snijtekens hebben eerder bestaan als schakelaar die in géén enkel
/// uitvoerpad iets deed; die is er toen uitgehaald (#1505). Ze komen alleen
/// terug voor het pad dat ze werkelijk zet: LaTeX, met het crop-pakket, rond
/// het snijformaat op het grotere vel.
void main() {
  const meta = ExportDocumentMetadata(title: 'Rapport', language: 'nl');

  String preamble({bool cropMarks = false, double bleed = 0}) =>
      articlePreamble(
        meta,
        pageSize: PageSizeSpec.a4,
        pageMargins: PageMargins(bleedMm: bleed),
        cropMarks: cropMarks,
      );

  test('zonder de schakelaar komt het pakket er niet in', () {
    // Wie geen snijtekens vraagt, krijgt ook geen extra afhankelijkheid.
    expect(preamble(bleed: 3), isNot(contains('{crop}')));
  });

  test('zonder afloop wijzen snijtekens nergens naar, dus geen pakket', () {
    expect(preamble(cropMarks: true), isNot(contains('{crop}')));
  });

  test('met afloop en de schakelaar staat het pakket op het snijformaat', () {
    final out = preamble(cropMarks: true, bleed: 3);
    // A4 is 210 × 297: de tekens horen om díe maat heen te staan, niet om het
    // vel van 216 × 303.
    expect(out, contains('width=210mm,height=297mm'));
    expect(out, contains('cam,center]{crop}'));
    // En het vel zelf is wél groter, via geometry.
    expect(out, contains('paperwidth=216mm,paperheight=303mm'));
  });

  test('een andere maat levert zijn eigen snijformaat op', () {
    final out = articlePreamble(
      meta,
      pageSize: const PageSizeSpec(series: PaperSeries.a, number: 5),
      pageMargins: const PageMargins(bleedMm: 5),
      cropMarks: true,
    );
    // A5 is 148 × 210.
    expect(out, contains('width=148mm,height=210mm'));
  });
}
