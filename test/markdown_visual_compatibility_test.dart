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

    expect(limitations, containsAll(MarkdownVisualLimitation.values));
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
}
