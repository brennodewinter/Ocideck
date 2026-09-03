import 'package:flutter_test/flutter_test.dart';
import 'package:markdown_quill/markdown_quill.dart';
import 'package:ocideck/utils/list_block_embed_syntax.dart';
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

  test('tijdlijn-marker lekt geen kop-opmaak bij round-trip (#1709)', () {
    // Regressie: een kale tijdlijn-embed deelde een Quill-regel met de
    // volgende kop, waardoor `## ` voor `<!-- timeline -->` kwam te staan.
    const source = '''# Incident

<!-- timeline -->
| Tijd | Gebeurtenis |
| --- | --- |
| 10:00 | Start |

## Analyse

Tekst hier.
''';

    final document = MarkdownQuillCodec.documentFromMarkdown(source);
    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    expect(restored, isNot(contains('# <!-- timeline')));
    expect(restored, isNot(contains('## <!-- timeline')));
    expect(restored, contains('<!-- timeline -->'));
    expect(restored, contains('## Analyse'));
    expect(restored, contains('| 10:00 | Start |'));
  });

  test('tijdlijn gevolgd door gewone tabel lekt niet (#1709)', () {
    const source = '''# Rapport

<!-- timeline -->
| Tijd | Gebeurtenis |
| --- | --- |
| 10:00 | Start |

| Nr | Bevinding |
| --- | --- |
| 1 | Test |
''';

    final document = MarkdownQuillCodec.documentFromMarkdown(source);
    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    expect(restored, isNot(contains('# <!-- timeline')));
    expect(restored, contains('<!-- timeline -->'));
    expect(restored, contains('| Nr | Bevinding |'));
  });

  test('tijdlijn na alinea gevolgd door kop lekt niet (#1709)', () {
    const source = '''Inleiding.

<!-- timeline -->
| Tijd | Gebeurtenis |
| --- | --- |
| 10:00 | Start |

## Analyse

Tekst.
''';

    final document = MarkdownQuillCodec.documentFromMarkdown(source);
    final restored = MarkdownQuillCodec.markdownFromDocument(document);

    expect(restored, isNot(contains('## <!-- timeline')));
    expect(restored, contains('<!-- timeline -->'));
    expect(restored, contains('## Analyse'));
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

  group('blokinhoud in een lijstitem reist verliesvrij (#1925)', () {
    // De visuele modus herschreef blokinhoud in een lijstitem stil: een
    // codeblok verloor zijn fences, een tabel verloor zijn bullet, en een
    // mermaid-diagram plakte aan de bulletregel. Quill's vlakke model kan een
    // codeblok niet als kind van een lijstitem dragen (`list` en `codeBlock`
    // zijn exclusief), dus de codec voert het blok nu als `x-embed-list-block`
    // met de inspringing bewaard.

    String roundTrip(String markdown) =>
        MarkdownQuillCodec.markdownFromDocument(
          MarkdownQuillCodec.documentFromMarkdown(markdown),
        );

    test('een codeblok in een lijstitem behoudt zijn fences en inspringing', () {
      const source =
          '- Stap een:\n\n  ```dart\n  void main() {}\n  ```\n\n- Stap twee\n';

      final document = MarkdownQuillCodec.documentFromMarkdown(source);

      // Het codeblok reist als x-embed-list-block, niet als platte tekst in
      // de bulletregel.
      final embeds = document
          .toDelta()
          .toList()
          .where((op) => op.data is Map)
          .map((op) => (op.data as Map).keys.first)
          .toList();
      expect(
        embeds,
        contains(EmbeddableListBlock.listBlockType),
        reason: 'het codeblok moet als embed in het document staan',
      );

      final restored = MarkdownQuillCodec.markdownFromDocument(document);

      // De fences en de inspringing overleven de rondgang.
      expect(restored, contains('  ```dart'));
      expect(restored, contains('  void main() {}'));
      expect(restored, contains('  ```'));
      expect(restored, contains('- Stap een:'));
      expect(restored, contains('- Stap twee'));
      // De inhoud is niet aan de bulletregel geplakt.
      expect(restored, isNot(contains('- Stap een:void main')));
    });

    test('een tabel in een lijstitem behoudt zijn bullet en inspringing', () {
      const source =
          '- Stap een:\n\n  | A | B |\n  | --- | --- |\n  | 1 | 2 |\n\n- Stap twee\n';

      final restored = roundTrip(source);

      expect(restored, contains('- Stap een:'));
      expect(restored, contains('  | A | B |'));
      expect(restored, contains('  | --- | --- |'));
      expect(restored, contains('  | 1 | 2 |'));
      expect(restored, contains('- Stap twee'));
      // Het item verliest zijn bullet niet aan de tabel.
      expect(restored, isNot(contains('Stap een:\n\n- | A | B |')));
    });

    test('een mermaid-diagram in een lijstitem behoudt zijn fence en inhoud', () {
      const source =
          '- Stap een:\n\n  ```mermaid\n  graph TD; A-->B;\n  ```\n\n- Stap twee\n';

      final restored = roundTrip(source);

      expect(restored, contains('  ```mermaid'));
      expect(restored, contains('  graph TD; A-->B;'));
      expect(restored, contains('- Stap een:'));
      expect(restored, contains('- Stap twee'));
      // Het diagram is niet aan de bulletregel geplakt.
      expect(restored, isNot(contains('- Stap een:```mermaid')));
    });

    test('een geordende lijst met een codeblok behoudt zijn nummering', () {
      const source =
          '1. Stap een:\n\n   ```dart\n   void main() {}\n   ```\n\n2. Stap twee\n';

      final restored = roundTrip(source);

      expect(restored, contains('1. Stap een:'));
      expect(restored, contains('   ```dart'));
      expect(restored, contains('   void main() {}'));
      expect(restored, contains('2. Stap twee'));
    });
  });
}
