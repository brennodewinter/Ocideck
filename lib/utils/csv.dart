// One implementation of CSV quoting, for the two readers that need it: chart
// data typed or exported by a user, and the CWE catalogue MITRE publishes.
//
// They read the same quoting rules but want a different shape, and the
// difference is deliberate rather than accidental:
//
//   * [parseCsvRows] reads a whole document, so a quoted field may contain a
//     line break (RFC 4180 proper). MITRE's CWE export needs that — its
//     descriptions run over several lines.
//   * [parseCsvLine] reads a single line the caller has already split off. A
//     line break therefore cannot occur inside a field, which is the point:
//     damage from a stray quote stops at the end of that line instead of
//     swallowing the rest of the file into one cell. For hand-made chart data
//     that containment is worth more than multi-line values, which chart rows
//     have no use for anyway.
//
// Both are the same scan; only the caller's framing differs.

/// Split [text] into rows of cells, honouring RFC 4180 quoting: a field wrapped
/// in double quotes may contain the delimiter, a line break, or a doubled `""`
/// standing for one literal quote.
///
/// With [trimUnquoted] the surrounding whitespace of an *unquoted* field is
/// removed. A quoted field is always taken verbatim, so `" a "` keeps its inner
/// spaces — the quotes are what say the spaces are meant.
///
/// Lenient about malformed input, because the source is whatever someone
/// exported: an unterminated quote runs to the end of the text, and characters
/// between a closing quote and the next delimiter are discarded. `\r\n` is
/// normalised to `\n` first. A trailing line break does not produce an extra
/// empty row; empty input produces no rows at all.
List<List<String>> parseCsvRows(
  String text, {
  String delimiter = ',',
  bool trimUnquoted = false,
}) {
  final source = text.replaceAll('\r\n', '\n');
  final rows = <List<String>>[];
  var row = <String>[];
  var started = false;
  var i = 0;

  while (i < source.length) {
    final start = i;
    // Tolerate space before an opening quote, but never eat the delimiter
    // itself — a tab-delimited line would otherwise collapse into one cell.
    while (i < source.length &&
        source[i] != delimiter &&
        (source[i] == ' ' || source[i] == '\t')) {
      i++;
    }

    if (i < source.length && source[i] == '"') {
      i++; // opening quote
      final field = StringBuffer();
      while (i < source.length) {
        if (source[i] != '"') {
          field.write(source[i]);
          i++;
        } else if (i + 1 < source.length && source[i + 1] == '"') {
          field.write('"');
          i += 2;
        } else {
          i++; // closing quote
          break;
        }
      }
      row.add(field.toString());
      while (i < source.length && source[i] != delimiter && source[i] != '\n') {
        i++;
      }
    } else {
      var end = i;
      while (end < source.length &&
          source[end] != delimiter &&
          source[end] != '\n') {
        end++;
      }
      final raw = source.substring(start, end);
      row.add(trimUnquoted ? raw.trim() : raw);
      i = end;
    }
    started = true;

    if (i >= source.length) break;
    if (source[i] == '\n') {
      rows.add(row);
      row = <String>[];
      started = false;
    }
    i++; // the delimiter or the line break
  }

  if (started) rows.add(row);
  return rows;
}

/// Split one already-isolated line into cells.
///
/// Runs [parseCsvRows] over a single line, so the quoting rules are literally
/// the same code. The containment described at the top of this file does not
/// come from here but from the caller having split on line breaks first: a
/// stray quote can only run to the end of what it is handed.
///
/// Unquoted cells are trimmed by default, which is what a chart's data grid
/// has always done. An empty line yields one empty cell, not zero cells, so a
/// caller can count columns without a special case.
List<String> parseCsvLine(
  String line, {
  String delimiter = ',',
  bool trimUnquoted = true,
}) {
  final rows = parseCsvRows(
    line,
    delimiter: delimiter,
    trimUnquoted: trimUnquoted,
  );
  return rows.isEmpty ? <String>[''] : rows.first;
}
