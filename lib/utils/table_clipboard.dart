/// Recognises tabular clipboard content so a paste into one table cell can
/// fill a whole grid.
///
/// Spreadsheets (Excel, Numbers, LibreOffice Calc, Google Sheets) put
/// tab-separated text on the clipboard on macOS, Linux and Windows alike, so
/// TSV is the primary format. CSV with a comma or semicolon (the Dutch/European
/// list separator) and markdown tables are recognised as well.
///
/// The field scanning itself is [parseCsvRows] — the same code that reads a
/// chart's data file. What stays here is the part that is genuinely about a
/// *clipboard*: deciding whether the payload is a table at all, and which
/// separator it uses. A file says what it is by its extension; a paste has to
/// be recognised.
library;

import 'csv.dart';

/// Parses [text] as a table, or returns null when it does not look tabular —
/// in that case the paste should go into the single cell as usual.
///
/// Detection is deliberately conservative for ambiguous formats: a tab is
/// always a column break (no one types tabs into a cell), but commas and
/// semicolons only count when every line yields the same column count, so a
/// pasted sentence with a comma stays plain text.
List<List<String>>? parseClipboardTable(String text) {
  final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  if (normalized.trim().isEmpty) return null;

  final markdown = _parseMarkdownTable(normalized);
  if (markdown != null) return markdown;

  if (_looksLikeList(normalized)) return null;

  if (normalized.contains('\t')) {
    return _trim(parseCsvRows(normalized, delimiter: '\t'));
  }

  // CSV variants: require at least two rows with a consistent column count of
  // two or more (checked before any padding, so prose with stray commas does
  // not qualify); prefer the separator that yields the wider table.
  List<List<String>>? best;
  for (final delimiter in const [';', ',']) {
    if (!normalized.contains(delimiter)) continue;
    final rows = parseCsvRows(normalized, delimiter: delimiter);
    while (rows.isNotEmpty && rows.last.every((c) => c.trim().isEmpty)) {
      rows.removeLast();
    }
    if (rows.length < 2) continue;
    final cols = rows.first.length;
    if (cols < 2 || rows.any((r) => r.length != cols)) continue;
    if (best == null || cols > best.first.length) best = rows;
  }
  return best;
}

final _reListItem = RegExp(
  r'^[ \t\u2009]*([-*+\u2022\u25E6\u25AA\u25AB]|\d+[.)])\s',
);

/// Ziet de inhoud eruit als een opsomming in plaats van een tabel?
///
/// De scheidingsherkenning hieronder is blind voor betekenis: een tab is altijd
/// een kolomscheiding ("no one types tabs into a cell"), en komma's en
/// puntkomma's tellen zodra elke regel evenveel velden geeft. Een ingesprongen
/// opsomming voldoet aan allebei — met tabs als inspringing, of met toevallig
/// één komma per regel — en werd dan een tabel in plaats van een lijst (#1557).
///
/// Begint élke niet-lege regel met een opsommingsteken of een genummerd item,
/// dan is het een lijst. Een echte tabel doet dat niet, en een lijst met één
/// item is te weinig om iets over te beweren.
bool _looksLikeList(String text) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).toList();
  if (lines.length < 2) return false;
  return lines.every(_reListItem.hasMatch);
}

/// Rastermodel dat uit een geplakte tabel komt: labels, reeksnamen en cellen.
///
/// Buiten [ChartEditor] gehouden zodat de plaklogica te toetsen is zonder een
/// State-widget op te starten, en zodat die State onder het klasseplafond blijft.
class ChartClipboardGrid {
  final List<String> xLabels;
  final List<String> seriesNames;
  final List<List<String>> values;

  const ChartClipboardGrid({
    required this.xLabels,
    required this.seriesNames,
    required this.values,
  });
}

