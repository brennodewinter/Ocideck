part of 'privacy_scanner.dart';

final class _TimelineCellSpan {
  final int start;
  final int end;
  final String context;

  const _TimelineCellSpan(this.start, this.end, this.context);
}

/// Indexeert tijdlijncellen één keer zodat iedere privacytreffer O(log n) blijft.
final class _TimelineContextIndex {
  final List<_TimelineCellSpan> _spans;

  const _TimelineContextIndex._(this._spans);

  factory _TimelineContextIndex.parse(String source) {
    final markerEnd = source.indexOf('\n');
    final headerEnd = source.indexOf('\n', markerEnd + 1);
    final delimiterEnd = source.indexOf('\n', headerEnd + 1);
    final headers = splitMarkdownTableRow(
      source.substring(markerEnd + 1, headerEnd),
    );
    final spans = <_TimelineCellSpan>[];
    var rowStart = delimiterEnd + 1;
    while (rowStart < source.length) {
      final newline = source.indexOf('\n', rowStart);
      final rowEnd = newline < 0 ? source.length : newline;
      _indexTimelineRow(source, rowStart, rowEnd, headers, spans);
      if (newline < 0) break;
      rowStart = newline + 1;
    }
    return _TimelineContextIndex._(spans);
  }

  String at(int offset) {
    var low = 0;
    var high = _spans.length - 1;
    while (low <= high) {
      final middle = (low + high) >> 1;
      final span = _spans[middle];
      if (offset < span.start) {
        high = middle - 1;
      } else if (offset >= span.end) {
        low = middle + 1;
      } else {
        return span.context;
      }
    }
    return '';
  }
}

void _indexTimelineRow(
  String source,
  int rowStart,
  int rowEnd,
  List<String> headers,
  List<_TimelineCellSpan> spans,
) {
  var firstContent = rowStart;
  while (firstContent < rowEnd &&
      _isTableSpace(source.codeUnitAt(firstContent))) {
    firstContent++;
  }
  var lastContent = rowEnd - 1;
  while (lastContent >= rowStart &&
      _isTableSpace(source.codeUnitAt(lastContent))) {
    lastContent--;
  }
  final leadingPipe =
      firstContent < rowEnd && source.codeUnitAt(firstContent) == 124;
  final trailingPipe =
      lastContent >= rowStart && source.codeUnitAt(lastContent) == 124;
  var cellStart = leadingPipe ? firstContent + 1 : rowStart;
  var column = 0;
  var slashRun = 0;
  for (var i = cellStart; i < rowEnd; i++) {
    final code = source.codeUnitAt(i);
    if (code == 92) {
      slashRun++;
      continue;
    }
    final delimiter = code == 124 && slashRun.isEven;
    slashRun = 0;
    if (!delimiter) continue;
    if (column < headers.length) {
      spans.add(_TimelineCellSpan(cellStart, i, headers[column]));
    }
    column++;
    cellStart = i + 1;
  }
  if (!trailingPipe && column < headers.length) {
    spans.add(_TimelineCellSpan(cellStart, rowEnd, headers[column]));
  }
}

bool _isTableSpace(int code) => code == 9 || code == 13 || code == 32;
