library;

import '../models/table_sort.dart';
import 'markdown_table_codec.dart';

export '../models/table_sort.dart';

class TableSortService {
  const TableSortService();

  /// Sorteert een volledige tabelbron zonder regeleindes of overige bytes te
  /// normaliseren. Alleen de inhoud van bodyregels verhuist; elke positionele
  /// LF/CRLF/CR en een eventueel ontbrekend laatste regeleinde blijven staan.
  TableSourceSortResult sortSource(
    String source, {
    required int columnIndex,
    TableSortKind kind = TableSortKind.automatic,
    TableSortDirection direction = TableSortDirection.ascending,
    TableSortDecision decision = TableSortDecision.apply,
  }) {
    final raw = _splitSourceLines(source);
    final result = sort(
      raw.map((line) => line.content).toList(),
      columnIndex: columnIndex,
      kind: kind,
      direction: direction,
      decision: decision,
    );
    if (!result.changed || raw.length != result.lines.length) {
      return TableSourceSortResult(
        source: source,
        outcome: result.outcome,
        analysis: result.analysis,
        reason: result.reason,
      );
    }
    final out = StringBuffer();
    for (var index = 0; index < raw.length; index++) {
      out
        ..write(result.lines[index])
        ..write(raw[index].ending);
    }
    return TableSourceSortResult(
      source: out.toString(),
      outcome: result.outcome,
      analysis: result.analysis,
    );
  }

  TableSortAnalysis analyze(
    List<String> tableLines, {
    required int columnIndex,
    TableSortKind kind = TableSortKind.automatic,
  }) {
    final rows = _bodyRows(tableLines, columnIndex);
    final classified = rows.map((row) => _classify(row.value)).toList();
    final dominant = _dominantKind(classified);
    final resolved = switch (kind) {
      TableSortKind.automatic => dominant,
      TableSortKind.text => TableParseKind.text,
      TableSortKind.number => TableParseKind.number,
      TableSortKind.date => TableParseKind.date,
      TableSortKind.time => TableParseKind.time,
    };
    final parsed = <_ParsedRow>[];
    final unparsed = <int>[];
    var emptyCount = 0;
    for (final row in rows) {
      if (row.value.trim().isEmpty) {
        emptyCount++;
        unparsed.add(row.index);
        continue;
      }
      final key = _parse(row.value, resolved);
      if (key == null) {
        unparsed.add(row.index);
      } else {
        parsed.add(_ParsedRow(row.index, key));
      }
    }

    final nonEmpty = rows.length - emptyCount;
    final confidence = nonEmpty == 0 ? 0.0 : parsed.length / nonEmpty;
    final reasons = <String>[
      if (nonEmpty == 0) 'The column has no non-empty values.',
      if (resolved == TableParseKind.mixed)
        'The column has no single dominant parse kind.',
      if (parsed.isNotEmpty)
        '${parsed.length} of $nonEmpty non-empty values parse as ${resolved.name}.',
      if (unparsed.isNotEmpty)
        '${unparsed.length} rows are empty or cannot be parsed and will remain together at the end.',
    ];
    final suitability = nonEmpty == 0 || resolved == TableParseKind.mixed
        ? TableAnalysisSuitability.notYetSuitable
        : unparsed.isEmpty
        ? TableAnalysisSuitability.suitable
        : TableAnalysisSuitability.suitableWithAttentionPoints;

    return TableSortAnalysis(
      profile: TableColumnProfile(
        nonEmptyCount: nonEmpty,
        emptyCount: emptyCount,
        dominantKind: dominant,
        parsedRowIndices: List.unmodifiable(parsed.map((row) => row.index)),
        unparsedRowIndices: List.unmodifiable(unparsed),
        alreadyMonotonic: _isMonotonic(parsed),
        confidence: confidence,
        reasons: List.unmodifiable(reasons),
      ),
      suitability: suitability,
      requestedKind: kind,
      resolvedKind: resolved,
    );
  }

  TableSortResult sort(
    List<String> tableLines, {
    required int columnIndex,
    TableSortKind kind = TableSortKind.automatic,
    TableSortDirection direction = TableSortDirection.ascending,
    TableSortDecision decision = TableSortDecision.apply,
  }) {
    final original = List<String>.of(tableLines);
    if (decision == TableSortDecision.cancel) {
      return TableSortResult(
        lines: original,
        outcome: TableSortOutcome.cancelled,
        analysis: null,
      );
    }

    TableSortAnalysis analysis;
    List<_RawRow> rows;
    try {
      rows = _bodyRows(tableLines, columnIndex);
      analysis = analyze(tableLines, columnIndex: columnIndex, kind: kind);
    } on ArgumentError catch (error) {
      return TableSortResult(
        lines: original,
        outcome: TableSortOutcome.failed,
        analysis: null,
        reason: error.message?.toString(),
      );
    }
    if (!analysis.canSort) {
      return TableSortResult(
        lines: original,
        outcome: TableSortOutcome.failed,
        analysis: analysis,
        reason: analysis.profile.reasons.firstOrNull,
      );
    }

    final parsedRows = rows
        .map(
          (row) => (
            row: row,
            key: row.value.trim().isEmpty
                ? null
                : _parse(row.value, analysis.resolvedKind),
          ),
        )
        .toList();
    parsedRows.sort((a, b) {
      final aKey = a.key;
      final bKey = b.key;
      if (aKey == null || bKey == null) {
        if (aKey == null && bKey == null) return a.row.index - b.row.index;
        return aKey == null ? 1 : -1;
      }
      final order = aKey.compareTo(bKey);
      if (order == 0) return a.row.index - b.row.index;
      return direction == TableSortDirection.ascending ? order : -order;
    });

    return TableSortResult(
      lines: [
        tableLines[0],
        tableLines[1],
        ...parsedRows.map((entry) => entry.row.rawLine),
      ],
      outcome: TableSortOutcome.applied,
      analysis: analysis,
    );
  }
}

