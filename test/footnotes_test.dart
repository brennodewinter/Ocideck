import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/footnotes.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';

/// Voetnoten in een document: `[^1]` in de tekst, `[^1]: …` als definitie.
/// De ontleding is gedeeld door de weergave, de vellen en beide exports — dus
/// de regels horen hier vast te liggen en niet in een van die drie.
void main() {
  group('nummeren', () {
    test('de nummers volgen de leesvolgorde, niet het label', () {
      const md = '''
Eerst [^bron] en dan [^a].

[^a]: De tweede.
[^bron]: De eerste.
''';
      expect(documentFootnotes(md), [
        const Footnote(label: 'bron', text: 'De eerste.', number: 1),
        const Footnote(label: 'a', text: 'De tweede.', number: 2),
      ]);
    });

    test('twee verwijzingen naar hetzelfde label delen één nummer', () {
      const md = 'Een [^x] en nog een [^x].\n\n[^x]: Eén noot.\n';
      expect(documentFootnotes(md), hasLength(1));
      expect(footnoteNumbers(md), {'x': 1});
    });

    test('een verwijzing zonder definitie is gewoon tekst', () {
      // Anders zou `[^1]` in een technische tekst ineens een noot worden.
      expect(documentFootnotes('Zie [^1] hierboven.'), isEmpty);
      expect(hasFootnotes('Zie [^1] hierboven.'), isFalse);
    });

    test('een definitie waar niets naar verwijst krijgt geen nummer', () {
      // Een noot met een nummer maar zonder merkteken in de tekst is een
      // raadsel; hij blijft wel gewoon in het bestand staan.
      const md = 'Tekst zonder verwijzing.\n\n[^weg]: Blijft staan.\n';
      expect(documentFootnotes(md), isEmpty);
      expect(stripFootnoteDefinitions(md), 'Tekst zonder verwijzing.\n');
    });
  });

  group('definities uit de tekst halen', () {
    test('de definitieregel verdwijnt uit de lopende tekst', () {
      const md = 'Een zin [^1].\n\n[^1]: De noot.\n\nNog een alinea.\n';
      expect(
        stripFootnoteDefinitions(md),
        'Een zin [^1].\n\nNog een alinea.\n',
      );
    });

    test('een ingesprongen vervolgregel hoort bij de noot', () {
      const md = 'Zin [^1].\n\n[^1]: Eerste regel\n    en de rest.\n\nSlot.\n';
      expect(documentFootnotes(md).single.text, 'Eerste regel en de rest.');
      expect(stripFootnoteDefinitions(md), 'Zin [^1].\n\nSlot.\n');
    });

    test('een niet-ingesprongen regel eronder blijft een gewone alinea', () {
      const md = 'Zin [^1].\n\n[^1]: De noot.\nEen alinea.\n';
      expect(documentFootnotes(md).single.text, 'De noot.');
      expect(stripFootnoteDefinitions(md), 'Zin [^1].\n\nEen alinea.\n');
    });

    test('binnen een codeblok is niets een definitie', () {
      const md = '''
Zin [^1].

```
[^1]: dit is code
```

[^1]: De echte noot.
''';
      expect(documentFootnotes(md).single.text, 'De echte noot.');
      expect(stripFootnoteDefinitions(md), contains('[^1]: dit is code'));
    });

    test('een tekst zonder voetnoten komt er byte-identiek uit', () {
      const md = '# Kop\n\nGewone tekst met [een link](a.md).\n';
      expect(stripFootnoteDefinitions(md), md);
      expect(documentFootnotes(md), isEmpty);
    });
  });

  group('verwijzingen vinden', () {
    test('de labels komen in volgorde terug', () {
      expect(footnoteReferencesIn('a [^x] b [^y] c [^x]'), ['x', 'y', 'x']);
    });

    test('een definitie telt niet als verwijzing', () {
      expect(footnoteReferencesIn('[^x]: de noot'), isEmpty);
    });
  });
  group('door de rijke-tekstlaag heen en weer', () {
    // De visuele editor draagt een voetnoot als twee embeds. Wat erin gaat moet
    // er byte-voor-byte weer uitkomen — anders herschrijft het openen van een
    // ándere weergave het bestand van de gebruiker.
    String roundTrip(String markdown) =>
        MarkdownQuillCodec.markdownFromDocument(
          MarkdownQuillCodec.documentFromMarkdown(markdown),
        );

    test('verwijzing en definitie komen er onveranderd uit', () {
      const md = 'Een zin [^1] met een noot.\n\n[^1]: De noot zelf.\n\nSlot.';
      expect(roundTrip(md), md.trimRight());
    });

    test('een zelfgekozen label blijft dat label', () {
      const md = 'Zie [^bron].\n\n[^bron]: Het boek.';
      expect(roundTrip(md), md);
    });

    test('een ingesprongen vervolgregel wordt geen codeblok', () {
      // Voor de markdown-parser is een ingesprongen regel een codeblok; zonder
      // dat de definitie hem opslokt kwam de tekst van de gebruiker er als
      // ```-fence weer uit. Nu wordt het één regel — de tekst blijft heel,
      // alleen de regelovergang in de bron verdwijnt (FILE_FORMAT.md §14.9).
      const md = 'Zin [^1].\n\n[^1]: Eerste regel\n    en de rest.\n\nSlot.';
      final back = roundTrip(md);
      expect(back, isNot(contains('```')));
      expect(back, contains('[^1]: Eerste regel en de rest.'));
    });
  });
}
