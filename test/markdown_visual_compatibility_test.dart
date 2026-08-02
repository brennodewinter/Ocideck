import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/markdown_visual_compatibility.dart';

void main() {
  test('detects constructs that are unsafe to round-trip visually', () {
    final limitations = markdownVisualLimitations(r'''
| A | B |
| --- | --- |
| 1 | 2 |

<!-- _class: lead -->
Prijs \* letterlijk
Zie[^1]
[^1]: noot
''');

    expect(limitations, containsAll(MarkdownVisualLimitation.values));
  });

  test('ignores unsafe-looking content inside code fences', () {
    final limitations = markdownVisualLimitations('''
```markdown
| A | B |
| --- | --- |
<div>
```
''');

    expect(limitations, isEmpty);
  });
}
