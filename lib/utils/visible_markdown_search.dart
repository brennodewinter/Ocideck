import 'inline_markdown.dart';
import 'markdown_blocks.dart';
import 'markdown_paste_cleanup.dart' show markdownEscapedPunctuation;
import 'text_search.dart';

/// Een leesprojectie met bronposities: opmaak valt weg, zichtbare tekst blijft.
/// Vervangen gebruikt bewust de afzonderlijke, strengere beschermgrenzen.
class VisibleMarkdownText {
  VisibleMarkdownText(String source) {
    final output = StringBuffer();
    var base = 0;
    MarkdownFence? fence;
    var hiddenFence = false;
    var comment = false;
    var metadata = RegExp(
      r'^---\r?\n[\s\S]*?\r?\n---(?:\r?\n|$)',
    ).hasMatch(source);
    var lineNumber = 0;
    for (final line in source.split('\n')) {
      final isMetadata = metadata;
      if (lineNumber++ > 0 && line.trim() == '---') metadata = false;
      final opening = markdownFenceOpen(line.trim());
      if (isMetadata) {
        // Frontmatter is bestandsinstelling, geen zichtbare tekst.
      } else if (fence != null) {
        if (fence.closes(line.trim())) {
          fence = null;
        } else if (!hiddenFence) {
          _append(output, line, base);
        }
      } else if (opening != null) {
        fence = opening;
        hiddenFence = const {'mermaid', 'chart'}.contains(opening.language);
      } else {
        final allowed = List<bool>.filled(line.length, true);
        for (var i = 0; i < line.length;) {
          if (comment) {
            final close = line.indexOf('-->', i);
            final end = close < 0 ? line.length : close + 3;
            allowed.fillRange(i, end, false);
            i = end;
            comment = close < 0;
          } else if (line.startsWith('<!--', i)) {
            comment = true;
          } else {
            i++;
          }
        }
        if (_definition.hasMatch(line) || _delimiter.hasMatch(line)) {
          allowed.fillRange(0, line.length, false);
        }
        for (final match in _link.allMatches(line)) {
          final labelStart = line.indexOf('[', match.start) + 1;
          final labelEnd = line.indexOf(']', labelStart);
          allowed.fillRange(match.start, labelStart, false);
          allowed.fillRange(labelEnd, match.end, false);
          if (line[match.start] == '!') {
            allowed.fillRange(labelStart, labelEnd, false);
          }
        }
        for (final match in _footnote.allMatches(line)) {
          allowed.fillRange(match.start, match.end, false);
        }
        if (line.trim().startsWith('|')) {
          for (var i = 0; i < line.length; i++) {
            if (line[i] == '|' && (i == 0 || line[i - 1] != r'\')) {
              allowed[i] = false;
            }
          }
        }
        final marker = _blockMarker.matchAsPrefix(line);
        if (marker != null) allowed.fillRange(0, marker.end, false);
        final filtered = StringBuffer();
        final positions = <int>[];
        for (var i = 0; i < line.length; i++) {
          if (allowed[i]) {
            filtered.write(line[i]);
            positions.add(base + i);
          }
        }
        final raw = filtered.toString();
        final visible = parseInlineRuns(raw).map((run) => run.text).join();
        final inlineVisible = _inlineSyntaxMask(raw);
        final entities = _entity.allMatches(raw).toList(growable: false);
        var entityCursor = 0;
        var cursor = 0;
        for (var i = 0; i < visible.length; i++) {
          var index = raw.indexOf(visible[i], cursor);
          while (index >= 0 && !inlineVisible[index]) {
            index = raw.indexOf(visible[i], index + 1);
          }
          while (entityCursor < entities.length &&
              entities[entityCursor].end <= cursor) {
            entityCursor++;
          }
          final candidate = entityCursor < entities.length
              ? entities[entityCursor]
              : null;
          final entity =
              candidate != null &&
                  inlineVisible[candidate.start] &&
                  decodeNamedHtmlEntities(candidate.group(0)!) == visible[i] &&
                  !visible.startsWith(candidate.group(0)!, i)
              ? candidate
              : null;
          if (entity != null && (index < 0 || entity.start <= index)) {
            output.write(visible[i]);
            offsets.add(positions[entity.start]);
            _ends.add(positions[entity.end - 1] + 1);
            cursor = entity.end;
            continue;
          }
          if (index < 0) {
            final lineBreak = _lineBreak.firstMatch(raw.substring(cursor));
            if (visible[i] == '\n' && lineBreak != null) {
              output.write('\n');
              offsets.add(positions[cursor + lineBreak.start]);
              _ends.add(positions[cursor + lineBreak.end - 1] + 1);
              cursor += lineBreak.end;
            }
            continue;
          }
          output.write(visible[i]);
          offsets.add(positions[index]);
          _ends.add(positions[index] + 1);
          cursor = index + 1;
        }
      }
      output.write('\n');
      offsets.add(base + line.length);
      _ends.add(base + line.length + 1);
      base += line.length + 1;
    }
    final result = output.toString();
    text = result.isEmpty ? '' : result.substring(0, result.length - 1);
    if (offsets.isNotEmpty) {
      offsets.removeLast();
      _ends.removeLast();
    }
  }

  late final String text;
  final offsets = <int>[];
  final _ends = <int>[];

  void _append(StringBuffer output, String line, int base) {
    output.write(line);
    offsets.addAll(List.generate(line.length, (i) => base + i));
    _ends.addAll(List.generate(line.length, (i) => base + i + 1));
  }

  /// Positie in de leesprojectie van een bronteken, ook binnen opmaak.
  int visibleOffsetOf(int sourceOffset) {
    var low = 0;
    var high = offsets.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (offsets[mid] < sourceOffset) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return low;
  }

  List<TextMatchRange> matches(String query, {bool caseSensitive = false}) => [
    for (final match in findAllMatches(
      text,
      query,
      caseSensitive: caseSensitive,
    ))
      TextMatchRange(offsets[match.start], _ends[match.end - 1]),
  ];

  String context(TextMatchRange match, {int radius = 45}) {
    final start = visibleOffsetOf(match.start);
    final end = visibleOffsetOf(match.end);
    final from = (start - radius).clamp(0, text.length);
    final to = (end + radius).clamp(from, text.length);
    return '${from > 0 ? '…' : ''}${text.substring(from, to).replaceAll(RegExp(r'\s+'), ' ')}${to < text.length ? '…' : ''}';
  }

  // Dezelfde begrenzing als de inline-renderer: codespans zijn letterlijk.
  // Alleen bronposities worden hier bijgehouden; de tekst komt uit diens runs.
  List<bool> _inlineSyntaxMask(String raw) {
    final mask = List<bool>.filled(raw.length, true);
    int closing(String marker, int from, int to) {
      for (var i = from; i <= to - marker.length; i++) {
        if (raw[i] == r'\') {
          i++;
          continue;
        }
        if (raw.startsWith(marker, i)) return i;
      }
      return -1;
    }

    void visit(int from, int to) {
      var i = from;
      while (i < to) {
        if (raw[i] == r'\' &&
            i + 1 < to &&
            markdownEscapedPunctuation.contains(raw[i + 1])) {
          mask[i] = false;
          i += 2;
          continue;
        }
        if (raw[i] == '`') {
          final end = raw.indexOf('`', i + 1);
          if (end >= 0 && end < to) {
            mask[i] = false;
            mask[end] = false;
            i = end + 1;
            continue;
          }
        }
        var matched = false;
        for (final marker in const ['**', '__', '~~', '*', '_']) {
          if (!raw.startsWith(marker, i)) continue;
          final end = closing(marker, i + marker.length, to);
          if (end < 0 || (marker.length == 1 && end == i + 1)) continue;
          mask.fillRange(i, i + marker.length, false);
          mask.fillRange(end, end + marker.length, false);
          visit(i + marker.length, end);
          i = end + marker.length;
          matched = true;
          break;
        }
        if (!matched) i++;
      }
    }

    visit(0, raw.length);
    return mask;
  }

  static final _entity = RegExp(r'&(?:lt|gt|quot|amp);');
  static final _lineBreak = RegExp(r'<br(?:\s[^>]*)?/?>', caseSensitive: false);
  static final _link = RegExp(r'!?\[[^\]\n]*\](?:\([^\n]*?\)|\[[^\]\n]*\])');
  static final _footnote = RegExp(r'\[\^[^\]\n]*\]');
  static final _definition = RegExp(r'^\s*\[(?!\^)[^\]\n]+\]\s*:');
  static final _delimiter = RegExp(
    r'^\s*\|?\s*:?-+:?\s*(?:\|\s*:?-+:?\s*)+\|?\s*$',
  );
  static final _blockMarker = RegExp(
    r'^\s*(?:#{1,6}\s+|>\s?|[-*+]\s+|\d+[.)]\s+)',
  );
}

/// Zoek letterlijk in de leesprojectie en vertaal terug naar Markdown-posities.
List<TextMatchRange> findVisibleMarkdownMatches(
  String source,
  String query, {
  bool caseSensitive = false,
}) {
  if (query.isEmpty) return const [];
  return VisibleMarkdownText(
    source,
  ).matches(query, caseSensitive: caseSensitive);
}

String visibleMarkdownText(String source) => VisibleMarkdownText(source).text;

/// Korte leesbare context, zonder verborgen doelen of machinespecificaties.
String searchMatchContext(
  String source,
  TextMatchRange match, {
  int radius = 45,
}) {
  return VisibleMarkdownText(source).context(match, radius: radius);
}
