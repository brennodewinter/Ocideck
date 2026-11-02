import 'dart:convert';

import '../models/slide.dart';
import '../models/markdown_source_document.dart';
import '../services/markdown_service.dart';
import 'deck_text_search.dart';
import 'markdown_blocks.dart';
import 'text_search.dart';

/// De broneditor zoekt dezelfde zichtbare JSON-waarden als de dia-editor.
/// Sleutels, paden en escape-syntax worden nooit als dia-inhoud aangeboden.
class DeckSourceSearchIndex {
  DeckSourceSearchIndex(this.source, {this.includeNotes = false}) {
    final masked = source.split('');
    MarkdownFence? fence;
    var openingStart = 0;
    var bodyStart = 0;
    var offset = 0;
    for (final line in source.split('\n')) {
      final end = offset + line.length;
      if (fence != null && fence.closes(line.trim())) {
        if (const {'chart', 'cockpit', 'question'}.contains(fence.language)) {
          _indexJson(
            source.substring(bodyStart, offset),
            bodyStart,
            fence.language,
          );
          _mask(masked, openingStart, end);
        }
        fence = null;
      } else if (fence == null) {
        fence = markdownFenceOpen(line.trim());
        openingStart = offset;
        bodyStart = end + 1;
      }
      offset = end + 1;
    }
    if (fence != null &&
        const {'chart', 'cockpit', 'question'}.contains(fence.language)) {
      _mask(masked, openingStart, source.length);
    }
    _prose = VisibleMarkdownText(masked.join());
    if (includeNotes) {
      final parser = MarkdownService();
      for (final block in MarkdownSourceDocument.parse(source).blocks) {
        for (final range in parser.speakerNoteSourceRanges(
          block.textIn(source),
        )) {
          final start = block.start + range.start;
          final end = block.start + range.end;
          _notes.add((
            start: start,
            end: end,
            projection: VisibleMarkdownText(
              source
                  .substring(start, end)
                  .replaceAllMapped(
                    RegExp(r'<!--[\s\S]*?--\\>'),
                    (match) => ' ' * match.group(0)!.length,
                  ),
            ),
          ));
        }
      }
    }
  }

  final String source;
  final bool includeNotes;
  final _notes = <({int start, int end, VisibleMarkdownText projection})>[];
  late final VisibleMarkdownText _prose;
  final List<_VisibleJsonString> _strings = [];

  void _indexJson(String json, int base, String language) {
    try {
      final data = jsonDecode(json);
      if (data is! Map) return;
      final indexed = <String, _VisibleJsonString>{};
      final type = switch (language) {
        'chart' => SlideType.chart,
        'cockpit' => SlideType.cockpit,
        _ => SlideType.question,
      };
      final fields = {
        for (final field in slideTextFields(
          Slide(id: '', type: type, customMarkdown: json),
        ))
          field.id,
      };
      final tokens = RegExp(
        r'"(?:[^"\\]|\\.)*"|[{}\[\]:,]|[^\s{}\[\]:,]+',
      ).allMatches(json).toList();
      var cursor = 0;
      void value(List<String> path) {
        if (path.length > 64) throw const FormatException('JSON nesting');
        final token = tokens[cursor++];
        if (token.group(0) == '{') {
          while (tokens[cursor].group(0) != '}') {
            final key = jsonDecode(tokens[cursor++].group(0)!) as String;
            cursor++;
            value([...path, key]);
            if (tokens[cursor].group(0) == ',') cursor++;
          }
          cursor++;
        } else if (token.group(0) == '[') {
          var index = 0;
          while (tokens[cursor].group(0) != ']') {
            value([...path, '${index++}']);
            if (tokens[cursor].group(0) == ',') cursor++;
          }
          cursor++;
        } else if (token.group(0)!.startsWith('"')) {
          final id = _fieldId(language, path);
          if (id != null &&
              fields.contains(id) &&
              _atPath(data, path) == jsonDecode(token.group(0)!)) {
            indexed[path.join('.')] = _VisibleJsonString(
              token.group(0)!,
              base + token.start,
              literal: language != 'question',
            );
          }
        }
      }

      value(const []);
      _strings.addAll(indexed.values);
    } on FormatException {
      // Ongeldige specificaties renderen geen inhoud en leveren geen treffers.
    }
  }

