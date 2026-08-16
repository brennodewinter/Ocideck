import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;

import '../services/table_of_contents.dart';

/// De `<!-- toc -->`-marker als blok-embed in de rijke-tekstlaag.
///
/// De marker is een HTML-commentaar, en rauwe HTML was tot dusver een reden om
/// de héle visuele modus te laten terugvallen op brontekst
/// ([markdownVisualLimitations]). Dat is voor precies deze regel onnodig: hij
/// draagt geen inhoud, alleen een plek. Door hem — net als de GFM-tabel — als
/// blok-embed door de heen-en-terugweg te dragen, blijft de visuele modus
/// visueel en komt de marker er byte-getrouw weer uit.
class EmbeddableToc extends BlockEmbed {
  EmbeddableToc() : super(tocType, tocMarker);

  /// [Embeddable]-type van de inhoudsopgave-marker.
  static const tocType = 'x-embed-toc';

  /// Uit de markdown-kant: de marker draagt geen gegevens, dus de attributen
  /// doen er niet toe.
  static EmbeddableToc fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableToc();

  /// Terug naar markdown: exact de marker die de rest van de keten herkent,
  /// gevolgd door een lege regel zodat hij een eigen blok blijft.
  static void toMdSyntax(Embed embed, StringSink out) {
    out
      ..writeln(tocMarker)
      ..writeln();
  }
}

/// Herkent een regel die alleen de `<!-- toc -->`-marker bevat en maakt er een
/// [EmbeddableToc]-element van, vóórdat de HTML-blokregel van de
/// markdown-parser hem als rauwe HTML opslokt.
class TocMarkerSyntax extends md.BlockSyntax {
  const TocMarkerSyntax();

  @override
  RegExp get pattern => tocMarkerLinePattern;

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance();
    // In een alinea gewikkeld, en niet kaal: `MarkdownToDelta` sluit een blok
    // met een eigen regel af voor `hr`, voor de tabel-embed, en voor een
    // alinea die alleen embeds bevat. Een kale embed erft anders de
    // blokopmaak van de volgende regel — een marker vóór een `##`-kop werd
    // dan zelf een kop.
    return md.Element('p', [md.Element.empty(EmbeddableToc.tocType)]);
  }
}
