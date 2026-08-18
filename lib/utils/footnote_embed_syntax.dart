/// Voetnoten als embeds in de rijke-tekstlaag, zodat de visuele modus visueel
/// blijft zodra er eentje in het document staat.
///
/// Vóór dit bestand was één voetnoot genoeg om de hele visuele editor terug te
/// werpen op brontekst: `[^1]` viel door de heen-en-terugweg uiteen in losse
/// tekens en de definitieregel werd een gewone alinea. Nu reizen ze mee als
/// embeds — dezelfde route die de GFM-tabel en de inhoudsopgave-marker al namen.
///
/// Bewust twee stuks, en niet één embed die het merkteken én de tekst draagt:
/// dan zou de definitie bij elke bewerking verhuizen naar de plek van de
/// verwijzing. De verwijzing is een inline-embed op zijn plek in de zin, de
/// definitie een blok-embed op zijn plek in het bestand, en de bytes komen er
/// dus uit zoals ze erin gingen.
library;

import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;

/// De verwijzing `[^label]` in de lopende tekst.
class EmbeddableFootnoteRef extends Embeddable {
  EmbeddableFootnoteRef(String label) : super(footnoteRefType, label);

  static const footnoteRefType = 'x-embed-footnote-ref';

  /// Het label van deze verwijzing.
  static String labelOf(Embeddable value) => (value.data ?? '').toString();

  static EmbeddableFootnoteRef fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableFootnoteRef(attributes['label'] ?? '');

  static void toMdSyntax(Embed embed, StringSink out) {
    out.write('[^${labelOf(embed.value)}]');
  }
}

/// De definitie `[^label]: de noot`, als eigen blok.
class EmbeddableFootnoteDef extends BlockEmbed {
  EmbeddableFootnoteDef(String label, String text)
    : super(footnoteDefType, '$label$_separator$text');

  static const footnoteDefType = 'x-embed-footnote-def';

  /// Scheidt het label van de tekst in de opgeslagen waarde. Een teken dat in
  /// geen van beide kan voorkomen: een label heeft geen witruimte (en dus geen
  /// regeleinde), en de tekst van een noot is één regel.
  static const _separator = '\n';

  static ({String label, String text}) parse(Embeddable value) {
    final raw = (value.data ?? '').toString();
    final split = raw.indexOf(_separator);
    return split < 0
        ? (label: raw, text: '')
        : (label: raw.substring(0, split), text: raw.substring(split + 1));
  }

  static EmbeddableFootnoteDef fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableFootnoteDef(
        attributes['label'] ?? '',
        attributes['text'] ?? '',
      );

  static void toMdSyntax(Embed embed, StringSink out) {
    final note = parse(embed.value);
    out.write('[^${note.label}]: ${note.text}');
  }
}

/// Herkent `[^label]` in de lopende tekst.
///
/// Vóór de link-syntax van de parser: die kijkt naar `[`, en een verwijzing
/// zonder deze regel eindigde als losse tekens.
class FootnoteRefSyntax extends md.InlineSyntax {
  FootnoteRefSyntax() : super(r'\[\^([^\]\s]+)\](?!:)');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.empty(EmbeddableFootnoteRef.footnoteRefType)
        ..attributes['label'] = match.group(1)!,
    );
    return true;
  }
}

/// Herkent een definitieregel `[^label]: de noot`, inclusief de ingesprongen
/// vervolgregels die erbij horen.
///
/// Die vervolgregels moeten mee: een ingesprongen regel is voor de
/// markdown-parser anders een codeblok, en dan kwam `    en de rest.` er als
/// ```-fence weer uit — echte tekst van de gebruiker, veranderd in code. Ze
/// worden aan de noot geplakt met een spatie ertussen, precies zoals de
/// weergave ze ook leest.
///
/// Wat daarmee verandert is de regelval in de bron: een noot die over twee
/// regels stond, komt na een bewerking in de visuele editor als één regel terug.
/// De tekst is dan identiek; alleen de regelovergang is weg. Dat is de enige
/// plek waar deze route de bytes aanraakt, en FILE_FORMAT.md §14.9 zegt het
/// hardop in plaats van het stil te laten gebeuren.
class FootnoteDefSyntax extends md.BlockSyntax {
  const FootnoteDefSyntax();

  @override
  RegExp get pattern => RegExp(r'^ {0,3}\[\^([^\]\s]+)\]:[ \t]*(.*)$');

  /// Een vervolgregel: ingesprongen met vier spaties of een tab, en niet leeg.
  /// Dezelfde regel als Pandoc, en de enige die een gewone alinea eronder niet
  /// per ongeluk opslokt.
  static final _continuation = RegExp(r'^(?: {4}|\t)\s*\S');

  @override
  md.Node? parse(md.BlockParser parser) {
    final match = pattern.firstMatch(parser.current.content)!;
    parser.advance();
    final parts = [match.group(2)!.trim()];
    while (!parser.isDone && _continuation.hasMatch(parser.current.content)) {
      parts.add(parser.current.content.trim());
      parser.advance();
    }
    // In een alinea gewikkeld, om dezelfde reden als de inhoudsopgave-marker:
    // een kale embed erft de blokopmaak van de regel erna, en een definitie
    // vlak vóór een `##` werd dan zelf een kop.
    return md.Element('p', [
      md.Element.empty(EmbeddableFootnoteDef.footnoteDefType)
        ..attributes['label'] = match.group(1)!
        ..attributes['text'] = parts.where((p) => p.isNotEmpty).join(' '),
    ]);
  }
}