  List<TextMatchRange> matches(String query, {bool caseSensitive = false}) => [
    ..._prose.matches(query, caseSensitive: caseSensitive),
    for (final value in _strings)
      ...value.matches(query, caseSensitive: caseSensitive),
    for (final note in _notes)
      for (final range in note.projection.matches(
        query,
        caseSensitive: caseSensitive,
      ))
        TextMatchRange(note.start + range.start, note.start + range.end),
  ]..sort((a, b) => a.start.compareTo(b.start));

  String context(TextMatchRange range) {
    for (final value in _strings) {
      if (range.start >= value.base && range.end <= value.end) {
        return value.context(range);
      }
    }
    for (final note in _notes) {
      if (range.start >= note.start && range.end <= note.end) {
        return note.projection.context(
          TextMatchRange(range.start - note.start, range.end - note.start),
        );
      }
    }
    return _prose.context(range);
  }
}

Object? _atPath(Object? data, List<String> path) {
  for (final key in path) {
    if (data is Map) {
      data = data[key];
    } else if (data is List) {
      final index = int.tryParse(key);
      if (index == null || index >= data.length) return null;
      data = data[index];
    } else {
      return null;
    }
  }
  return data;
}

void _mask(List<String> text, int start, int end) {
  for (var i = start; i < end; i++) {
    if (text[i] != '\n' && text[i] != '\r') text[i] = ' ';
  }
}

String? _fieldId(String language, List<String> path) {
  final key = path.join('.');
  if (language == 'chart') {
    if (key == 'title' || RegExp(r'^x\.\d+$').hasMatch(key)) {
      return 'chart.$key';
    }
    if (RegExp(r'^series\.\d+\.name$').hasMatch(key)) {
      return 'chart.${path.take(2).join('.')}';
    }
  } else if (language == 'cockpit') {
    if (RegExp(r'^meters\.\d+\.(label|unit|markerLabel)$').hasMatch(key)) {
      return 'cockpit.${path.skip(1).join('.')}';
    }
  } else {
    if (key == 'prompt' ||
        RegExp(
          r'^(distractors\.\d+|pairs\.\d+\.(left|right)|feedback\.(correct|wrong|partial|timeout))$',
        ).hasMatch(key)) {
      return 'question.$key';
    }
    if (RegExp(r'^hints\.\d+$').hasMatch(key)) return 'question.hints';
    if (RegExp(
      r'^(answers\.\d+\.text|regions\.\d+\.label|fields\.\d+\.placeholder)$',
    ).hasMatch(key)) {
      return 'question.${path.take(2).join('.')}';
    }
    if (RegExp(r'^fields\.\d+\.unit$').hasMatch(key)) return 'question.$key';
  }
  return null;
}

class _VisibleJsonString {
  _VisibleJsonString(String raw, this.base, {required bool literal})
    : end = base + raw.length,
      text = jsonDecode(raw) as String {
    for (var i = 1; i < raw.length - 1;) {
      starts.add(base + i);
      i += raw[i] == '\\' ? (raw[i + 1] == 'u' ? 6 : 2) : 1;
      ends.add(base + i);
    }
    projection = literal ? null : VisibleMarkdownText(text);
  }

  final int base;
  final int end;
  final String text;
  final starts = <int>[];
  final ends = <int>[];
  late final VisibleMarkdownText? projection;

  List<TextMatchRange> matches(String query, {bool caseSensitive = false}) => [
    for (final range
        in projection?.matches(query, caseSensitive: caseSensitive) ??
            findAllMatches(text, query, caseSensitive: caseSensitive))
      TextMatchRange(starts[range.start], ends[range.end - 1]),
  ];

  String context(TextMatchRange range) =>
      projection?.context(
        TextMatchRange(
          starts.indexOf(range.start),
          ends.indexOf(range.end) + 1,
        ),
      ) ??
      text;
}
