/// De ```mermaid-fence als blok-embed in de rijke-tekstlaag.
///
/// **Waarom een embed en niet "gewoon een codeblok".** Een mermaid-fence is
/// geldige, draagbare Markdown en viel daarom nooit onder
/// [markdownVisualLimitations] — de scanner slaat alles binnen een fence
/// bewust over. Het gevolg was dat de visuele modus wél openging, maar het
/// diagram er als monospace brontekst in stond terwijl lezer, voorvertoning,
/// Pagina's, PDF en HTML-export het diagram tekenden. Niet een terugval naar
/// brontekst dus, en ook niet de vangnet-bouwer: gewoon een gat tussen de
/// belofte in `DOCUMENT_MODE.md` §4.3 en wat de editor liet zien (#1920).
///
/// **Byte-getrouw.** De embed draagt de héle fence — de openingsregel, de
/// inhoud en de sluitregel — en [EmbeddableMermaid.toMdSyntax] schrijft die
/// verbatim terug. De rijke-tekstlaag komt er niet aan, dus een `%%{init}`-
/// directive, een `<br/>` in een label of een backslash in een tekst overleeft
/// een rondgang door de visuele editor ongeschonden. Dat is dezelfde reden als
/// bij de pentest-envelop: `DeltaToMarkdown` escapet leestekens, en een diagram
/// is geen proza.
library;

import 'package:flutter_quill/flutter_quill.dart' hide Node;
import 'package:markdown/markdown.dart';

/// Een fence-openingsregel die `mermaid` als taal noemt: ` ```mermaid `,
/// eventueel met spaties eromheen. Meer tildes of extra info-woorden achter de
/// taal horen bij een gewoon codeblok — die laat deze syntax met opzet liggen,
/// zodat de standaardregel ze afhandelt.
final RegExp mermaidFenceOpenPattern = RegExp(r'^\s{0,3}```[ \t]*mermaid[ \t]*$');

/// De sluitregel van diezelfde fence.
final RegExp _mermaidFenceClosePattern = RegExp(r'^\s{0,3}```[ \t]*$');

/// Herkent een volledige ```mermaid-fence en maakt er één [EmbeddableMermaid]
/// van, vóórdat de standaard-fenceregel van de markdown-parser er een codeblok
/// van maakt.
class MermaidFenceSyntax extends BlockSyntax {
  const MermaidFenceSyntax();

  @override
  RegExp get pattern => mermaidFenceOpenPattern;

  /// Een fence eindigt niet op een lege regel: alles tot de sluit-fence hoort
  /// erbij, witregels inbegrepen.
  @override
  bool canEndBlock(BlockParser parser) => false;

  @override
  Node? parse(BlockParser parser) {
    final value = StringBuffer(parser.current.content);
    parser.advance();
    while (!parser.isDone &&
        !_mermaidFenceClosePattern.hasMatch(parser.current.content)) {
      value.write('\n${parser.current.content}');
      parser.advance();
    }
    // De sluitregel hoort bij de fence; ontbreekt hij (onafgesloten bron), dan
    // draagt de embed wat er wél stond in plaats van de rest op te slokken.
    if (!parser.isDone) {
      value.write('\n${parser.current.content}');
      parser.advance();
    }
    // In een alinea gewikkeld om blokopmaak-lekkage te voorkomen (#1709): een
    // kale embed erft anders het `header`-attribuut van een volgende kop.
    return Element('p', [
      Element.empty(EmbeddableMermaid.mermaidType)
        ..attributes['data'] = value.toString(),
    ]);
  }
}

/// De fence als blok-embed. `data` is de fence inclusief beide ```-regels, zodat
/// de terugweg hem verbatim kan wegschrijven.
class EmbeddableMermaid extends BlockEmbed {
  EmbeddableMermaid(String data) : super(mermaidType, data);

  /// [Embeddable]-type van de mermaid-fence.
  static const mermaidType = 'x-embed-mermaid';

  // Statische fabrieken zijn het contract van markdown_quill.
  // ignore: prefer_constructors_over_static_methods
  static EmbeddableMermaid fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableMermaid(attributes['data']!);

  static void toMdSyntax(Embed embed, StringSink out) {
    out
      ..writeln(embed.value.data)
      ..writeln();
  }
}
