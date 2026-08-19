/// De codering van een Markdown-tabel zoals OciDeck hem schrijft en leest.
///
/// Los van `MarkdownService` omdat de HTML-export de tabellen óók moet kunnen
/// lezen: de zes rapportagetypes (`scorecard`, `assets`, `discoveries`,
/// `checklist`, `scope-matrix`, `findings-summary`) bewaren hun inhoud als een
/// gewone tabel en krijgen in de export een eigen weergave. Zonder deze module
/// zou de export zijn eigen tabelparser naast die van de parser leggen, en dan
/// gaat er precies één ding mis: de ontsnappingen. Een cel met een `|` of een
/// regeleinde erin las er dan anders uit dan hij bewaard was.
///
/// De ontsnappingen zijn: `\|` voor een letterlijke pijp, `\\` voor een
/// backslash, en `<br>` voor een regeleinde binnen een cel — met `\<br>` voor
/// een auteur die de tekens `<br>` letterlijk bedoelt.
library;

import '../models/slide.dart';

/// De regelherkenning en het celsplitsen wonen in een Flutter-vrij bestand,
/// zodat een zuivere parser ze kan gebruiken zonder deze module (en daarmee
/// `models/slide.dart` en het hele Flutter-materiaal) binnen te halen. Hier
/// doorgeëxporteerd, zodat elke bestaande aanroeper één oppervlak ziet.
export 'markdown_table_lines.dart';

import 'markdown_table_lines.dart';

/// Codeert één celwaarde voor een Markdown-tabel.
String encodeMarkdownTableCell(String value) => value
    .replaceAll('\\', r'\\')
    .replaceAll('|', r'\|')
    // Escape an author-typed literal "<br>" before encoding real newlines as
    // "<br>", so the two are distinguishable on parse (otherwise a literal
    // "<br>" silently became a line break every load).
    .replaceAll('<br>', r'\<br>')
    .replaceAll('\n', '<br>');

/// Leest de rijen van een tabel uit [tableLines] (de regels van de tabel, zonder
/// omringende tekst). De GFM-scheidingsrij direct ná de kop valt weg.
///
/// Alleen die ene regel telt als scheiding. Verderop is een streepje gewoon
/// inhoud — in een bevindingen- of scopetabel de gebruikelijke invulling voor
/// "niet van toepassing" — en zo'n rij werd anders in zijn geheel weggegooid,
/// inclusief de andere kolommen.
List<List<String>> decodeMarkdownTableRows(List<String> tableLines) =>
    decodeMarkdownTableWithAlignment(tableLines).rows;

/// Zoals [decodeMarkdownTableRows], maar leest óók de per-kolomuitlijning uit
/// de GFM-scheidingsrij (`:---` = links, `:---:` = centrum, `---:` = rechts).
/// Een scheidingsrij zonder colons levert een lege lijst op — de aanroeper
/// hoort dat te behandelen als "alles links" (de GFM-default).
({List<List<String>> rows, List<TableAlign> alignments})
decodeMarkdownTableWithAlignment(List<String> tableLines) {
  final rows = <List<String>>[];
  final alignments = <TableAlign>[];
  for (final line in tableLines) {
    final cells = splitMarkdownTableRow(line);
    // Dezelfde vraag als [isMarkdownTableDelimiterRow], en sinds die met de
    // regelherkenning is meeverhuisd stellen we hem daar in plaats van met een
    // eigen kopie van het scheidingscel-patroon.
    if (rows.length == 1 && isMarkdownTableDelimiterRow(line)) {
      for (final c in cells) {
        final t = c.trim();
        final left = t.startsWith(':');
        final right = t.endsWith(':');
        alignments.add(
          left && right
              ? TableAlign.center
              : right
              ? TableAlign.right
              : TableAlign.left,
        );
      }
      continue;
    }
    rows.add(cells);
  }
  return (rows: rows, alignments: alignments);
}

/// Bouwt de GFM-scheidingsrij met per-kolomuitlijning: `:---` voor links,
/// `:---:` voor centrum, `---:` voor rechts. Zonder [alignments] (of korter
/// dan [colCount]) is elke kolom de kale `---` (GFM-default = links).
String markdownTableSeparatorRow(int colCount, [List<TableAlign>? alignments]) {
  final cells = <String>[];
  for (var c = 0; c < colCount; c++) {
    // Geen uitlijning opgegeven voor deze kolom = kale --- (de GFM-default).
    // Wel opgegeven = expliciete colon-vorm, ook voor links (:---). Zo blijft
    // een oud deck zonder uitlijning ongewijzigd bij opslaan.
    if (alignments == null || c >= alignments.length) {
      cells.add('---');
      continue;
    }
    cells.add(switch (alignments[c]) {
      TableAlign.left => ':---',
      TableAlign.center => ':---:',
      TableAlign.right => '---:',
    });
  }
  return '| ${cells.join(' | ')} |';
}

/// Serialiseer een celraster (eerste rij = koppen) naar een volledige
/// GFM-pijptabel: koprij, scheidingsrij (met optionele [alignments]) en de body.
/// De cellen gaan door [encodeMarkdownTableCell], dus een `|`, een backslash of
/// een regelovergang (`\n` → `<br>`) blijft behouden. Ragged rijen worden met
/// lege cellen aangevuld tot de breedste. De omgekeerde van
/// [decodeMarkdownTableRows].
String encodeMarkdownTable(
  List<List<String>> rows, {
  List<TableAlign>? alignments,
}) {
  if (rows.isEmpty) return '';
  final cols = rows.fold<int>(1, (m, r) => r.length > m ? r.length : m);
  // Alleen colons in de scheidingsrij zetten als er écht een niet-linkse kolom
  // is; een tabel zonder uitlijning houdt de kale `---` (`:---` is semantisch
  // gelijk aan links maar oogt als ruis in een gewone tabel).
  final hasAlignment =
      alignments != null && alignments.any((a) => a != TableAlign.left);
  String rowLine(List<String> r) =>
      '| ${List.generate(cols, (c) => encodeMarkdownTableCell(c < r.length ? r[c] : '')).join(' | ')} |';
  return [
    rowLine(rows.first),
    markdownTableSeparatorRow(cols, hasAlignment ? alignments : null),
    for (final r in rows.skip(1)) rowLine(r),
  ].join('\n');
}
