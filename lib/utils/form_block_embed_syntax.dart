/// Houdt de blokken van een formulier bijeen die de rijke-tekstlaag niet mag
/// aanraken (FORM_INTAKE.md §4.9, rij 2–3 van de keten; naar het model van
/// `pentest_block_embed_syntax.dart` en PENTEST_DOCUMENT.md §5.5).
///
/// **Waarom atomair.** `DeltaToMarkdown` escapet elk leesteken en
/// `_normalizeQuillOutput` haalt die escapes weer weg. Een antwoord dat `## kop`
/// of `1.` bevat, of een label met een blokquote, zou er niet byte-gelijk
/// uitkomen — en een veld is geen tekst die mag stromen: de markers eromheen en de
/// grens tussen label en antwoord zijn structuur. Dus een heel veld, de
/// `form`-marker en de notice reizen elk als **één embed** met hun bron verbatim.
///
/// De grens woont niet hier maar in `packages/ocideck_form_core`
/// (`formBlockLength`): deze syntax stelt per regel een vraag aan die ene regel in
/// plaats van de lus te kopiëren — dezelfde keuze als bij het pentestblok.
library;

import 'package:flutter_quill/flutter_quill.dart' hide Node;
import 'package:markdown/markdown.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

/// Eén blok van een formulier: de kop, een notice of een heel veld.
class FormBlockSyntax extends BlockSyntax {
  const FormBlockSyntax();

  // Alleen een voorfilter: `canParse` beslist, via de gedeelde grensregel.
  @override
  RegExp get pattern => RegExp(r'^[ \t]{0,3}<!--');

  @override
  bool canEndBlock(BlockParser parser) => false;

  @override
  bool canParse(BlockParser parser) => _length(parser) != null;

  @override
  Node? parse(BlockParser parser) {
    final length = _length(parser)!;
    final value = StringBuffer();
    for (var i = 0; i < length; i++) {
      if (i > 0) value.write('\n');
      value.write(parser.current.content);
      parser.advance();
    }
    // In een alinea gewikkeld om blokopmaak-lekkage te voorkomen (#1709): een
    // kale embed erft anders de `header`-attribuut van een volgende kop.
    return Element('p', [
      Element.empty(EmbeddableFormBlock.blockType)
        ..attributes['data'] = value.toString(),
    ]);
  }

  /// De lengte van het blok dat op de huidige regel begint — via de ene
  /// grensregel van het pakket. `peek(0)` is de huidige regel; daarom wordt die
  /// apart genomen.
  static int? _length(BlockParser parser) => formBlockLength(
    (offset) =>
        offset == 0 ? parser.current.content : parser.peek(offset)?.content,
  );
}

/// Eén embeddable voor alle drie. De soort staat in de bloktekst zelf — de
/// markerregel is de eerste regel van `data` — dus een tweede plek die hem
/// bijhoudt zou alleen maar uit de pas kunnen lopen.
class EmbeddableFormBlock extends BlockEmbed {
  static const blockType = 'x-embed-form-block';

  EmbeddableFormBlock(String data) : super(blockType, data);

  // Statische fabrieken zijn het contract van markdown_quill.
  // ignore: prefer_constructors_over_static_methods
  static EmbeddableFormBlock fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableFormBlock(attributes['data']!);

  static void toMdSyntax(Embed embed, StringSink out) {
    out
      ..writeln(embed.value.data)
      ..writeln();
  }
}
