/// De scanner over de `<!-- ocideck:* -->`-tabelcontracten uit
/// docs/design/RISK_FORMAT.md: welke marker loopt voor welke tabel, welke
/// contractkolommen (`cols=`) ze draagt, en hoe je tabelinhoud of marker-
/// attributen chirurgisch terugschrijft zonder een andere byte aan te
/// raken.
///
/// De bindingsregel volgt §5.1: een run van markerregels bindt aan de eerste
/// tabel die erop volgt, met hoogstens witregels ertussen. Een marker zonder
/// tabel blijft onaangeroerd commentaar — [scanOciMarkedTables] levert hem
/// niet op, dus geen enkele schrijver raakt hem.
///
/// Zuivere services-laag: alleen string-werk, geen Flutter-imports.
library;

import '../utils/markdown_blocks.dart';
import 'markdown_table_codec.dart';
import 'ocideck_markers.dart';

/// Eén markerblok + de GFM-tabel die erop volgt, met regelnummers naar de
/// bron zodat terugschrijven een bereikvervanging is en geen her-parse.
class OciMarkedTable {
  /// Regelindex (vanaf 0) van de eerste markerregel van het blok.
  final int blockStart;

  /// Regelindex direct na de laatste markerregel — het begin van de
  /// witregel-opening vóór de tabel.
  final int markerEnd;

  /// Regelindex van de tabelkoprij.
  final int tableStart;

  /// Regelindex direct na de laatste tabelregel (exclusief).
  final int tableEnd;

  /// De ruwe markerregels, in bronvolgorde.
  final List<String> markerLines;

  /// De ontlede markers, zelfde volgorde als [markerLines].
  final List<OciTableMarker> markers;

  /// De tabelregels: kop, scheidingsrij en body.
  final List<String> tableLines;

  const OciMarkedTable({
    required this.blockStart,
    required this.markerEnd,
    required this.tableStart,
    required this.tableEnd,
    required this.markerLines,
    required this.markers,
    required this.tableLines,
  });

  /// De draagende marker: de eerste die geen `calc` is (een `calc` is een
  /// bijschrift óp de drager, nooit zelf de eigenaar). `null` bij een blok
  /// van alleen `calc`-regels — dat is per §5.1 net zo goed bewaard commentaar.
  OciTableMarker? get marker {
    for (final m in markers) {
      if (m.kind != OciMarkerKinds.calc) return m;
    }
    return null;
  }

  /// De gestapelde `calc`-markers boven deze tabel (§3.7).
  List<OciTableMarker> get calcMarkers => [
    for (final m in markers)
      if (m.kind == OciMarkerKinds.calc) m,
  ];

  String? get kind => marker?.kind;
  String? get id => marker?.attr('id');
  int? get rev => marker?.intAttr('rev');
  int? get next => marker?.intAttr('next');

  /// De positionele kolomcontract-sleutels uit `cols=` (§3.2). Leeg bij een
  /// marker zonder `cols`-attribuut.
  List<String> get cols {
    final raw = marker?.attr('cols');
    if (raw == null || raw.isEmpty) return const [];
    return raw.split(',').map((k) => k.trim()).toList();
  }

  /// De gedecodeerde tabel: eerste rij de koppen, daarna de body-rijen.
  List<List<String>> get decodedRows => decodeMarkdownTableRows(tableLines);

  List<String> get headerCells {
    final rows = decodedRows;
    return rows.isEmpty ? const [] : rows.first;
  }

  /// Alleen de body-rijen (zonder kop). Een ragged rij krijgt geen padding —
  /// de contractlaag meldt die via de kwaliteitscontrole, niet door stil
  /// aan te vullen.
  List<List<String>> get bodyRows => decodedRows.skip(1).toList();

  /// De kolomindex van contract-sleutel [key], of `-1` als `cols=` hem niet
  /// noemt. Cellen voorbij [cols].length zijn vrije auteurskolommen en
  /// bereik je dus niet via een sleutel — bewust: die hebben geen contract.
  int colIndexOf(String key) => cols.indexOf(key);

