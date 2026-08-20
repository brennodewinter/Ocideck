/// Een afbeelding `![alt](bron)` als embed in de rijke-tekstlaag, zodat de
/// visuele modus er niet op omvalt en de alt-tekst blijft staan.
///
/// Zonder dit bestand ging een afbeelding langs de standaardweg van
/// `markdown_quill`: die maakt er een `image`-embed van die alléén de bron
/// draagt. Dat kostte twee dingen tegelijk.
///
/// **Een uitzondering.** Voor `image` staat er in deze editor geen bouwer, dus
/// Quill wierp bij het tekenen `UnimplementedError: Embeddable type "image" is
/// not supported` en het schrijfvlak viel om — geen document meer, alleen een
/// foutscherm.
///
/// **En stil verlies.** De terugweg schrijft `![](bron)`: de alt-tekst is er
/// niet meer. Eén bewerking ergens anders in het document was genoeg om overal
/// de toegankelijke omschrijving weg te gooien, zonder melding en zonder weg
/// terug.
///
/// Dezelfde route als de tabel, de inhoudsopgave en de voetnoot lost beide op:
/// de embed draagt de **hele** markdown van de afbeelding als tekst, en de
/// terugweg schrijft die er letterlijk weer uit. Wat atomair reist, kan
/// onderweg niet stukgaan.
library;

import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;

/// De afbeelding op zijn plek in de zin. Inline, want dat is wat een afbeelding
/// in Markdown is: `![](a.png)![](b.png)` op één regel zijn twee afbeeldingen
/// naast elkaar, geen twee alinea's.
class EmbeddableMarkdownImage extends Embeddable {
  EmbeddableMarkdownImage(String markdown) : super(imageType, markdown);

  static const imageType = 'x-embed-image';

  /// De markdown zoals de schrijver hem tikte — inclusief alt-tekst en een
  /// eventuele titel. Dit is de opgeslagen waarde; er wordt niets afgeleid.
  static String markdownOf(Embeddable value) => (value.data ?? '').toString();

  // Statische fabrieken zijn het contract van markdown_quill.
  // ignore: prefer_constructors_over_static_methods
  static EmbeddableMarkdownImage fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableMarkdownImage(attributes['markdown'] ?? '');

  static void toMdSyntax(Embed embed, StringSink out) {
    out.write(markdownOf(embed.value));
  }

  /// De alt-tekst en de bron, voor wie de afbeelding wil *tonen*. Faalt nooit:
  /// wat niet te lezen is, komt als lege string terug en de opgeslagen markdown
  /// blijft ongemoeid.
  static ({String alt, String source}) parse(Embeddable value) {
    final match = _pattern.firstMatch(markdownOf(value));
    if (match == null) return (alt: '', source: '');
    return (alt: match[1] ?? '', source: _stripTitle(match[2] ?? ''));
  }

  /// `a.png "Een titel"` → `a.png`. De titel hoort bij de markdown, niet bij
  /// het pad.
  static String _stripTitle(String source) {
    final trimmed = source.trim();
    final space = trimmed.indexOf(RegExp(r'\s'));
    return space < 0 ? trimmed : trimmed.substring(0, space);
  }
}

/// Herkent `![alt](bron)` in de lopende tekst.
///
/// Ruim in de bron (`[^)]*`), zodat `![a](b.png "titel")` en een pad met
/// spaties er ook onder vallen. Wat er tóch buiten valt — een bron met haakjes
/// erin, of de verwijzingsvorm `![alt][label]` — loopt naar de standaardweg en
/// wordt daar een gewone `image`-embed; die vangt de onbekende-embed-bouwer op
/// in plaats van het schrijfvlak te laten omvallen.
class MarkdownImageSyntax extends md.InlineSyntax {
  MarkdownImageSyntax() : super(_source);

  static const _source = r'!\[([^\]]*)\]\(([^)]*)\)';

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    parser.addNode(
      md.Element.empty(EmbeddableMarkdownImage.imageType)
        ..attributes['markdown'] = match[0]!,
    );
    return true;
  }
}

final _pattern = RegExp(MarkdownImageSyntax._source);
