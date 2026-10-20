// Tests voor de paginaverdeling van de documentpresentatie (#2487):
// `---` op blokniveau en hoofdstukkoppen zijn pagina-einden; een setext-
// onderstreping of een breuk in een fenced blok is dat niet. Dezelfde
// einden als de export (FILE_FORMAT.md §14.6).

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/document_pagination.dart';

List<String> pagesOf(String source, {bool chapterBreaks = false}) {
  final lines = source.split('\n');
  return [
    for (final p in documentPresentationPages(
      source,
      chapterBreaks: chapterBreaks,
    ))
      lines.sublist(p.start, p.end).join('\n'),
  ];
}

void main() {
  test('lege en kale bron leveren één pagina', () {
    expect(documentPresentationPages(''), hasLength(1));
    expect(pagesOf('alleen tekst'), ['alleen tekst']);
  });

  test('--- op blokniveau knipt een pagina', () {
    // De streep valt op de paginagrens; op het nieuwe vel is de pagina-
    // einde zelf al de scheiding.
    expect(pagesOf('eerste\n\n---\n\ntweede'), ['eerste\n', 'tweede']);
  });

  test('--- direct onder tekst is een setext-kop, geen breuk', () {
    expect(pagesOf('Titel\n---\n\nrest'), hasLength(1));
  });

  test('--- in een fenced blok is letterlijke tekst', () {
    expect(pagesOf('voor\n\n```\n---\n```\n\nna'), hasLength(1));
  });

  test('een hoofdstukkop opent alleen een pagina als de instelling aan is', () {
    const doc = 'intro\n\n# Hoofdstuk 2\n\nmeer';
    // De instelling "nieuw hoofdstuk op een nieuwe pagina" deelt — zonder
    // instelling is een kop gewoon inhoud op hetzelfde vel.
    expect(pagesOf(doc), hasLength(1));
    final pages = pagesOf(doc, chapterBreaks: true);
    expect(pages, hasLength(2));
    expect(pages[1], startsWith('# Hoofdstuk 2'));
  });

  test('een H1 aan het begin maakt geen lege eerste pagina', () {
    expect(pagesOf('# Titel\n\ntekst', chapterBreaks: true), hasLength(1));
  });

  test('witregels aan de kop van een vervolgpagina horen er niet bij', () {
    // De kopkop opent de tweede pagina; de witruimte ervoor hoort bij het
    // gat tussen de pagina's, niet bij het vel.
    expect(pagesOf('a\n\n\n\n# B\nx', chapterBreaks: true).last, '# B\nx');
  });
}
