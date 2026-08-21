import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_visual_compatibility.dart';

void main() {
  test('detects constructs that are unsafe to round-trip visually', () {
    final limitations = markdownVisualLimitations(r'''
<!-- _class: lead -->
Prijs \* letterlijk
Zie[^1]
[^1]: noot
''');

    expect(
      limitations,
      containsAll([
        MarkdownVisualLimitation.rawHtml,
        MarkdownVisualLimitation.escapedPunctuation,
      ]),
    );
  });

  test(
    'een GFM-tabel is geen beperking meer — die round-trip\'t als embed',
    () {
      // Een tabel valt de visuele modus niet meer terug op ruwe markdown: hij
      // wordt een `x-embed-table`-embed en blijft bewerkbaar (zie
      // MarkdownQuillCodec / TableEmbedBuilder).
      final limitations = markdownVisualLimitations('''
| A | B |
| --- | ---: |
| 1 | 2 |
''');

      expect(limitations, isEmpty);
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
        markdownVisualLimitations('''
| Naam | Rol |
| --- | --- |
| Aap<br>Noot | Tester |
'''),
        isEmpty,
      );
    });

    test('de ontsnappingen van de celcodering zijn geen beperking', () {
      expect(
        markdownVisualLimitations(r'''
| Pad | Expressie |
| --- | --- |
| C:\\Data | a \| b |
'''),
        isEmpty,
      );
    });

    test('tekst ná de tabel wordt weer gewoon gescand', () {
      expect(
        markdownVisualLimitations(r'''
| A | B |
| --- | --- |
| 1 | 2 |

Prijs \* letterlijk
'''),
        contains(MarkdownVisualLimitation.escapedPunctuation),
      );
    });
  });

  group('een tabelregel die géén blok vormt, valt zichtbaar terug', () {
    // `_normalizeQuillOutput` laat de ontsnappingen van Quill op elke regel die
    // met een pijp begint bewust staan — daar betekent `\|` structuur. Hoort
    // die regel niet bij een tabel die als blok reist, dan blijven Quills eigen
    // `\-` en `\.` er dus in staan en verandert de tekst van de gebruiker.
    test('kop en scheidingsrij van ongelijke breedte', () {
      // `EmbeddableTableSyntax` weigert deze tabel (kop 2, scheiding 3) en de
      // round-trip maalt hem tot één regel escaped tekst. Zichtbaar terugvallen
      // is het enige eerlijke antwoord.
      expect(
        markdownVisualLimitations('''
| A | B |
| --- | --- | --- |
| 1 | 2 |
'''),
        contains(MarkdownVisualLimitation.looseTableLine),
      );
    });

    test('een losse tabelregel zonder scheidingsrij', () {
      expect(
        markdownVisualLimitations('Tekst.\n\n| 1 | 2 |\n'),
        contains(MarkdownVisualLimitation.looseTableLine),
      );
    });

    test('een kopcel met een ontsnapte pijp telt niet mee als kolom', () {
      // Zo telt de embed: hij splitst op élke pijp. Kop 3, scheiding 2 — dus
      // geen blok, dus terugvallen in plaats van stilletjes slopen.
      expect(
        markdownVisualLimitations(r'''
| a \| b | c |
| --- | --- |
| 1 | 2 |
'''),
        contains(MarkdownVisualLimitation.looseTableLine),
      );
    });

    test('een tabel in een codeblok telt niet als losse tabelregel', () {
      expect(markdownVisualLimitations('```\n| 1 | 2 |\n```\n'), isEmpty);
    });
  });

  test('ignores unsafe-looking content inside code fences', () {
    final limitations = markdownVisualLimitations('''
```markdown
<div>
Prijs \\* letterlijk
```
''');

    expect(limitations, isEmpty);
  });

  test('de inhoudsopgave-marker is geen beperking meer', () {
    // Regressie: één ingevoegde inhoudsopgave gooide de hele visuele modus
    // terug naar brontekst, omdat `<!-- toc -->` als rauwe HTML telde.
    expect(
      markdownVisualLimitations('# Kop\n\n<!-- toc -->\n\n## Sectie\n'),
      isEmpty,
    );
    expect(markdownVisualLimitations('  <!--   toc   -->  '), isEmpty);
  });

  test('ander HTML-commentaar blijft wel een beperking', () {
    expect(
      markdownVisualLimitations('<!-- _class: lead -->'),
      contains(MarkdownVisualLimitation.rawHtml),
    );
    // Marker mét tekst ernaast is geen kale marker en round-trip't niet.
    expect(
      markdownVisualLimitations('<!-- toc --> en meer'),
      contains(MarkdownVisualLimitation.rawHtml),
    );
  });

  group('firstVisualLimitation', () {
    test('vindt de eerste beperking met regelnummer — rawHtml', () {
      final hit = firstVisualLimitation('# Kop\n\n<!-- timeline -->\n');
      expect(hit, isNotNull);
      expect(hit!.limitation, MarkdownVisualLimitation.rawHtml);
      expect(hit.lineIndex, 2);
    });

    test('vindt de eerste beperking met regelnummer — escapedPunctuation', () {
      final hit = firstVisualLimitation('# Kop\n\nPrijs \\* letterlijk\n');
      expect(hit, isNotNull);
      expect(hit!.limitation, MarkdownVisualLimitation.escapedPunctuation);
      expect(hit.lineIndex, 2);
    });

    test('vindt de eerste beperking met regelnummer — looseTableLine', () {
      final hit = firstVisualLimitation('Tekst.\n\n| 1 | 2 |\n');
      expect(hit, isNotNull);
      expect(hit!.limitation, MarkdownVisualLimitation.looseTableLine);
      expect(hit.lineIndex, 2);
    });

    test('geen beperking → null', () {
      expect(firstVisualLimitation('# Kop\n\nAlinea tekst.\n'), isNull);
    });

    test('een kop met HTML-commentaar erin is rawHtml', () {
      // Het 31-juli incidentrapport: `# <!-- timeline -->` is een kop met
      // HTML-commentaar erin. De `# ` maakt het een kop, en `<!--` triggert
      // rawHtml — het hele document valt terug op brontekst.
      final hit = firstVisualLimitation('# <!-- timeline -->\n');
      expect(hit, isNotNull);
      expect(hit!.limitation, MarkdownVisualLimitation.rawHtml);
      expect(hit.lineIndex, 0);
    });

    test('geeft de eerste hit bij meerdere beperkingen', () {
      final hit = firstVisualLimitation('<!-- html -->\n\nPrijs \\*\n');
      expect(hit, isNotNull);
      expect(hit!.limitation, MarkdownVisualLimitation.rawHtml);
      expect(hit.lineIndex, 0);
    });

    test('slaat regels in een codeblok over', () {
      final hit = firstVisualLimitation(
        '```\n<!-- html -->\n```\n\nPrijs \\*\n',
      );
      expect(hit, isNotNull);
      expect(hit!.limitation, MarkdownVisualLimitation.escapedPunctuation);
      expect(hit.lineIndex, 4);
    });
  });
}
