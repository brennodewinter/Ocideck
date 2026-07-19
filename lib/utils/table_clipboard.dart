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
    final cells = body.split('|').map((c) => c.trim()).toList();
    // Alignment/separator row (|---|:--:|) carries no data.
    if (cells.every((c) => RegExp(r'^:?-{2,}:?$').hasMatch(c))) continue;
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