List<({String content, String ending})> _splitSourceLines(String source) {
  final lines = <({String content, String ending})>[];
  var start = 0;
  var index = 0;
  while (index < source.length) {
    if (source.codeUnitAt(index) != 10 && source.codeUnitAt(index) != 13) {
      index++;
      continue;
    }
    final content = source.substring(start, index);
    final crlf =
        source.codeUnitAt(index) == 13 &&
        index + 1 < source.length &&
        source.codeUnitAt(index + 1) == 10;
    final end = crlf ? index + 2 : index + 1;
    lines.add((content: content, ending: source.substring(index, end)));
    start = end;
    index = end;
  }
  if (start < source.length || source.isEmpty) {
    lines.add((content: source.substring(start), ending: ''));
  }
  return lines;
}

List<_RawRow> _bodyRows(List<String> lines, int columnIndex) {
  if (lines.length < 2 || !isMarkdownTableDelimiterRow(lines[1])) {
    throw ArgumentError('Expected a GFM header and delimiter row.');
  }
  final columnCount = splitMarkdownTableRow(lines.first).length;
  if (columnIndex < 0 || columnIndex >= columnCount) {
    throw ArgumentError.value(columnIndex, 'columnIndex', 'Outside the table.');
  }
  return [
    for (var index = 0; index < lines.length - 2; index++)
      _RawRow(index, lines[index + 2], _cellAt(lines[index + 2], columnIndex)),
  ];
}

String _cellAt(String line, int columnIndex) {
  final cells = splitMarkdownTableRow(line);
  return columnIndex < cells.length ? cells[columnIndex] : '';
}

TableParseKind _classify(String value) {
  if (value.trim().isEmpty) return TableParseKind.mixed;
  if (_parseTime(value) != null) return TableParseKind.time;
  if (_parseDate(value) != null) return TableParseKind.date;
  if (_parseNumber(value) != null) return TableParseKind.number;
  return TableParseKind.text;
}

TableParseKind _dominantKind(List<TableParseKind> kinds) {
  final counts = <TableParseKind, int>{};
  for (final kind in kinds.where((kind) => kind != TableParseKind.mixed)) {
    counts[kind] = (counts[kind] ?? 0) + 1;
  }
  if (counts.isEmpty) return TableParseKind.mixed;
  final highest = counts.values.reduce((a, b) => a > b ? a : b);
  final winners = counts.entries.where((entry) => entry.value == highest);
  return winners.length == 1 ? winners.single.key : TableParseKind.mixed;
}

Comparable<Object>? _parse(String value, TableParseKind kind) => switch (kind) {
  TableParseKind.text => value.trim().toLowerCase(),
  TableParseKind.number => _parseNumber(value),
  TableParseKind.date => _parseDate(value),
  TableParseKind.time => _parseTime(value),
  TableParseKind.mixed => null,
};

String _withoutQualifier(String value) => value
    .trim()
    .replaceFirst(RegExp(r'^(?:circa|ca\.?)\s+', caseSensitive: false), '')
    .trim();

double? _parseNumber(String value) {
  final match = RegExp(
    r'^([+-]?\d+(?:[.,]\d+)?)(?:\s*(?:-|–|—|\.\.)\s*[+-]?\d+(?:[.,]\d+)?)?$',
  ).firstMatch(_withoutQualifier(value));
  return match == null
      ? null
      : double.tryParse(match.group(1)!.replaceAll(',', '.'));
}

int? _parseDate(String value) {
  final input = _withoutQualifier(value);
  final date = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})(?:\s*(?:–|—|\.\.|\s-\s)\s*\d{4}-\d{2}-\d{2})?$',
  ).firstMatch(input);
  if (date != null) {
    final year = int.parse(date.group(1)!);
    final month = int.parse(date.group(2)!);
    final day = int.parse(date.group(3)!);
    final parsed = DateTime.utc(year, month, day);
    if (parsed.year != year || parsed.month != month || parsed.day != day) {
      return null;
    }
    return parsed.millisecondsSinceEpoch;
  }
  final year = RegExp(
    r'^(\d{4})(?:\s*(?:-|–|—|\.\.)\s*\d{4})?$',
  ).firstMatch(input);
  return year == null
      ? null
      : DateTime.utc(int.parse(year.group(1)!)).millisecondsSinceEpoch;
}

int? _parseTime(String value) {
  final match = RegExp(
    r'^(\d{1,2}):(\d{2})(?::(\d{2}))?(?:\s*(?:-|–|—|\.\.)\s*\d{1,2}:\d{2}(?::\d{2})?)?$',
  ).firstMatch(_withoutQualifier(value));
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final second = int.tryParse(match.group(3) ?? '') ?? 0;
  if (hour > 23 || minute > 59 || second > 59) return null;
  return hour * 3600 + minute * 60 + second;
}

bool _isMonotonic(List<_ParsedRow> rows) {
  for (var index = 1; index < rows.length; index++) {
    if (rows[index - 1].key.compareTo(rows[index].key) > 0) return false;
  }
  return true;
}

class _RawRow {
  const _RawRow(this.index, this.rawLine, this.value);

  final int index;
  final String rawLine;
  final String value;
}

class _ParsedRow {
  const _ParsedRow(this.index, this.key);

  final int index;
  final Comparable<Object> key;
}
