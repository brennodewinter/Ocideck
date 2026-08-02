import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_outline.dart';

void main() {
  test('outline maps headings to slides and source lines', () {
    final outline = buildMarkdownOutline(
      '''
---
marp: true
---
# Eerste
## Onderdeel
---
# Tweede
'''
          .trim(),
    );

    expect(outline.map((entry) => entry.title), [
      'Eerste',
      'Onderdeel',
      'Tweede',
    ]);
    expect(outline.map((entry) => entry.slideNumber), [1, 1, 2]);
    expect(outline.map((entry) => entry.line), [4, 5, 7]);
  });

  test('outline ignores headings and separators inside fenced code', () {
    final outline = buildMarkdownOutline(
      '''
# Echt
```markdown
# Geen kop
---
```
## Ook echt
'''
          .trim(),
    );

    expect(outline.map((entry) => entry.title), ['Echt', 'Ook echt']);
    expect(outline.last.slideNumber, 1);
  });
}
