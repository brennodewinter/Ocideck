import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/markdown_visual_compatibility.dart';

void main() {
  group('sourceFragmentRanges wijst de regels aan die als bronblok reizen', () {
    test('detecteert constructies die niet verliesvrij als tekst reizen', () {
      final ranges = sourceFragmentRanges(
        '<!-- _class: lead -->\nPrijs \\* letterlijk\nZie[^1]\n[^1]: noot\n',
      );

      // Regel 0 (commentaar) en 1 (escape) vormen één brok, en `Zie[^1]` hoort
      // bij dezelfde alinea — hij reist mee zonder zelf een hit te zijn. De
      // definitie `[^1]:` is een fragmentgrens en reist als eigen embed.
      expect(ranges, [(0, 3)]);
    });

    test(
      'een GFM-tabel is geen beperking meer — die round-trip\'t als embed',
      () {
        // Een tabel valt de visuele modus niet meer terug op ruwe markdown: hij
        // wordt een `x-embed-table`-embed en blijft bewerkbaar (zie
        // MarkdownQuillCodec / TableEmbedBuilder).
        expect(
          sourceFragmentRanges('''
| A | B |
| --- | ---: |
| 1 | 2 |
'''),
          isEmpty,
        );
      },
    );

    group('de regels van een tabel reizen mee in het blok', () {
      // De klacht: één bewerking in een cel wierp het hele document terug in de
      // brontekst. De tabel gaat als één `x-embed-table` door de rijke-tekstlaag,
      // dus zijn regels kunnen daar niet stukgaan — en `encodeMarkdownTableCell`
      // schrijft nu eenmaal `<br>` voor een celregeleinde en `\\` voor een
      // backslash. Die telden als rauwe HTML en als ontsnapping (#1565).
      test('een regeleinde in een cel is geen rauwe HTML', () {
        expect(
          sourceFragmentRanges('''
| Naam | Rol |
| --- | --- |
| Aap<br>Noot | Tester |
'''),
          isEmpty,
        );
      });

      test('de ontsnappingen van de celcodering zijn geen beperking', () {
        expect(
          sourceFragmentRanges(r'''
| Pad | Expressie |
| --- | --- |
| C:\\Data | a \| b |
'''),
          isEmpty,
        );
      });

      test('tekst ná de tabel wordt weer gewoon gescand', () {
        expect(
          sourceFragmentRanges(
            '| A | B |\n| --- | --- |\n| 1 | 2 |\n\nPrijs \\* letterlijk\n',
          ),
          [(4, 5)],
        );
      });
    });

    group('een tabelregel die géén blok vormt, wordt een bronblok', () {
      // `_normalizeQuillOutput` laat de ontsnappingen van Quill op elke regel die
      // met een pijp begint bewust staan — daar betekent `\|` structuur. Hoort
      // die regel niet bij een tabel die als blok reist, dan blijven Quills eigen
      // `\-` en `\.` er dus in staan en verandert de tekst van de gebruiker.
      test('kop en scheidingsrij van ongelijke breedte', () {
        // `EmbeddableTableSyntax` weigert deze tabel (kop 2, scheiding 3) en de
        // round-trip maalt hem tot één regel escaped tekst. Als bronblok mee-
        // nemen is het enige eerlijke antwoord.
        expect(
          sourceFragmentRanges('''
| A | B |
| --- | --- | --- |
| 1 | 2 |
'''),
          [(0, 3)],
        );
      });

      test('een losse tabelregel zonder scheidingsrij', () {
        expect(sourceFragmentRanges('Tekst.\n\n| 1 | 2 |\n'), [(2, 3)]);
      });

      test('een kopcel met een ontsnapte pijp telt niet mee als kolom', () {
        // Zo telt de embed: hij splitst op élke pijp. Kop 3, scheiding 2 — dus
        // geen blok, dus als bronblok meenemen in plaats van stilletjes slopen.
        expect(
          sourceFragmentRanges(r'''
| a \| b | c |
| --- | --- |
| 1 | 2 |
'''),
          [(0, 3)],
        );
      });

      test('een tabel in een codeblok telt niet als losse tabelregel', () {
        expect(sourceFragmentRanges('```\n| 1 | 2 |\n```\n'), isEmpty);
      });
    });

    test('negeert onveilige inhoud binnen code-fences', () {
      expect(
        sourceFragmentRanges('''
```markdown
<div>
Prijs \\* letterlijk
```
'''),
        isEmpty,
      );
    });

    test('de inhoudsopgave-marker is geen beperking meer', () {
      // Regressie: één ingevoegde inhoudsopgave gooide de hele visuele modus
      // terug naar brontekst, omdat `<!-- toc -->` als rauwe HTML telde.
      expect(
        sourceFragmentRanges('# Kop\n\n<!-- toc -->\n\n## Sectie\n'),
        isEmpty,
      );
      expect(sourceFragmentRanges('  <!--   toc   -->  '), isEmpty);
    });

    test('ander HTML-commentaar wordt wel een bronblok', () {
      expect(sourceFragmentRanges('<!-- _class: lead -->'), [(0, 1)]);
      // Marker mét tekst ernaast is geen kale marker en round-trip't niet.
      expect(sourceFragmentRanges('<!-- toc --> en meer'), [(0, 1)]);
    });

    test('een kop met HTML-commentaar erin is één bronblok', () {
      // Het 31-juli incidentrapport: `# <!-- timeline -->` is een kop met
      // HTML-commentaar erin. De `# ` maakt het een kop, en `<!--` triggert
      // de hit — als bronblok komt hij er byte-getrouw weer uit.
      expect(sourceFragmentRanges('# <!-- timeline -->\n'), [(0, 1)]);
    });

    test('slaat regels in een codeblok over', () {
      expect(sourceFragmentRanges('```\n<!-- html -->\n```\n\nPrijs \\*\n'), [
        (4, 5),
      ]);
    });

    group('inline code beschermt inhoud tegen false positives', () {
      // Regressie (#1761): `<persoon01>` in backticks werd als HTML-tag gezien,
      // waardoor het hele document uit de visuele modus viel. Inline code reist
      // als `code`-attribuut door Quill — de inhoud is platte tekst.
      test('hoekhaakjes in inline code zijn geen rawHtml', () {
        expect(sourceFragmentRanges('Zie `<persoon01>` in de tekst.'), isEmpty);
      });

      test('backslash-escapes in inline code zijn geen escapedPunctuation', () {
        expect(sourceFragmentRanges(r'Zie `\*` in de tekst.'), isEmpty);
      });

      test('HTML-commentaar buiten inline code blijft wel een hit', () {
        // HTML-*tags* round-trippen als platte tekst en zijn geen beperking meer
        // (#1777); HTML-*commentaar* wel. Inline code beschermt allebei.
        expect(sourceFragmentRanges('`<ok>` <!-- x --> na de code'), [(0, 1)]);
      });

      test('HTML-tags in proza zijn geen beperking meer (#1777)', () {
        // Regressie: een privacy-redactieplaceholder als `<persoon1>` trapte de
        // visuele modus uit omdat de tag als rauwe HTML werd gezien. De codec
        // round-tript tags byte-getrouw als letterlijke tekst.
        expect(sourceFragmentRanges('Dit is <persoon1> in proza.'), isEmpty);
        expect(
          sourceFragmentRanges('Zie `<persoon01>` en <persoon1> erna.'),
          isEmpty,
        );
        expect(sourceFragmentRanges('Tekst met <b>vet</b> en <br>.'), isEmpty);
      });
    });

    group('de brok om de hit mee', () {
      test('een hit in een alinea neemt de hele alinea mee', () {
        // Uitbreiding stopt op de witregel: de regels erboven en eronder horen
        // bij dezelfde brok en reizen mee — anders zou uitknippen midden in een
        // alinea de rondreis breken.
        expect(sourceFragmentRanges('Voor.\n\nEen \\* twee\n\nNa.\n'), [
          (2, 3),
        ]);
      });

      test('vervolgregels van een lijst of een citaat horen bij de brok', () {
        // Lijst- en citaatregels zijn géén fragmentgrens: ze zijn in Markdown
        // één blok met hun vervolgregels.
        expect(sourceFragmentRanges('> citaat \\*\n> vervolg\n\nNa.\n'), [
          (0, 2),
        ]);
      });

      test('een kopregel begrenst de brok', () {
        expect(sourceFragmentRanges('Tekst \\*\n## Kop\n\nNa.\n'), [(0, 1)]);
      });

      test('twee hits in dezelfde brok vormen één bereik', () {
        expect(sourceFragmentRanges('<!-- a -->\n<!-- b -->\n\nNa.\n'), [
          (0, 2),
        ]);
      });
    });
  });

  group('de bron van een fragment reist byte-getrouw terug', () {
    // Het echte contract van #2463: niet "de detector vindt hem", maar "wat
    // er in het bestand staat komt er ook weer uit" — ongewijzigd.
    String roundTrip(String source) {
      final document = MarkdownQuillCodec.documentFromMarkdown(source);
      return MarkdownQuillCodec.markdownFromDocument(document);
    }

    test('HTML-commentaar op eigen regel', () {
      const source = 'A.\n\n<!-- note -->\n\nB.\n';
      expect(roundTrip(source), source.trimRight());
    });

    test('meerregelig HTML-commentaar', () {
      const source = 'A.\n\n<!-- a -->\n<!-- b -->\n\nB.\n';
      expect(roundTrip(source), source.trimRight());
    });

    test('ontsnapte leestekens in proza', () {
      const source = 'A. \\* escape en \\~ meer\n\nB.\n';
      expect(roundTrip(source), source.trimRight());
    });

    test('een ontsnapte pijp als losse regel', () {
      const source = 'A.\n\n\\| losse tabelregel\n\nB.\n';
      expect(roundTrip(source), source.trimRight());
    });

    test('escapes in kop, lijst en citaat', () {
      const source =
          '# Kop \\* met escape\n\n- item \\*\n\n> citaat \\*\n\nB.\n';
      expect(roundTrip(source), source.trimRight());
    });

    test('fragmenten aan de randen van het document', () {
      expect(roundTrip('<!-- eerst -->\n\nB.\n'), '<!-- eerst -->\n\nB.');
      expect(roundTrip('A.\n\n<!-- laatst -->\n'), 'A.\n\n<!-- laatst -->');
    });

    test('de tekst om het fragment heen blijft gewone Markdown', () {
      // Alleen het brok is bron; de alinea's ervoor en erna reizen als
      // rijke tekst en komen dus óók als rijke tekst terug — geen escapes,
      // geen sentinels, geen restregels.
      const source = 'A. gewone **tekst**\n\n<!-- x -->\n\nB. weer gewoon\n';
      final out = roundTrip(source);
      expect(out, source.trimRight());
      expect(out, isNot(contains('OCIDECKSOURCEFRAGMENT')));
    });
  });
}
