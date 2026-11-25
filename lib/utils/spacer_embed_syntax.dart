import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;

import 'document_blank_lines.dart';

export 'document_blank_lines.dart' show spacerMarker, spacerMarkerLinePattern;

/// De spacer en zijn regelafsluiter vormen samen één verwijderbaar blok.
/// Anders laat het wissen van de embed een lege alinea achter.
bool endsWithSpacerLine(Document document, int index, int length) {
  final end = index + length;
  if (length == 0 || end >= document.length - 1) return false;
  final line = document.queryChild(end - 1).node;
  if (line is! Line || line.length != 2 || line.documentOffset != end - 1) {
    return false;
  }
  return switch (line.first) {
    Embed(value: Embeddable(type: EmbeddableSpacer.spacerType)) => true,
    _ => false,
  };
}

/// De `<!-- spacer -->`-marker als blok-embed in de rijke-tekstlaag.
///
/// Zonder deze embed was rauwe HTML-commentaar een reden om de héle visuele
/// modus op brontekst terug te laten vallen (`sourceFragmentRanges`).
/// De marker draagt geen inhoud — alleen een plek — en komt als één blok
/// door de heen-en-terugweg: byte-getrouw in de bron, atomair te selecteren
/// en te verwijderen in de editor.
class EmbeddableSpacer extends BlockEmbed {
  EmbeddableSpacer() : super(spacerType, spacerMarker);

  /// [Embeddable]-type van de tussenruimte-marker.
  static const spacerType = 'x-embed-spacer';

  /// Uit de markdown-kant: de marker draagt geen gegevens, dus de attributen
  /// doen er niet toe.
  static EmbeddableSpacer fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableSpacer();

  /// Terug naar markdown: exact de marker die de rest van de keten herkent.
  /// Zonder eigen regelafsluiter — `DeltaToMarkdown` sluit de alinea zelf al
  /// af; elke extra `writeln` hier werd een witregel méér bij elke invoeging.
  static void toMdSyntax(Embed embed, StringSink out) {
    out.write(spacerMarker);
  }
}

/// Herkent een regel die alleen de `<!-- spacer -->`-marker bevat en maakt er
/// een [EmbeddableSpacer]-element van, vóórdat de HTML-blokregel van de
/// markdown-parser hem als rauwe HTML opslokt.
class SpacerMarkerSyntax extends md.BlockSyntax {
  const SpacerMarkerSyntax();

  @override
  RegExp get pattern => spacerMarkerLinePattern;

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance();
    // In een alinea gewikkeld, en niet kaal: `MarkdownToDelta` sluit een blok
    // met een eigen regel af voor `hr`, voor de tabel-embed, en voor een
    // alinea die alleen embeds bevat. Een kale embed erft anders de
    // blokopmaak van de volgende regel — een marker vóór een `##`-kop werd
    // dan zelf een kop.
    return md.Element('p', [md.Element.empty(EmbeddableSpacer.spacerType)]);
  }
}
