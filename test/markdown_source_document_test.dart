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

  test('code fences keep separator lines in the same slide (#3115)', () {
    for (final fenced in [
      '~~~yaml\n---\nname: A\n~~~',
      '````markdown\n```\n---\nname: A\n````',
    ]) {
      final text = '---\nmarp: true\n---\n\n# Eerste\n\n$fenced\n---\n# Tweede';
      final document = MarkdownSourceDocument.parse(text);

      expect(document.blocks.map((block) => block.textIn(text).trim()), [
        '# Eerste\n\n$fenced',
        '# Tweede',
      ]);
      expect(document.blockAt(text.indexOf('# Tweede'))?.slideNumber, 2);
    }
  });

  test('cursor on a separator stays with the preceding slide (#3115)', () {
    const text = '# Eerste\r\n---\r\n# Tweede\r\n---\r\n# Derde';
    final document = MarkdownSourceDocument.parse(text);
    final separator = text.indexOf('---');
    final second = text.indexOf('# Tweede');

    for (var offset = separator; offset < second; offset++) {
      expect(document.blockAt(offset)?.slideNumber, 1);
    }
    expect(document.blockAt(second)?.slideNumber, 2);
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
