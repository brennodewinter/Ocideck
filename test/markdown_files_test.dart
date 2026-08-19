import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_files.dart';

void main() {
  group('isEditableMarkdownFile', () {
    test('accepts the markdown and plain-text extensions', () {
      expect(isEditableMarkdownFile('/pad/verslag.md'), isTrue);
      expect(isEditableMarkdownFile('/pad/verslag.markdown'), isTrue);
      expect(isEditableMarkdownFile('/pad/aantekening.txt'), isTrue);
    });

    test('is case-insensitive on the extension', () {
      expect(isEditableMarkdownFile('/pad/VERSLAG.MD'), isTrue);
      expect(isEditableMarkdownFile('/pad/Notitie.TXT'), isTrue);
    });

    test('refuses everything else', () {
      expect(isEditableMarkdownFile('/pad/deck.ocideck'), isFalse);
      expect(isEditableMarkdownFile('/pad/data.json'), isFalse);
      expect(isEditableMarkdownFile('/pad/foto.png'), isFalse);
      // Geen extensie: een map of een binair bestand zonder achtervoegsel.
      expect(isEditableMarkdownFile('/pad/README'), isFalse);
      // `.md` als deel van de naam is geen extensie.
      expect(isEditableMarkdownFile('/pad/verslag.md.bak'), isFalse);
    });
  });

  group('firstMarkdownHeading', () {
    test('reads the first ATX heading of any level', () {
      expect(
        firstMarkdownHeading('# Kwartaalverslag\n\ntekst\n'),
        'Kwartaalverslag',
      );
      expect(firstMarkdownHeading('tekst\n\n## Bijlage\n'), 'Bijlage');
    });

    test('skips the YAML front matter', () {
      const source =
          '---\ntitle: iets\n# geen kop maar een sleutel\n---\n\n# Echte kop\n';
      expect(firstMarkdownHeading(source), 'Echte kop');
    });

    test('ignores a heading inside a fenced code block', () {
      const source = '```\n# niet dit\n```\n\n# Wel dit\n';
      expect(firstMarkdownHeading(source), 'Wel dit');
    });

    test('strips a closing hash run', () {
      expect(firstMarkdownHeading('## Titel ##\n'), 'Titel');
    });

    test('returns null without a heading, and for an empty document', () {
      expect(firstMarkdownHeading('gewoon een regel tekst\n'), isNull);
      expect(firstMarkdownHeading(''), isNull);
    });

    test('looks no further than scanChars', () {
      final source = '${'x\n' * 100}# Te laat\n';
      expect(firstMarkdownHeading(source, scanChars: 20), isNull);
      expect(firstMarkdownHeading(source), 'Te laat');
    });
  });
}
