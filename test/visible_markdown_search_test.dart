import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/text_search.dart';

void main() {
  test('ATX-sluithek en voetnootdefinitiemarker zijn onzichtbare syntax', () {
    const source = '# Titel ###\n\n[^a]: zichtbare voetnoot';
    expect(findVisibleMarkdownMatches(source, '#'), isEmpty);
    expect(findVisibleMarkdownMatches(source, ':'), isEmpty);
    expect(findVisibleMarkdownMatches(source, 'zichtbare voetnoot').length, 1);
    expect(visibleMarkdownText('# ###'), '');
  });

  test('softbreaks vormen een zichtbare frase met exacte bronposities', () {
    const source = 'Een **belangrijke**\n  [passage](https://example.invalid).';
    final match = findVisibleMarkdownMatches(
      source,
      'belangrijke passage',
    ).single;
    expect(
      source.substring(match.start, match.end),
      'belangrijke**\n  [passage',
    );
    expect(visibleMarkdownText(source), 'Een belangrijke passage.');
    expect(
      findVisibleMarkdownMatches(
        '> belangrijke\n> passage',
        'belangrijke passage',
      ).length,
      1,
    );
    expect(
      findVisibleMarkdownMatches(
        '- belangrijke\n  passage',
        'belangrijke passage',
      ).length,
      1,
    );
  });

  test('harde regeleinden, blokgrenzen en code worden niet samengevoegd', () {
    expect(visibleMarkdownText(r'een\'), r'een\');
    for (final source in [
      'een  \npassage',
      'een\\\npassage',
      'een\n\npassage',
      '# een\npassage',
      'een\n> passage',
      '- een\n- passage',
      '~~~text\neen\npassage\n~~~',
      '```text\neen\npassage\n```',
    ]) {
      expect(
        findVisibleMarkdownMatches(source, 'een passage'),
        isEmpty,
        reason: source,
      );
    }
  });

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
