import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/utils/markdown_paste_cleanup.dart';
import 'package:ocideck/utils/inline_markdown.dart';
import 'package:ocideck/services/import/utils/import_text_sanitizer.dart';

void main() {
  group('presentation escape display', () {
    test('inline markdown unescapes common pasted sequences', () {
      for (final input in [
        r'Intro \- regel',
        r'\\- dubbel',
        r'\* ster',
        r'letter \. punt',
        r'Kosten (\$ 100)',
      ]) {
        final norm = normalizeRichTextMarkdown(input);
        final runs = parseInlineRuns(norm);
        final rendered = runs.map((r) => r.text).join();
        expect(rendered, isNot(contains(r'\')), reason: 'input: $input');
      }
    });

    // #1299: een `&` in een geïmporteerde slidetitel wordt aan de importgrens
    // naar `&amp;` geschreven (veilig voor het `.md` en de HTML-export), en de
    // Flutter-preview moet het via `parseInlineRuns` weer terugdraaien.
    test('imported ampersand round-trips through sanitize and display', () {
      const raw = 'Where to find, copy & paste?';
      final stored = sanitizeImportedText(raw);
      expect(stored, 'Where to find, copy &amp; paste?');
      final rendered = parseInlineRuns(
        normalizeRichTextMarkdown(stored),
      ).map((r) => r.text).join();
      expect(rendered, raw);
    });

    test('deck round-trip for rich text keeps displayable markdown', () {
      const body = 'Intro\n\\- Dit is geen lijst\n\\- Nog een regel';
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(
              SlideType.bullets,
            ).copyWith(listStyle: ListStyle.richText, customMarkdown: body),
          ],
        ),
      );
      final parsed = service.parseDeck(markdown)!.slides.single.customMarkdown;
      final norm = normalizeRichTextMarkdown(parsed);
      final rendered = parseInlineRuns(norm).map((r) => r.text).join('\n');
      expect(rendered, 'Intro\n- Dit is geen lijst\n- Nog een regel');
    });
  });
}
