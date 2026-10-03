// Een formulier blijft visueel bewerkbaar, en wat atomair reist komt
// byte-identiek uit een échte Quill-rondgang (FORM_INTAKE.md §4.9, rij 2–5).
//
// Zelfde bewijsvorm als `pentest_visual_mode_test.dart`: "de poort slaat het
// bereik over" is alleen veilig als dat bereik ook werkelijk als één embed door
// de conversie gaat. Overslaan zonder atomiciteit is stille corruptie — een
// antwoord met `## kop` komt er als échte sectiekop uit. Daarom toetst dit
// bestand beide kanten tegen elkaar.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/form_document_blocks.dart';
import 'package:ocideck/utils/form_block_embed_syntax.dart';
import 'package:ocideck/utils/markdown_quill_codec.dart';
import 'package:ocideck/utils/markdown_visual_compatibility.dart';

/// Een geldig formulier waarvan de antwoorden precies bevatten wat de conversie
/// anders zou aanraken: een kop, een genummerde lijst, een blockquote, een
/// escape en een regelovergang.
const String _formulier = '''<!-- form id=f version=1 -->
# Formulier

Welkom.

<!-- notice -->
We bewaren je gegevens.
<!-- /notice -->

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
Sari
<!-- /field id=naam -->

<!-- field id=verhaal type=prose -->
## Het verhaal
> uitleg
<!-- answer -->
## kop in een antwoord

1. eerste
2. tweede

tekst met \\* een escape<br>tweede regel
<!-- /field id=verhaal -->

Tot slot.
''';

int _embeds(String markdown) =>
    MarkdownQuillCodec.documentFromMarkdown(markdown)
        .toDelta()
        .toList()
        .where(
          (op) =>
              op.value is Map &&
              (op.value as Map).containsKey(EmbeddableFormBlock.blockType),
        )
        .length;

void main() {
  test('een geldig formulier blijft visueel bewerkbaar', () {
    // Zonder de blokbewuste poort was élke `<!--`-regel rawHtml: één formulier
    // en de hele editor viel terug op brontekst.
    expect(markdownVisualLimitations(_formulier), isEmpty);
    expect(markdownRoundTripsVisually(_formulier), isTrue);
  });

  test('elk blok komt byte-identiek uit de Quill-rondgang', () {
    final scan = scanFormBlocks(_formulier);
    expect(scan.blocks, hasLength(4));

    // Eerst bewijzen dat de embeds ook echt aangrijpen; anders kan de
    // rondgangstoets slagen doordat de tekst toevallig heel blijft.
    expect(_embeds(_formulier), 4);

    final doc = MarkdownQuillCodec.documentFromMarkdown(_formulier);
    final terug = MarkdownQuillCodec.markdownFromDocument(doc);
    final lines = _formulier.split('\n');
    for (final block in scan.blocks) {
      final bron = lines.sublist(block.start, block.end).join('\n');
      expect(
        terug,
        contains(bron),
        reason: 'het blok op regel ${block.start} is door de conversie geraakt',
      );
    }
    // De kanaries: dit zou de conversie herschrijven als het niet atomair was.
    expect(terug, contains('## kop in een antwoord'));
    expect(terug, contains('1. eerste\n2. tweede'));
    expect(terug, contains('tekst met \\* een escape<br>tweede regel'));
  });

  test('de opslagnormalisatie raakt een blok niet, de tekst ervoor wel', () {
    // Het label draagt een zacht koppelteken en een NBSP: onzichtbaar, maar
    // bytes in de sjabloontekst. Normaliseren zou het label laten afwijken van
    // het gepubliceerde formulier.
    const bron =
        'Een \\* alinea.\n'
        '\n'
        '<!-- form id=f -->\n'
        '\n'
        '<!-- field id=a type=text -->\n'
        '**Na\u00ADam\u00A0hier**\n'
        '<!-- answer -->\n'
        'a \\_ b\n'
        '<!-- /field id=a -->\n'
        '\n'
        'Na \\* afloop.\n';
    expect(_embeds(bron), 2);
    final terug = MarkdownQuillCodec.markdownFromDocument(
      MarkdownQuillCodec.documentFromMarkdown(bron),
    );
    expect(
      terug,
      contains(
        '**Na\u00ADam\u00A0hier**\n'
        '<!-- answer -->\n'
        'a \\_ b\n'
        '<!-- /field id=a -->',
      ),
    );
    // Buiten het blok blijft de bestaande normalisatie gelden: de prozaregels
    // zijn niet in het blok getrokken.
    expect(terug, startsWith('Een * alinea.'));
    expect(terug, endsWith('Na * afloop.'));
  });

  test('een tweede rondgang verandert niets meer', () {
    final een = MarkdownQuillCodec.markdownFromDocument(
      MarkdownQuillCodec.documentFromMarkdown(_formulier),
    );
    final twee = MarkdownQuillCodec.markdownFromDocument(
      MarkdownQuillCodec.documentFromMarkdown(een),
    );
    expect(twee, een);
  });

  test('een kapot formulier valt terug op brontekst — zichtbaar, niet stil', () {
    // Een veld zonder sluitmarker is geen ParsedForm: dan zijn er geen blokken,
    // dus geen atomaire reis, dus is de bronmodus de eerlijke uitkomst.
    const kapot = '''<!-- form id=f -->
<!-- field id=naam type=text -->
**Naam**
<!-- answer -->
Sari
''';
    expect(scanFormBlocks(kapot).blocks, isEmpty);
    expect(
      markdownVisualLimitations(kapot),
      contains(MarkdownVisualLimitation.rawHtml),
    );
  });

  test('een document zonder formulier is onveranderd', () {
    const gewoon = 'Een alinea.\n\n<!-- toc -->\n';
    expect(_embeds(gewoon), 0);
  });

  test('de embed schrijft zijn bron terug met een lege regel erna', () {
    final doc = MarkdownQuillCodec.documentFromMarkdown(
      '<!-- form id=f -->\n\nTekst.\n',
    );
    final terug = MarkdownQuillCodec.markdownFromDocument(doc);
    expect(terug, startsWith('<!-- form id=f -->\n'));
    expect(terug, contains('Tekst.'));
  });
}
