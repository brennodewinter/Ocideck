import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/text_search.dart';

void main() {
  test('zichtbare frase over opmaak heen behoudt exacte bronposities', () {
    const source = 'een **belangrijke** passage en échte 🐈 tekst';
    final found = findVisibleMarkdownMatches(source, 'belangrijke passage');
    expect(found, [TextMatchRange(6, 27)]);
    expect(
      visibleMarkdownText(source),
      'een belangrijke passage en échte 🐈 tekst',
    );
  });
  test('entities en aangrenzende opmaak houden hun echte bronbereik', () {
    const source = 'A **&lt;** B &amp; C';
    final found = findVisibleMarkdownMatches(source, '<');
    expect(found.length, 1);
    expect(source.substring(found.single.start, found.single.end), '&lt;');
    const adjacent = '**vet**`**letterlijk**`';
    final code = findVisibleMarkdownMatches(adjacent, '**letterlijk**').single;
    expect(adjacent.substring(code.start, code.end), '**letterlijk**');
  });

  test('labels en zichtbare code tellen, doelen en specificaties niet', () {
    const source =
        '[kat](https://kat.invalid) kat\n'
        '```dart\nkat **letterlijk**\n```\n'
        '```mermaid\nkat --> hond\n```\n<!-- kat -->\n';
    final found = findVisibleMarkdownMatches(source, 'kat');
    expect(found.length, 3);
    expect(found[1].start, source.indexOf(' kat') + 1);
    expect(findVisibleMarkdownMatches(source, 'invalid'), isEmpty);
    expect(findVisibleMarkdownMatches(source, '**letterlijk**').length, 1);
  });
}