  /// De cel in body-rij [row] voor contract-sleutel [key] — `''` als de
  /// sleutel of de cel ontbreekt, zodat aanroepers "leeg" en "afwezig"
  /// niet hoeven te onderscheiden vóór de kwaliteitscontrole dat doet.
  String cell(int row, String key) {
    final c = colIndexOf(key);
    if (c < 0) return '';
    final rows = bodyRows;
    if (row < 0 || row >= rows.length || c >= rows[row].length) return '';
    return rows[row][c];
  }

  /// Elke body-rij als `sleutel → cel` over de gedeelde prefix van
  /// [cols] en de rijbreedte. Vrije kolommen voorbij `cols=` en ontbrekende
  /// cellen blijven zichtbaar via [bodyRows] zelf.
  List<Map<String, String>> get contractRows => [
    for (final row in bodyRows)
      {for (var c = 0; c < cols.length && c < row.length; c++) cols[c]: row[c]},
  ];
}

/// De tabel die een markerblok volgt. `null` als de marker-run niet aan een
/// tabel bindt — de scanner meldt hem dan niet (§5.1).
class OciMarkedTableScan {
  final List<OciMarkedTable> tables;

  /// De markerregels die níét aan een tabel bonden — een verweesde marker
  /// is informatie voor de kwaliteitscontrole (#2490), geen ruis om weg te
  /// filteren. Regelindex + ruwe regel.
  final List<(int, String)> orphanMarkerLines;

  const OciMarkedTableScan(this.tables, this.orphanMarkerLines);
}

/// Vindt alle `<!-- ocideck:* -->`-gemarkeerde tabellen in [source].
///
/// Fenced codeblokken tellen niet mee — een marker of pijpregel in een
/// ` ``` `-blok is letterlijke tekst. Verder geldt alleen de bindingsregel:
/// markerregels, dan witregels, dan kop + scheidingsrij.
OciMarkedTableScan scanOciMarkedTables(String source) {
  final lines = source.split('\n');
  final tables = <OciMarkedTable>[];
  final orphans = <(int, String)>[];
  var i = 0;
  while (i < lines.length) {
    final fence = markdownFenceOpen(lines[i].trim());
    if (fence != null) {
      var end = i + 1;
      while (end < lines.length && !fence.closes(lines[end].trim())) {
        end++;
      }
      i = end < lines.length ? end + 1 : end;
      continue;
    }
    if (!isOciTableMarkerLine(lines[i])) {
      i++;
      continue;
    }
    final blockStart = i;
    final markerLines = <String>[];
    while (i < lines.length && isOciTableMarkerLine(lines[i])) {
      markerLines.add(lines[i]);
      i++;
    }
    final markerEnd = i;
    // Witregels mogen tussen markerblok en tabel staan (§2); elke andere
    // regel breekt de binding.
    var j = i;
    while (j < lines.length && lines[j].trim().isEmpty) {
      j++;
    }
    final bound =
        j + 1 < lines.length &&
        isMarkdownTableLine(lines[j]) &&
        isMarkdownTableDelimiterRow(lines[j + 1]);
    if (!bound) {
      for (var k = 0; k < markerLines.length; k++) {
        orphans.add((blockStart + k, markerLines[k]));
      }
      continue;
    }
    var end = j + 2;
    while (end < lines.length && isMarkdownTableLine(lines[end])) {
      end++;
    }
    tables.add(
      OciMarkedTable(
        blockStart: blockStart,
        markerEnd: markerEnd,
        tableStart: j,
        tableEnd: end,
        markerLines: markerLines,
        markers: [
          for (final line in markerLines)
            parseOciTableMarker(line) ??
                OciTableMarker(kind: 'unknown', raw: line.trim()),
        ],
        tableLines: lines.sublist(j, end),
      ),
    );
    i = end;
  }
  return OciMarkedTableScan(tables, orphans);
}

