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
}
