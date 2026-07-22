import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/rich_text_layout.dart';

void main() {
  test(
    'an expanded rich-text deck serialises to one slide, not one per page',
    () {
      const profile = ThemeProfile();
      final slide = Slide.create(SlideType.bullets).copyWith(
        title: 'Titel',
        listStyle: ListStyle.richText,
        customMarkdown: List.generate(
          40,
          (i) => 'Alinea $i met wat tekst om hoogte op te bouwen.',
        ).join('\n\n'),
      );
      final expanded = expandRichTextForRender([slide], profile);
      expect(
        expanded.length,
        greaterThan(1),
        reason: 'testopzet: moet pagineren',
      );

      final markdown = MarkdownService().generateDeck(
        Deck(title: 'Demo', slides: expanded),
      );
      // De body mag precies één keer in het bestand staan.
      expect('Alinea 0 '.allMatches(markdown).length, 1);
      expect('Alinea 39 '.allMatches(markdown).length, 1);
    },
  );
}
