import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/services/document_page_setup.dart';

/// De paginaopmaak reist optioneel mee in het document zelf, in vocabulaire dat
/// Pandoc écht uitvoert (`papersize:`, `geometry:`). De rode lijn blijft de
/// byte-getrouwe round-trip: zetten en weer wissen geeft de oorspronkelijke
/// bytes terug.
void main() {
  const plain = '# Rapport\n\nEen alinea.\n';

  group('lezen', () {
    test('een document zonder front matter zegt niets over de pagina', () {
      expect(documentPageSetup(plain), kNoDocumentPageSetup);
    });

    test('papersize en geometry komen terug als maat en marges', () {
      const source =
          '---\npapersize: a4\n'
          'geometry: top=30mm,bottom=30mm,left=15mm,right=15mm\n---\n\n# Kop\n';
      final setup = documentPageSetup(source);
      expect(setup.size, PageSizeSpec.a4);
      expect(setup.margins?.topMm, 30);
      expect(setup.margins?.leftMm, 15);
      expect(setup.margins?.hasBleed, isFalse);
    });

    test('a4paper leest ook, want die schrijfwijze is in omloop', () {
      const source = '---\npapersize: a4paper\n---\n\n# Kop\n';
      expect(documentPageSetup(source).size, PageSizeSpec.a4);
    });

    test('een onbekende waarde is geen fout maar een stilte', () {
      // Terugvallen op de instelling, niet falen — zoals een ontbrekend
      // stijlprofiel dat ook doet.
      const source = '---\npapersize: doorslagpapier\n---\n\n# Kop\n';
      expect(documentPageSetup(source).size, isNull);
    });

    test('een vel dat groter is dan zijn ISO-maat levert de afloop op', () {
      // A4 is 210 × 297; 216 × 303 is dat plus 3 mm rondom.
      const source =
          '---\ngeometry: paperwidth=216mm,paperheight=303mm,'
          'top=28mm,bottom=28mm,left=23mm,right=23mm\n---\n\n# Kop\n';
      final margins = documentPageSetup(source).margins;
      expect(margins?.bleedMm, 3);
      // En de marges worden weer vanaf het snijformaat gerekend.
      expect(margins?.topMm, 25);
      expect(margins?.leftMm, 20);
    });

    test('een vrije maat is geen afloop', () {
      const source =
          '---\ngeometry: paperwidth=200mm,paperheight=200mm,top=10mm\n'
          '---\n\n# Kop\n';
      expect(documentPageSetup(source).margins?.bleedMm, 0);
    });
  });

  group('schrijven', () {
    test('een gewone maat wordt papersize plus marges', () {
      final out = withDocumentPageSetup(
        plain,
        size: PageSizeSpec.a4,
        margins: const PageMargins(),
      );
      expect(out, contains('papersize: a4'));
      expect(
        out,
        contains('geometry: top=25mm,bottom=25mm,left=20mm,right=20mm'),
      );
      expect(out, endsWith(plain), reason: 'de body blijft ongemoeid');
    });

    test('met afloop dragen expliciete maten het verhaal', () {
      final out = withDocumentPageSetup(
        plain,
        size: PageSizeSpec.a4,
        margins: const PageMargins(bleedMm: 3),
      );
      // Een papiernaam zou hier liegen: het vel is groter dan A4.
      expect(out, isNot(contains('papersize:')));
      expect(out, contains('paperwidth=216mm,paperheight=303mm'));
      expect(out, contains('top=28mm'));
    });

    test('liggend gaat ook als expliciete maat', () {
      final out = withDocumentPageSetup(
        plain,
        size: PageSizeSpec.a4Landscape,
        margins: const PageMargins(),
      );
      expect(out, isNot(contains('papersize:')));
      expect(out, contains('paperwidth=297mm,paperheight=210mm'));
    });

    test('zetten en weer wissen geeft exact de oorspronkelijke bytes', () {
      final set = withDocumentPageSetup(
        plain,
        size: PageSizeSpec.a4,
        margins: const PageMargins(),
      );
      expect(set, isNot(plain));
      final cleared = withDocumentPageSetup(set, size: null, margins: null);
      expect(cleared, plain);
    });

    test('een handgeschreven sleutel blijft verbatim staan', () {
      const withOwn = '---\ntitle: Mijn rapport\n---\n\n# Kop\n';
      final set = withDocumentPageSetup(
        withOwn,
        size: PageSizeSpec.a4,
        margins: const PageMargins(),
      );
      expect(set, contains('title: Mijn rapport'));
      final cleared = withDocumentPageSetup(set, size: null, margins: null);
      expect(cleared, withOwn, reason: 'alleen onze eigen regels gaan weg');
    });

    test('de stijl blijft naast de paginaopmaak staan', () {
      const styled = '---\ntheme: LibreKAT\n---\n\n# Kop\n';
      final set = withDocumentPageSetup(
        styled,
        size: PageSizeSpec.a4,
        margins: const PageMargins(),
      );
      expect(set, contains('theme: LibreKAT'));
      expect(set, contains('papersize: a4'));
      expect(withDocumentPageSetup(set, size: null, margins: null), styled);
    });

    // De documentatie-agent vond dit door de code tegen de tekst te leggen:
    // met afloop of liggend schrijven we geen papiernaam, en het leespad viel
    // dan terug op de instelling. Een vastgelegde maat die niet terugkomt maakt
    // het vastleggen zinloos.
    test('een vastgelegde maat overleeft ook mét afloop', () {
      final out = withDocumentPageSetup(
        plain,
        size: PageSizeSpec.a4,
        margins: const PageMargins(bleedMm: 3),
      );
      final back = documentPageSetup(out);
      expect(back.size, PageSizeSpec.a4);
      expect(back.margins?.bleedMm, 3);
      expect(back.margins?.topMm, 25);
    });

    test('een vastgelegde liggende maat overleeft ook', () {
      final out = withDocumentPageSetup(
        plain,
        size: PageSizeSpec.a4Landscape,
        margins: const PageMargins(),
      );
      expect(documentPageSetup(out).size, PageSizeSpec.a4Landscape);
    });

    test('een vrije maat blijft een vrije maat', () {
      const source =
          '---\ngeometry: paperwidth=200mm,paperheight=200mm,top=10mm\n'
          '---\n\n# Kop\n';
      expect(documentPageSetup(source).size, isNull);
    });

    test('draagt het document een opmaak, in alle vier de vormen', () {
      // De indicator hing aan de papiernaam alleen, en merkte daardoor juist de
      // documenten die OciDeck zelf had vastgelegd aan als "uit je
      // instellingen".
      expect(documentCarriesPageSetup(plain), isFalse);
      for (final margins in [
        const PageMargins(),
        const PageMargins(bleedMm: 3),
      ]) {
        for (final size in [PageSizeSpec.a4, PageSizeSpec.a4Landscape]) {
          final out = withDocumentPageSetup(
            plain,
            size: size,
            margins: margins,
          );
          expect(
            documentCarriesPageSetup(out),
            isTrue,
            reason: '$size met afloop ${margins.bleedMm} wordt niet herkend',
          );
        }
      }
    });

    test('heen en weer door de codec verandert de opmaak niet', () {
      const size = PageSizeSpec(series: PaperSeries.b, number: 5);
      const margins = PageMargins(topMm: 18, bottomMm: 22, bleedMm: 5);
      final out = withDocumentPageSetup(plain, size: size, margins: margins);
      final back = documentPageSetup(out);
      expect(back.margins?.topMm, 18);
      expect(back.margins?.bottomMm, 22);
      expect(back.margins?.bleedMm, 5);
    });
  });
}
