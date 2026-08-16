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

import 'package:markdown/markdown.dart' as md;

/// De marker die de plek van de inhoudsopgave aangeeft in de `.md`.
/// Een HTML-commentaar op een eigen regel — draagbaar, elke Markdown-lezer
/// negeert het.
const tocMarker = '<!-- toc -->';

/// Genereer een GFM-Markdown inhoudsopgave uit de koppen in [body].
///
/// Parseert koppen `#` t/m `######` en produceert een GFM-lijst met
/// ankerverwijzingen (`[Koptitel](#slug)`), inspringing per niveau.
/// [maxDepth] beperkt de kopniveaus die meekomen (standaard 3: H1–H3).
///
/// Puur headless: geen I/O, geen widget-afhankelijkheden. Testbaar.
String generateTocMarkdown(String body, {int maxDepth = 3}) {
  final document = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
  );
  final nodes = document.parse(body);
  final entries = <_TocEntry>[];
  _collectHeadings(nodes, entries, maxDepth);
  if (entries.isEmpty) return '';
  final buf = StringBuffer();
  for (final entry in entries) {
    buf.write('${'  ' * (entry.level - 1)}- [${entry.text}](#${entry.slug})\n');
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

class _TocEntry {
  final int level;
  final String text;
  final String slug;
  _TocEntry(this.level, this.text, this.slug);
}

void _collectHeadings(
  List<md.Node> nodes,
  List<_TocEntry> entries,
  int maxDepth,
) {
  for (final node in nodes) {
    if (node is md.Element && node.tag == 'h1' && maxDepth >= 1) {
      entries.add(_TocEntry(1, _text(node), _slug(_text(node))));
    } else if (node is md.Element && node.tag == 'h2' && maxDepth >= 2) {
      entries.add(_TocEntry(2, _text(node), _slug(_text(node))));
    } else if (node is md.Element && node.tag == 'h3' && maxDepth >= 3) {
      entries.add(_TocEntry(3, _text(node), _slug(_text(node))));
    } else if (node is md.Element && node.tag == 'h4' && maxDepth >= 4) {
      entries.add(_TocEntry(4, _text(node), _slug(_text(node))));
    } else if (node is md.Element && node.tag == 'h5' && maxDepth >= 5) {
      entries.add(_TocEntry(5, _text(node), _slug(_text(node))));
    } else if (node is md.Element && node.tag == 'h6' && maxDepth >= 6) {
      entries.add(_TocEntry(6, _text(node), _slug(_text(node))));
    }
  }
}

/// Haal de platte tekst uit een heading-element.
String _text(md.Element el) {
  final buf = StringBuffer();
  void walk(md.Node n) {
    if (n is md.Text) {
      buf.write(n.text);
    } else if (n is md.Element) {
      for (final child in n.children ?? const <md.Node>[]) {
        walk(child);
      }
    }
  }

  for (final child in el.children ?? const <md.Node>[]) {
    walk(child);
  }
  return buf.toString().trim();
}

/// GFM-anchor-slug: lowercase, spaties → streepjes, leesteken gestript.
/// Komt overeen met wat `marked` + `DOMPurify` in de HTML-export genereren.
String _slug(String text) {
  return text
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s-]'), '')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
}