/// Herschrijft het blok van [table] in [source] en laat elke byte erbuiten
/// staan.
///
/// * [markers] `null` → de markerregels gaan byte-getrouw terug ([raw] —
///   geen herformattering van onaangeroerde inhoud); anders worden de markers
///   in de canonieke vorm geschreven.
/// * [bodyRows] `null` → de tabelregels gaan byte-getrouw terug; anders
///   blijven kopregel én scheidingsrij verbatim staan en wordt alleen de
///   body opnieuw gecodeerd — zo houdt een cel-escape (`\|`, `<br>`) dezelfde
///   schrijfwijze als elke andere OciDeck-tabel.
/// * De witregel-opening tussen markerblok en tabel reist altijd mee.
///
/// Resultaat is de volledige nieuwe bron; de aanroeper (provider, codec)
/// beslist hoe die in een stap landt.
String rewriteOciMarkedTable(
  String source,
  OciMarkedTable table, {
  List<OciTableMarker>? markers,
  List<List<String>>? bodyRows,
}) {
  final lines = source.split('\n');
  final replacement = <String>[
    if (markers == null)
      ...table.markerLines
    else
      for (final m in markers) m.toComment(),
    // De witregels tussen markerblok en tabel: nooit zelf verzinnen.
    ...lines.sublist(table.markerEnd, table.tableStart),
    if (bodyRows == null)
      ...table.tableLines
    else ...[
      table.tableLines.first,
      table.tableLines[1],
      for (final row in bodyRows)
        '| ${List.generate(table.headerCells.length, (c) => encodeMarkdownTableCell(c < row.length ? row[c] : '')).join(' | ')} |',
    ],
  ];
  lines.replaceRange(table.blockStart, table.tableEnd, replacement);
  return lines.join('\n');
}

/// Splitst één gecombineerd markerblok (zoals het in de atomaire embed of in
/// [OciMarkedTable] zit) in zijn markerregels en de tabelbron. De visuele
/// editor bewerkt de tabel en schrijft hem met [markOciTable] weer bij de
/// markers terug — dezelfde rol als `unmarkTimeline`/`markTableAsTimeline`.
({List<String> markerLines, String table}) splitOciMarkedBlock(String source) {
  final lines = source.split('\n');
  final markers = <String>[];
  var i = 0;
  while (i < lines.length && isOciTableMarkerLine(lines[i])) {
    markers.add(lines[i]);
    i++;
  }
  // Witregels tussen markerblok en tabel (§2) zijn opmaak, geen inhoud:
  // bij terugschrijven staat de marker direct boven de tabel — de canonieke
  // vorm die ook de atomaire embed spreekt.
  while (i < lines.length && lines[i].trim().isEmpty) {
    i++;
  }
  return (markerLines: markers, table: lines.sublist(i).join('\n'));
}

/// Zet [markerLines] weer direct boven de tabel — de bindingsvorm die zowel
/// de scanner als de atomaire embed als één contract leest.
String markOciTable(List<String> markerLines, String tableSource) =>
    [...markerLines, tableSource].join('\n');

/// Zet op de draagende marker van [table] het attribuut [key] op [value]
/// (`null` verwijdert) en schrijft het blok terug — de andere markerregels
/// (o.a. gestapelde `calc`'s) en de tabel zelf blijven byte-getrouw.
String rewriteOciMarkedTableAttr(
  String source,
  OciMarkedTable table,
  String key,
  String? value,
) {
  final carrier = table.marker;
  if (carrier == null) return source;
  final markers = [
    for (final m in table.markers)
      identical(m, carrier) ? carrier.withAttr(key, value) : m,
  ];
  return rewriteOciMarkedTable(source, table, markers: markers);
}

/// Verhoogt `rev` op de draagende marker met één — de ene regel in het
/// contract die een geslaagde mutatie van de tabel registreert (§5.4).
/// Een tabel zónder `rev` krijgt er geen: writers verzinnen geen markers.
String bumpOciMarkedTableRev(String source, OciMarkedTable table) {
  final rev = table.rev;
  if (rev == null) return source;
  return rewriteOciMarkedTableAttr(source, table, 'rev', '${rev + 1}');
}
