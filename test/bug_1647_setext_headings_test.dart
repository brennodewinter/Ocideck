import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';

void main() {
  group('Setext-koppen in weergave (#1647)', () {
    test('=== onder een tekstregel is H1', () {
      const source = 'Titel\n=====\n\nInhoud.\n';
      final texts = DocumentMarkdownView.blockTexts(source);
      // De eerste block moet de kop zijn, niet een alinea.
      // blockTexts geeft de zoektekst per blok; een kop draagt zijn titel.
      expect(texts.first, contains('Titel'));
      // De headingBlockIndex moet de kop vinden.
      final idx = DocumentMarkdownView.headingBlockIndex(source, 'titel');
      expect(idx, 0);
    });

    test('--- onder een tekstregel is H2, geen horizontale streep', () {
      const source = 'Ondertitel\n----------\n\nInhoud.\n';
      final texts = DocumentMarkdownView.blockTexts(source);
      expect(texts.first, contains('Ondertitel'));
      final idx = DocumentMarkdownView.headingBlockIndex(
        source,
        'ondertitel',
      );
      expect(idx, 0);
    });

    test('--- na een lege regel blijft een horizontale streep', () {
      const source = 'Tekst.\n\n---\n\nMeer tekst.\n';
      final texts = DocumentMarkdownView.blockTexts(source);
      // Eerste blok is de alinea "Tekst.", tweede is de streep (geen tekst),
      // derde is "Meer tekst."
      expect(texts.first, contains('Tekst'));
      // De streep heeft geen zoektekst — een lege string.
      expect(texts[1], '');
      expect(texts[2], contains('Meer tekst'));
    });

    test('Setext H1 en H2 samen in één document', () {
      const source =
          'Hoofdstuk\n========\n\nOnderwerp\n---------\n\nTekst.\n';
      final idx1 = DocumentMarkdownView.headingBlockIndex(source, 'hoofdstuk');
      final idx2 = DocumentMarkdownView.headingBlockIndex(
        source,
        'onderwerp',
      );
      expect(idx1, greaterThanOrEqualTo(0));
      expect(idx2, greaterThanOrEqualTo(0));
      expect(idx2, greaterThan(idx1));
    });
  });
}
