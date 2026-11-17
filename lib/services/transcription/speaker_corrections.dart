import 'dart:convert';

import 'transcript_document.dart';

/// A source-preserving view of transcript paragraphs. Refuse ambiguous metadata
/// rather than applying a correction to the wrong paragraph after a manual edit.
class SpeakerCorrections {
  SpeakerCorrections(this.lines, this.metadata, this.names);
  final List<String> lines;
  final List<Map<String, dynamic>> metadata;
  final Map<String, String> names;
  static final marker = RegExp(r'\n*<!-- ocideck:segments:v1 (\[.*\]) -->\s*$');
  static final label = RegExp(r'\*\*([^\n]*?):\*\* ');

  static Match? _labelMatch(String line) {
    final prefix = RegExp(
      r'^(?:\[[^\n]*?\](?:\([^\n]*?\))? )*',
    ).firstMatch(line)!.end;
    final match = label.matchAsPrefix(line, prefix);
    return match;
  }

  static SpeakerCorrections? read(String source) {
    final body = transcriptBodyText(source)?.trim();
    if (body == null || body.isEmpty) return null;
    try {
      final match = marker.firstMatch(body);
      final raw = match == null ? <dynamic>[] : jsonDecode(match[1]!) as List;
      final lines = (match == null ? body : body.substring(0, match.start))
          .trimRight()
          .split('\n');
      // Generated transcripts have one paragraph per segment. Other Markdown
      // remains editable normally, but cannot safely be indexed as segments.
      if (lines.any((l) => l.trim().isEmpty || l.startsWith('<!--'))) {
        return null;
      }
      final metadata = List.generate(
        lines.length,
        (i) => <String, dynamic>{'segment': i},
      );
      final seen = <int>{};
      for (final entry in raw) {
        final row = Map<String, dynamic>.from(entry as Map);
        final index = row['segment'] as int;
        if (index < 0 || index >= lines.length || !seen.add(index)) return null;
        if (row['corrected_line'] != null &&
            row['corrected_line'] != lines[index]) {
          return null;
        }
        metadata[index] = row;
      }
      if (raw.isNotEmpty && raw.length != lines.length) return null;
      final names = <String, String>{};
      for (var i = 0; i < lines.length; i++) {
        final row = metadata[i];
        final ids = List<String>.from(
          (row['speaker_ids'] as List?) ?? <String>[],
        );
        final visible = _labelMatch(lines[i])?[1];
        if (ids.isEmpty && visible != null) ids.add('legacy:$visible');
        row['speaker_ids'] = ids;
        final stored = Map<String, String>.from(
          (row['speaker_names'] as Map?) ?? {},
        );
        for (final id in ids) {
          names.putIfAbsent(
            id,
            () =>
                stored[id] ??
                (ids.length == 1 && visible != null
                    ? visible.replaceAll(' (?)', '')
                    : 'Spreker ${names.length + 1}'),
          );
        }
      }
      return SpeakerCorrections(lines, metadata, names);
    } catch (_) {
      return null;
    }
  }

  List<String> idsAt(int index) =>
      List<String>.from(metadata[index]['speaker_ids'] as List);

  void assign(Set<int> selected, String id) {
    if (!names.containsKey(id)) throw ArgumentError('Unknown speaker');
    for (final i in selected) {
      metadata[i]['speaker_ids'] = [id];
      metadata[i]['speaker_uncertain'] = false;
      _render(i);
    }
  }

  String addSpeaker(String name) {
    if (name.trim().isEmpty || RegExp(r'[\r\n*<>]').hasMatch(name)) {
      throw ArgumentError('Invalid speaker name');
    }
    var n = 1;
    while (names.containsKey('manual:$n')) {
      n++;
    }
    final id = 'manual:$n';
    names[id] = name.trim();
    return id;
  }

  int mergeCount(String from) =>
      metadata.where((m) => (m['speaker_ids'] as List).contains(from)).length;

  void merge(String from, String into) {
    if (from == into || !names.containsKey(from) || !names.containsKey(into)) {
      throw ArgumentError('Invalid merge');
    }
    for (var i = 0; i < lines.length; i++) {
      if (!idsAt(i).contains(from)) continue;
      metadata[i]['speaker_ids'] = idsAt(
        i,
      ).map((id) => id == from ? into : id).toSet().toList();
      _render(i);
    }
    names.remove(from);
  }

  /// Offset is in the spoken text, not in the timestamp or label. The second
  /// paragraph has no timestamp: a text caret is not an audio alignment.
  void split(int index, int offset) {
    final text = spokenText(index);
    if (offset <= 0 ||
        offset >= text.length ||
        text.substring(0, offset).trim().isEmpty ||
        text.substring(offset).trim().isEmpty) {
      throw ArgumentError('Invalid split');
    }
    final second = Map<String, dynamic>.from(metadata[index]);
    second.remove('start_us');
    second.remove('end_us');
    metadata[index].remove('end_us');
    final prefix = lines[index].substring(0, lines[index].length - text.length);
    lines[index] = '$prefix${text.substring(0, offset).trimRight()}';
    lines.insert(index + 1, text.substring(offset).trimLeft());
    metadata.insert(index + 1, second);
    _render(index + 1);
  }

  String spokenText(int index) {
    final match = _labelMatch(lines[index]);
    return match == null ? lines[index] : lines[index].substring(match.end);
  }

  void _render(int i) {
    final name = idsAt(i).map((id) => names[id]!).join(' + ');
    final match = _labelMatch(lines[i]);
    if (match != null) {
      lines[i] = lines[i].replaceRange(match.start, match.end, '**$name:** ');
    } else {
      final prefix = RegExp(
        r'^(?:\[[^\n]*?\](?:\([^\n]*?\))? )*',
      ).firstMatch(lines[i])!.end;
      lines[i] = lines[i].replaceRange(prefix, prefix, '**$name:** ');
    }
  }

  String apply(String source) {
    final rows = <Map<String, dynamic>>[];
    for (var i = 0; i < lines.length; i++) {
      rows.add({
        ...metadata[i],
        'segment': i,
        'speaker_names': {for (final id in idsAt(i)) id: names[id]},
        'speaker_corrected': true,
        'corrected_line': lines[i],
      });
    }
    final json = jsonEncode(rows)
        .replaceAll('<', r'\u003c')
        .replaceAll('>', r'\u003e')
        .replaceAll('--', r'\u002d\u002d');
    return applyTranscriptBody(
      source,
      '${lines.join('\n')}\n\n<!-- ocideck:segments:v1 $json -->',
    );
  }
}
