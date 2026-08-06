import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_document.dart';
import 'package:ocideck/models/markdown_kind.dart';

void main() {
  group('byte-getrouwe round-trip — de nul-verlies-poort', () {
    // Elk geval is een constructie die het deck-pad zou aanraken (normaliseren,
    // op `---` knippen, streepjes escapen) maar die een document byte-identiek
    // MOET bewaren. Faalt er hier iets, dan is het plat-.md-contract gebroken.
    final cases = <String, String>{
      'leeg': '',
      'gewone alinea': 'Hallo wereld.\n',
      'geen sluitende newline': '# Titel\n\nTekst zonder eind-newline',
      'thematische regel blijft --- (geen dia-scheiding)':
          'Boven de streep.\n\n---\n\nOnder de streep.\n',
      'CRLF blijft CRLF': 'Regel een\r\nRegel twee\r\n',
      'auteur-frontmatter blijft byte-identiek':
          '---\ntitle: Memo\nauthor: Jane\n---\n\n# Kop\n\nInhoud.\n',
      'zero-width space en nbsp blijven staan': 'a​--​-b c\n',
      'fenced chart-blok blijft verbatim':
          '## Grafiek\n\n```chart\n{ "type": "line", "source": "data/x.json" }\n```\n',
      'tab-inspringing en dubbele spaties':
          '- item\n\t- genest item\n\ntekst  met  dubbele  spaties\n',
      'losse pipe-regel (geen geldige tabel)': '| dit is geen tabel\n',
    };
    cases.forEach((name, source) {
      test(name, () {
        final doc = MarkdownDocument.parse(source);
        expect(doc.toMarkdown(), source);
        // Ook na een open → bewerk-met-zelfde-inhoud → opslaan-cyclus.
        expect(doc.withSource(source).toMarkdown(), source);
      });
    });
  });

  test('soort is altijd document', () {
    expect(MarkdownDocument.parse('x').kind, MarkdownKind.document);
  });

  test('outline volgt de koppen in volgorde', () {
    final doc = MarkdownDocument.parse('# Een\n\n## Twee\n\ntekst\n\n# Drie\n');
    expect(
      doc.outline.map((e) => e.title),
      containsAllInOrder(['Een', 'Twee', 'Drie']),
    );
  });

  test('withSource vervangt de hele inhoud', () {
    final doc = MarkdownDocument.parse('oud\n').withSource('nieuw\n');
    expect(doc.toMarkdown(), 'nieuw\n');
  });

  test('isEmpty', () {
    expect(MarkdownDocument.parse('').isEmpty, isTrue);
    expect(MarkdownDocument.parse('x').isEmpty, isFalse);
  });
}
