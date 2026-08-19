library;

import '../utils/document_front_matter.dart' show kMaxDocumentFieldValueLength;

final _documentChromePlaceholder = RegExp(r'\{([a-z][a-z0-9_-]*)\}');
const _markdownPunctuation = r'''!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~''';
const int kMaxResolvedDocumentChromeChars = kMaxDocumentFieldValueLength * 4;

/// Vult bekende `{veld}`-plaatsen in en laat onbekende plaatsen leesbaar staan.
///
/// Veldwaarden worden als letterlijke Markdown ingevoegd. Daardoor kan een
/// waarde geen opmaak, koppeling, HTML of extra Markdown-regel introduceren.
/// Een uitvoerder die zelf voor escaping zorgt kan dat met
/// [escapeMarkdownValues] uitschakelen.
String resolveDocumentChromeTemplate(
  String template,
  Map<String, String> fields, {
  bool escapeMarkdownValues = true,
}) {
  final out = _BoundedChromeWriter(kMaxResolvedDocumentChromeChars);
  var cursor = 0;
  for (final match in _documentChromePlaceholder.allMatches(template)) {
    if (!out.writeSlice(template, cursor, match.start)) return out.finish();
    final value = fields[match.group(1)];
    if (value == null) {
      if (!out.writeSlice(template, match.start, match.end)) {
        return out.finish();
      }
    } else if (escapeMarkdownValues) {
      if (!out.writeEscaped(value)) return out.finish();
    } else if (!out.writeSlice(
      value,
      0,
      value.length.clamp(0, kMaxDocumentFieldValueLength),
    )) {
      return out.finish();
    }
    cursor = match.end;
  }
  out.writeSlice(template, cursor, template.length);
  return out.finish();
}

class _BoundedChromeWriter {
  _BoundedChromeWriter(this.limit);

  final int limit;
  final StringBuffer _buffer = StringBuffer();
  var _length = 0;
  var _truncated = false;

  bool writeSlice(String source, int start, int end) {
    final available = limit - _length;
    final wanted = end - start;
    final take = wanted <= available ? wanted : available;
    if (take > 0) {
      _buffer.write(source.substring(start, start + take));
      _length += take;
    }
    if (take < wanted) _truncated = true;
    return !_truncated;
  }

  bool writeEscaped(String value) {
    final end = value.length.clamp(0, kMaxDocumentFieldValueLength);
    for (var i = 0; i < end; i++) {
      final char = value[i];
      if (char == '\r') {
        if (i + 1 < end && value[i + 1] == '\n') i++;
        if (!writeSlice(r'\\n', 0, 3)) return false;
      } else if (char == '\n') {
        if (!writeSlice(r'\\n', 0, 3)) return false;
      } else {
        if (_markdownPunctuation.contains(char) &&
            !writeSlice('\\$char', 0, 2)) {
          return false;
        }
        if (!_markdownPunctuation.contains(char) &&
            !writeSlice(char, 0, char.length)) {
          return false;
        }
      }
    }
    return true;
  }

  String finish() {
    final value = _buffer.toString();
    if (!_truncated || value.isEmpty) return value;
    return '${value.substring(0, value.length - 1)}…';
  }
}
