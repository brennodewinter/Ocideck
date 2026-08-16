import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';

/// De drukkersafloop: het vel wordt rondom groter dan het snijformaat, zodat
/// inkt die tot de rand loopt dóór de snijlijn heen gaat. Zonder afloop moet
/// alles precies blijven zoals het was — het is een uitzondering, geen nieuwe
/// standaard.
void main() {
  group('zonder afloop verandert er niets', () {
    const margins = PageMargins();

    test('de CSS-maat blijft de papiernaam', () {
      expect(PageSizeSpec.a4.cssSizeWith(margins), 'A4');
    });

    test('LaTeX houdt de papiermaat uit documentclass', () {
      expect(PageSizeSpec.a4.latexPaperWith(margins), isNull);
    });

    test('de marges zijn de marges', () {
      expect(margins.cssMargin, '25mm 20mm 25mm 20mm');
      expect(margins.latexMargin, 'top=25mm,bottom=25mm,left=20mm,right=20mm');
    });

    test('de opgeslagen vorm blijft kort', () {
      expect(margins.id, '25,25,20,20');
    });
  });

  group('met afloop', () {
    const margins = PageMargins(bleedMm: 3);

    test('het vel groeit 3mm aan elke zijde', () {
      // A4 is 210 × 297; met 3mm rondom wordt dat 216 × 303.
      expect(PageSizeSpec.a4.cssSizeWith(margins), '216mm 303mm');
      expect(
        PageSizeSpec.a4.latexPaperWith(margins),
        'paperwidth=216mm,paperheight=303mm',
      );
    });

    test('liggend groeit in de andere richting mee', () {
      expect(PageSizeSpec.a4Landscape.cssSizeWith(margins), '303mm 216mm');
    });

    test('de tekstspiegel schuift mee, zodat hij op zijn plek blijft', () {
      // Zonder deze verschuiving zou de tekst 3mm naar de snijlijn kruipen.
      expect(margins.cssMargin, '28mm 23mm 28mm 23mm');
      expect(margins.latexMargin, 'top=28mm,bottom=28mm,left=23mm,right=23mm');
    });

    test('de afloop overleeft opslaan en teruglezen', () {
      final back = PageMargins.fromId(margins.id);
      expect(back, margins);
      expect(back!.bleedMm, 3);
    });
  });

  test('een oude opgeslagen marge zonder afloop leest gewoon door', () {
    final back = PageMargins.fromId('25,25,20,20');
    expect(back, const PageMargins());
    expect(back!.hasBleed, isFalse);
  });

  // De snijtekens-schakelaar heeft kort bestaan en is er weer uit: geen enkel
  // uitvoerpad zette ze, dus beloofde hij drukwerk dat niemand leverde. Een
  // waarde die in die periode is opgeslagen mag niet stil terugvallen op de
  // standaardmarges — de marges zelf stonden er immers gewoon in.
  test('een marge uit de snijtekens-periode leest zijn afloop nog', () {
    final back = PageMargins.fromId('25,25,20,20,3,1');
    expect(back, isNotNull);
    expect(back!.bleedMm, 3);
    expect(back.topMm, 25);
  });

  test('alle ISO-reeksen en -nummers leveren een maat', () {
    for (final series in PaperSeries.values) {
      for (var n = 0; n <= 10; n++) {
        final spec = PageSizeSpec(series: series, number: n);
        final (w, h) = spec.dimensions;
        expect(
          w,
          greaterThan(0),
          reason: '${spec.sizeName} heeft geen breedte',
        );
        expect(h, greaterThan(w), reason: '${spec.sizeName} is niet staand');
        expect(PageSizeSpec.fromId(spec.id), spec);
      }
    }
  });
}
