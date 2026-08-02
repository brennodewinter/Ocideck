import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/markdown_source_document.dart';

void main() {
  const source = '''---
marp: true
---
# Eerste

Tekst
---
# Tweede

```markdown
---
```
''';

  test('source document keeps exact source and finds real slide ranges', () {
    final document = MarkdownSourceDocument.parse(source);

    expect(document.source, source);
    expect(document.blocks, hasLength(2));
    expect(document.blocks.first.textIn(source), contains('# Eerste'));
    expect(document.blocks.last.textIn(source), contains('```markdown'));
    expect(document.blockAt(source.indexOf('# Tweede'))?.slideNumber, 2);
  });

  test('reparse retains stable ids when a slide body changes', () {
    final before = MarkdownSourceDocument.parse(source);
    final after = before.reparse(source.replaceFirst('Tekst', 'Nieuwe tekst'));

    expect(after.blocks.map((block) => block.id), [
      before.blocks.first.id,
      before.blocks.last.id,
    ]);
  });

  test('replaceBlock patches only that source range', () {
    final before = MarkdownSourceDocument.parse(source);
    final second = before.blocks.last;
    final after = before.replaceBlock(second.id, '# Vervangen\n');

    expect(after.source, startsWith('---\nmarp: true\n---\n'));
    expect(after.source, contains(before.blocks.first.textIn(source)));
    expect(after.source, contains('# Vervangen'));
    expect(after.source, isNot(contains('# Tweede')));
  });
}
