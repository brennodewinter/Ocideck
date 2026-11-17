// Inhoudsopgave-service voor de documentmodus (feature 4).
//
// De TOC-plek wordt gemarkeerd met een HTML-commentaar `<!-- toc -->` op een
// eigen regel in de `.md`. Een vreemde Markdown-lezer negeert HTML-commentaar;
// OciDeck herkent het en regenereert de inhoudsopgave op die plek bij export.
// De gegenereerde inhoud zelf wordt niet in de `.md` opgeslagen — alleen de
// marker. Dat voorkomt dat een verouderde TOC in het bestand blijft staan.
//
// De regeneratie gebeurt in het exportpad, ná de OciWacht-projectie, op de
// geprojecteerde body — zodat de TOC alleen koppen bevat die de ontvanger mag
// zien.

import '../utils/heading_anchors.dart';

/// De marker die de plek van de inhoudsopgave aangeeft in de `.md`.
/// Een HTML-commentaar op een eigen regel — draagbaar, elke Markdown-lezer
/// negeert het.
const tocMarker = '<!-- toc -->';

/// Een regel die niets anders bevat dan de marker (inspringing en extra spaties
/// toegestaan). Eén bron voor alle plekken die de marker als bijzonder geval
/// moeten herkennen: de visuele-modus-poorten en de Quill-embed.
final tocMarkerLinePattern = RegExp(r'^[ \t]*<!--\s*toc\s*-->[ \t]*$');

/// Genereer een GFM-Markdown inhoudsopgave uit de koppen in [body].
///
/// Parseert koppen `#` t/m `######` en produceert een GFM-lijst met
/// ankerverwijzingen (`[Koptitel](#slug)`), inspringing per niveau.
/// [maxDepth] beperkt de kopniveaus die meekomen (standaard 3: H1–H3).
///
/// Puur headless: geen I/O, geen widget-afhankelijkheden. Testbaar.
String generateTocMarkdown(String body, {int maxDepth = 3}) {
  final headings = markdownHeadings(body);
  final anchors = HeadingAnchorIndex(headings.map((h) => h.text));
  final buf = StringBuffer();
  for (var i = 0; i < headings.length; i++) {
    final h = headings[i];
    if (h.level > maxDepth) continue;
    final label = h.text
        .replaceAll('\\', '\\\\')
        .replaceAll('[', r'\[')
        .replaceAll(']', r'\]');
    buf.write('${'  ' * (h.level - 1)}- [$label](#${anchors.entries[i].id})\n');
  }
  return buf.toString().trimRight();
}

/// Vervang de `<!-- toc -->`-marker (en eventuele bestaande TOC eronder) in
/// [body] door de marker + [generatedToc].
///
/// Behoudt de marker in de uitvoer (zodat een volgende export hem weer vindt)
/// en plaatst de gegenereerde TOC er direct onder. Een bestaande TOC onder de
/// marker (van een vorige export) wordt vervangen — de TOC wordt altijd
/// opnieuw gegenereerd. Als de marker niet voorkomt, retourneert [body]
/// ongewijzigd.
///
/// Met [keepMarker] op `false` verdwijnt de marker en blijft alleen de TOC
/// staan — op de plek van de marker, niet bovenaan. Dat is wat de `.md`-export
/// wil: een ontvanger buiten OciDeck heeft niets aan de marker, en een
/// HTML-commentaar dat blijft rondslingeren is rommel.
String replaceTocMarker(
  String body,
  String generatedToc, {
  bool keepMarker = true,
}) {
  // Match de marker + eventuele bestaande TOC-lijnen eronder (geneste
  // GFM-lijst-items die met `- ` of `  - ` beginnen).
  final pattern = RegExp(
    r'^<!-- toc -->\s*\n?(?:[ \t]*- \[.*?\]\(#.*?\)[^\n]*\n?)*',
    multiLine: true,
  );
  if (!RegExp(r'^<!-- toc -->', multiLine: true).hasMatch(body)) return body;
  final toc = generatedToc.trim();
  final String replacement;
  if (keepMarker) {
    replacement = toc.isEmpty ? tocMarker : '$tocMarker\n\n$toc';
  } else {
    replacement = toc;
  }
  return body.replaceFirst(pattern, replacement);
}

/// Verwijder de `<!-- toc -->`-marker en eventuele gegenereerde TOC eronder
/// uit [body]. Gebruikt door de `.md`-export die de TOC als platte lijst
/// schrijft (zonder marker) — of door de editor die de marker verbergt.
String stripTocMarker(String body) {
  // Zelfde regelvorm als in [replaceTocMarker] — inclusief de inspringing.
  // Zonder `[ \t]*` bleven precies de geneste regels staan (`  - [H2](#h2)`),
  // en dat is de normale vorm: een TOC met H2's onder een H1 springt in. Wat
  // overbleef waren losse lijstitems midden in het document.
  final pattern = RegExp(
    r'^<!-- toc -->\s*\n?(?:[ \t]*- \[.*?\]\(#.*?\)[^\n]*\n?)*',
    multiLine: true,
  );
  return body.replaceAll(pattern, '').trimLeft();
}

/// Of [body] de `<!-- toc -->`-marker bevat.
bool hasTocMarker(String body) =>
    RegExp(r'^<!-- toc -->\s*$', multiLine: true).hasMatch(body);