/// Zet een al-geparste klembordtabel om naar het chart-rastermodel.
///
/// Eerste rij = reekskoppen wanneer die niet-numeriek oogt; anders één
/// synthetische reeks en elke rij is label + waarden. Lege tabellen geven
/// `null` terug — dan hoort de paste in de cel te blijven.
ChartClipboardGrid? chartGridFromClipboardTable(List<List<String>> table) {
  if (table.isEmpty) return null;
  final first = table.first;
  final headerLooksNumeric = first
      .skip(1)
      .every((c) => double.tryParse(c.replaceAll(',', '.')) != null);
  if (!headerLooksNumeric && table.length > 1) {
    var seriesNames = [
      for (var c = 1; c < first.length; c++)
        first[c].trim().isEmpty ? 'Reeks $c' : first[c].trim(),
    ];
    if (seriesNames.isEmpty) seriesNames = ['Reeks 1'];
    final body = table.skip(1).toList();
    return ChartClipboardGrid(
      seriesNames: seriesNames,
      xLabels: [for (final row in body) row.isEmpty ? '' : row.first],
      values: [
        for (final row in body)
          [
            for (var c = 0; c < seriesNames.length; c++)
              c + 1 < row.length ? row[c + 1] : '',
          ],
      ],
    );
  }
  return ChartClipboardGrid(
    seriesNames: const ['Reeks 1'],
    xLabels: [for (final row in table) row.isEmpty ? '' : row.first],
    values: [
      for (final row in table) [row.length > 1 ? row[1] : ''],
    ],
  );
}

/// Een pijp die niet ontsnapt is — de scheiding tussen twee cellen.
final _reUnescapedPipe = RegExp(r'(?<!\\)\|');

/// Zet een celraster om naar tab-gescheiden tekst (TSV) — de spiegel van
/// [parseClipboardTable]. Spreadsheets (Excel, Numbers, Calc, Sheets) lezen
/// TSV op elk platform, dus dit is de vorm die het best plakt in een
/// rekenblad. Een cel met een regeleinde wordt tussen aanhalingstekens gezet
/// (CSV-regel: anders breekt de regel de rij).
String encodeClipboardTable(List<List<String>> rows) {
  final out = StringBuffer();
  for (var r = 0; r < rows.length; r++) {
    if (r > 0) out.writeln();
    final cells = <String>[];
    for (final cell in rows[r]) {
      cells.add(
        cell.contains('\t') || cell.contains('\n') || cell.contains('"')
            ? '"${cell.replaceAll('"', '""')}"'
            : cell,
      );
    }
    out.write(cells.join('\t'));
  }
  return out.toString();
}

/// Haalt de ontsnapping uit een geplakte markdown-cel.
///
/// Spiegelt `_unescapeCell` in `markdown_service.dart`, dat de schrijfkant doet.
/// Bewust een kopie van drie regels en geen gedeelde helper: die zit in de
/// private kant van de markdown-library, en die opentrekken voor het plakpad
/// levert meer koppeling op dan het bespaart.
String _unescapeClipboardCell(String s) => s
    .replaceAll(r'\|', '|')
    .replaceAll(r'\<br>', '<br>')
    .replaceAll(r'\\', r'\');

/// Markdown table: every non-empty line framed by pipes. The `|---|---|`
/// separator row is dropped.
List<List<String>>? _parseMarkdownTable(String text) {
  final lines = [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (lines.isEmpty || lines.any((l) => !l.startsWith('|'))) return null;

  final rows = <List<String>>[];
  for (final line in lines) {
    var body = line.substring(1);
    if (body.endsWith('|')) body = body.substring(0, body.length - 1);
    // Splitsen op een níét-ontsnapte pijp, en daarna de ontsnapping weghalen.
    // OciDeck schrijft een cel met een pijp erin als `a\|b`; een kale split
    // scheurde die cel in tweeën en gaf de rij een kolom te veel.
    final cells = body
        .split(_reUnescapedPipe)
        .map((c) => _unescapeClipboardCell(c.trim()))
        .toList();
    // Alignment/separator row (|---|:--:|) carries no data. GFM allows a
    // single dash per cell; this must match markdown_table_codec.dart (see
    // _separatorCell there), otherwise one module reads a row as a separator
    // and the other as data.
    if (cells.every((c) => RegExp(r'^:?-+:?$').hasMatch(c))) continue;
    rows.add(cells);
  }
  if (rows.isEmpty || rows.first.length < 2) return null;
  return _trim(rows);
}

/// Drops empty trailing rows (from the trailing newline spreadsheets add) and
/// pads every row to the same column count. Returns null when the result is a
/// single lone cell — that is not a table.
List<List<String>>? _trim(List<List<String>> rows) {
  final kept = List<List<String>>.from(rows);
  while (kept.isNotEmpty && kept.last.every((c) => c.trim().isEmpty)) {
    kept.removeLast();
  }
  if (kept.isEmpty) return null;
  final cols = kept.fold<int>(0, (m, r) => r.length > m ? r.length : m);
  if (cols < 2 && kept.length < 2) return null;
  return [
    for (final row in kept)
      [for (var c = 0; c < cols; c++) c < row.length ? row[c] : ''],
  ];
}
