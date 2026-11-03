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

  test('meerregelige noten volgen getrimde rendertekst en bronbereiken', () {
    const source =
        'Een noot[^a].\n\n[^a]: **belangrijke**\n    passage en\n\tmeer tekst';
    final projection = VisibleMarkdownText(source);
    final match = projection.matches('belangrijke passage en meer').single;
    expect(
      source.substring(match.start, match.end),
      'belangrijke**\n    passage en\n\tmeer',
    );
    expect(
      projection.context(match),
      contains('belangrijke passage en meer tekst'),
    );
    expect(
      VisibleMarkdownText('Een noot[^a].\n\n[^a]: eerste\n    - tweede').text,
      contains('eerste - tweede'),
    );
    expect(
      VisibleMarkdownText(
        'Een noot[^a].\n\n[^a]: eerste\n    | tweede [^b] |',
      ).matches('| tweede [^b] |'),
      hasLength(1),
    );
  });

  test('alleen de paginaprojectie verbergt ongebruikte definities', () {
    const source =
        'Een gebruikte noot[^a].\n\n[^orphan]: verborgenanker\n    vervolganker\n\n[^a]: zichtbaaranker';
    final editable = VisibleMarkdownText(source);
    final rendered = VisibleMarkdownText(
      source,
      includeUnreferencedFootnotes: false,
    );
    expect(editable.matches('verborgenanker vervolganker'), hasLength(1));
    expect(rendered.matches('verborgenanker'), isEmpty);
    expect(rendered.matches('vervolganker'), isEmpty);
    final hit = rendered.matches('zichtbaaranker').single;
    expect(source.substring(hit.start, hit.end), 'zichtbaaranker');
    const code = '```text\n[^orphan]: letterlijk\n```';
    expect(
      VisibleMarkdownText(
        code,
        includeUnreferencedFootnotes: false,
      ).matches('[^orphan]'),
      hasLength(1),
    );
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
