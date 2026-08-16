import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_quill/markdown_quill.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/toc_embed_syntax.dart';

void main() {
  test('markdown round-trips through quill for basic formatting', () {
    const source = '''## Kop

Dit is **vet** en *cursief* met `code`.

- item een
- item twee
''';

    final document = MarkdownQuillCodec.documentFromMarkdown(source);
    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    expect(restored, contains('## Kop'));
    expect(restored, contains('**vet**'));
    expect(restored, contains('*cursief*'));
    expect(restored, contains('`code`'));
    expect(restored, contains('- item een'));
  });

  test('een GFM-tabel wordt een embed en round-trip\'t byte-getrouw', () {
    const source = '''# Rapport

Inleiding.

| Team | Omzet | Groei |
| --- | ---: | ---: |
| Ontwerp | 120 | 12% |
| Bouw | 340 | 8% |

Afsluiting.''';

    final document = MarkdownQuillCodec.documentFromMarkdown(source);

    // De tabel landt als één blok-embed (x-embed-table), niet als losse woorden.
    final embeds = document
        .toDelta()
        .toList()
        .where((op) => op.data is Map)
        .map((op) => (op.data as Map).keys.first)
        .toList();
    expect(
      embeds,
      contains(EmbeddableTable.tableType),
      reason: 'de tabel moet als embed in het document staan',
    );

    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    // Kop, prosa én de tabel mét kolomuitlijning overleven de reis.
    expect(restored, contains('# Rapport'));
    expect(restored, contains('| Team | Omzet | Groei |'));
    expect(restored, contains('| --- | ---: | ---: |'));
    expect(restored, contains('| Ontwerp | 120 | 12% |'));
    expect(restored, contains('| Bouw | 340 | 8% |'));
    expect(restored, contains('Afsluiting.'));
  });

  test('de inhoudsopgave-marker wordt een embed en komt er weer uit', () {
    // Regressie: `<!-- toc -->` viel als rauwe HTML uiteen, waardoor de visuele
    // modus het hele document als brontekst toonde zodra iemand een
    // inhoudsopgave invoegde.
    const source = '''# Rapport

<!-- toc -->

## Eerste

Tekst.''';

    final document = MarkdownQuillCodec.documentFromMarkdown(source);

    final embeds = document
        .toDelta()
        .toList()
        .where((op) => op.data is Map)
        .map((op) => (op.data as Map).keys.first)
        .toList();
    expect(
      embeds,
      contains(EmbeddableToc.tocType),
      reason: 'de marker moet als embed in het document staan',
    );

    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    expect(restored, contains('<!-- toc -->'));
    expect(restored, contains('# Rapport'));
    expect(restored, contains('## Eerste'));
    // De marker blijft één blok — geen losse `<!--`-brokken in de tekst.
    expect(RegExp('<!--').allMatches(restored).length, 1);
  });

  test('een scheiding komt er als `---` uit, niet als `- - -`', () {
    // `DeltaToMarkdown` schrijft `- - -`. Betekenis-identiek, maar OciDeck
    // schrijft en documenteert `---` (het pagina-einde in de documentmodus);
    // zonder de omzetting herschreef één visuele bewerking stilzwijgend elke
    // scheiding in het bestand van de gebruiker.
    final document = MarkdownQuillCodec.documentFromMarkdown(
      'Voor.\n\n---\n\nNa.',
    );
    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    expect(restored, contains('---'));
    expect(restored, isNot(contains('- - -')));
  });
}
