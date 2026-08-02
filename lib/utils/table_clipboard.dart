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
