/// De paginaverdeling van de documentpresentatie (#2487).
///
/// Eén stabiele, gedocumenteerde regel — dezelfde die de export al
/// honoreert (FILE_FORMAT.md §14.6): een `---` op blokniveau is een
/// pagina-einde, en een hoofdstukkop (`H1`) begint een nieuwe pagina
/// precies wanneer "nieuw hoofdstuk op een nieuwe pagina" aan staat.
/// Een `---` direct na een alinearegel is een setext-onderstreping
/// (CommonMark), geen breuk; een `---` of kop binnen een fenced blok
/// is letterlijke tekst.
library;

import '../widgets/reader/document_markdown_view.dart';
import 'markdown_blocks.dart';

/// Eén presentatiepagina als regelbereik `[start, end)` in de bron.
/// Regelgebonden, dus een edit die geen regels wist (een cel in een
/// tabel) laat de verdeling staan.
typedef DocumentPageRange = ({int start, int end});

/// Deelt [source] in presentatiepagina's. Altijd minstens één pagina;
/// lege begin- of eindpagina's komen er nooit uit. [chapterBreaks] is de
/// documentinstelling "nieuw hoofdstuk op een nieuwe pagina" (§14.6):
/// de presentatie knipt op precies dezelfde einden als de export.
List<DocumentPageRange> documentPresentationPages(
  String source, {
  bool chapterBreaks = false,
}) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final cuts = <int>{};
  var inFence = false;
  String fenceMarker = '';
  for (var i = 0; i < lines.length; i++) {
    final trimmed = lines[i].trim();
    final fence = markdownFenceOpen(trimmed);
    if (fence != null) {
      if (!inFence) {
        inFence = true;
        fenceMarker = fence.marker;
      } else if (trimmed.startsWith(fenceMarker * 3)) {
        inFence = false;
      }
      continue;
    }
    if (inFence || trimmed.isEmpty) continue;
    if (_startsPage(lines, i, chapterBreaks: chapterBreaks)) cuts.add(i);
  }
  // Knip vóór elke markeerlijn; de eerste pagina start altijd bij 0.
  final bounds = <int>[0, ...cuts.where((c) => c > 0).toList()..sort()];
  final pages = <DocumentPageRange>[];
  for (var i = 0; i < bounds.length; i++) {
    var start = bounds[i];
    final end = i + 1 < bounds.length ? bounds[i + 1] : lines.length;
    // Witregels en scheidingsstrepen aan de kop van een vervolgpagina horen
    // bij het gat, niet bij het vel: de pagina-einde ís al de scheiding.
    // Zo kan een `---` nooit een eigen, vrijwel leeg vel vormen.
    while (start < end &&
        (lines[start].trim().isEmpty ||
            DocumentMarkdownView.isThematicBreakLine(lines[start]))) {
      start++;
    }
    if (start < end) pages.add((start: start, end: end));
  }
  return pages.isEmpty ? [(start: 0, end: lines.length)] : pages;
}

/// Of regel [i] een nieuwe pagina opent: een thematische breuk die geen
/// setext-onderstreping is, of — met [chapterBreaks] aan — een hoofdstukkop
/// die niet de allereerste inhoud van het document opent.
bool _startsPage(List<String> lines, int i, {required bool chapterBreaks}) {
  final trimmed = lines[i].trim();
  if (chapterBreaks && (trimmed.startsWith('# ') || trimmed == '#')) {
    return _hasContent(lines, i);
  }
  if (!DocumentMarkdownView.isThematicBreakLine(lines[i])) return false;
  // Setext-H2: `---` direct onder een gewone tekstregel is een
  // onderstreping, geen breuk. Een regel die zelf een blok begint
  // (tabel, lijst, citaat, kop, breuk) kan geen setext-tekst zijn.
  final prev = i > 0 ? lines[i - 1].trim() : '';
  return prev.isEmpty || !_isPlainTextLine(prev);
}

/// Een regel die als setext-tekst kan doorlopen: geen blokopening.
bool _isPlainTextLine(String trimmed) =>
    !trimmed.startsWith('#') &&
    !trimmed.startsWith('>') &&
    !trimmed.startsWith('|') &&
    !trimmed.startsWith('```') &&
    !trimmed.startsWith('~~~') &&
    !DocumentMarkdownView.isThematicBreakLine(trimmed) &&
    !RegExp(r'^\s*([-*+]|\d+[.)])\s').hasMatch(trimmed);

bool _hasContent(List<String> lines, int before) {
  for (var i = 0; i < before; i++) {
    if (lines[i].trim().isNotEmpty) return true;
  }
  return false;
}
