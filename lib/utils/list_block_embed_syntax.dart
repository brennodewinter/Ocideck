/// Blokinhoud (codeblok, tabel, mermaid) die binnen een lijstitem staat, reist
/// als `x-embed-list-block`-embed door de rijke-tekstlaag.
///
/// **Waarom een embed.** Quills documentmodel is vlak: een regel is óf een
/// lijstitem óf een codeblok — `list` en `codeBlock` zijn exclusieve
/// blokattributen. Een codeblok in een lijstitem kon daardoor niet als kind van
/// het lijstitem reizen en werd aan de bulletregel geplakt, met stil verlies van
/// de fence en de inspringing als gevolg (#1925). De embed draagt de ruwe
/// markdown van het blok mét inspringing, zodat de terugweg hem verbatim kan
/// wegschrijven en de rondgang verliesvrij is.
///
/// **Byte-getrouw.** De data is de ruwe markdown van het blok, inclusief de
/// inspringing die het kind van het lijstitem maakt. [toMdSyntax] schrijft die
/// verbatim terug — dezelfde aanpak als de mermaid- en tabel-embeds.
library;

import 'package:flutter_quill/flutter_quill.dart' hide Node;

/// Een blok-embed dat ingesprongen blokinhoud in een lijstitem draagt.
class EmbeddableListBlock extends BlockEmbed {
  EmbeddableListBlock(String data) : super(listBlockType, data);

  /// [Embeddable]-type van de ingesprongen blokinhoud.
  static const listBlockType = 'x-embed-list-block';

  /// Schrijft de ruwe markdown verbatim terug. De inspringing zit al in de data;
  /// de rijke-tekstlaag komt er niet aan.
  static void toMdSyntax(Embed embed, StringSink out) {
    out.write(embed.value.data);
  }
}
