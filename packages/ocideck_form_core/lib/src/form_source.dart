/// A template split into lines with their offsets, plus the two pieces of
/// Markdown context the marker scan needs: where the front matter ends and
/// whether a line sits inside fenced code (FORM_INTAKE.md §4.3).
///
/// Everything here is read-only. The parser never rewrites the source; it only
/// reports *where* things are, so the fill view can later change **only** the
/// bytes inside an answer zone and leave every other byte of the file alone
/// (§4.1).
library;

/// One line of the source.
///
/// [text] has no line ending (`\n`, and a `\r` before it, are not part of it),
/// and the BOM, if any, is not part of the first line's text. [start] is the
/// offset of the line's first character in the *original* string (a BOM counts),
/// [end] the offset just past its last character — the line ending, a CR
/// included, is not part of the line — and [nextStart] where the next line begins
/// (the source length for the last one). So `text.substring(start, end)` is the
/// line's own text and `text.substring(start, nextStart)` is the line with its
/// ending.
class FormLine {
  const FormLine(this.number, this.start, this.end, this.nextStart, this.text);

  /// 1-based.
  final int number;
  final int start;
  final int end;
  final int nextStart;
  final String text;
}

/// The lines of a template and where its body starts.
class FormSource {
  FormSource._(this.text, this.lines, this.bodyStartIndex);

  /// Splits [text]. A leading BOM is tolerated; a front-matter block is
  /// recognised exactly as the document mode of the app recognises it.
  factory FormSource(String text) {
    final lines = <FormLine>[];
    var number = 1;
    var start = 0;
    while (start <= text.length) {
      final nl = text.indexOf('\n', start);
      final end = nl < 0 ? text.length : nl;
      var contentStart = start;
      if (number == 1 && text.startsWith('\uFEFF')) contentStart = 1;
      var contentEnd = end;
      if (contentEnd > contentStart && text.codeUnitAt(contentEnd - 1) == 13) {
        contentEnd--;
      }
      final nextStart = nl < 0 ? text.length : nl + 1;
      lines.add(
        FormLine(
          number,
          start,
          contentEnd,
          nextStart,
          text.substring(contentStart, contentEnd),
        ),
      );
      if (nl < 0) break;
      start = nl + 1;
      number++;
    }
    return FormSource._(text, lines, _frontMatterEnd(lines));
  }

  final String text;
  final List<FormLine> lines;

  /// Index into [lines] of the first line after the front matter (0 when there
  /// is none). Marker lines inside the front matter are not markers.
  final int bodyStartIndex;
}

/// The index of the first line after a leading YAML front-matter block, or 0.
///
/// Mirrors `splitDocumentFrontMatter` in the app (`lib/utils/document_front_matter.dart`):
/// the first line is exactly `---`, a later line is exactly `---`, and the
/// lines between open with a YAML mapping key — otherwise it is two horizontal
/// rules (a page break), not front matter, and the whole file is body. Blank
/// lines after the closing fence belong to the block. A parity test in the app
/// runs both over the same vectors, because a form must survive a document style
/// being chosen (which writes front matter above it).
int _frontMatterEnd(List<FormLine> lines) {
  if (lines.isEmpty || lines.first.text != '---') return 0;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].text != '---') continue;
    if (!_opensWithYamlKey(lines.sublist(1, i))) return 0;
    var end = i + 1;
    while (end < lines.length && lines[end].text.trim().isEmpty) {
      end++;
    }
    return end;
  }
  return 0;
}

final RegExp _yamlKeyLine = RegExp(r'^\s*[A-Za-z_][\w.\-]*\s*:(\s|$)');

bool _opensWithYamlKey(List<FormLine> inner) {
  for (final line in inner) {
    if (line.text.trim().isEmpty) continue;
    return _yamlKeyLine.hasMatch(line.text);
  }
  return false;
}

/// An open CommonMark fence: the fence character, its run length, and nothing
/// else — a form never looks at the info string.
class FormFence {
  const FormFence(this.char, this.length);

  final String char;
  final int length;

  /// Whether [trimmed] closes this fence: the same character, at least as long,
  /// and nothing after it.
  bool closes(String trimmed) =>
      RegExp('^${RegExp.escape(char)}{$length,}[ \\t]*\$').hasMatch(trimmed);
}

/// The fence [trimmed] opens, or null.
///
/// The same predicate as `markdownFenceOpen` in the app
/// (`lib/utils/markdown_blocks.dart`). The core package carries its own copy
/// because it cannot import the app, and a parity test in the app runs both over
/// shared vectors — the repository otherwise holds three slightly different
/// fence models, and a form block must agree with the reader that renders it.
FormFence? formFenceOpen(String trimmed) {
  final match = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
  if (match == null) return null;
  final run = match.group(1)!;
  return FormFence(run[0], run.length);
}

/// Follows fenced code line by line, so the marker scan can tell content from
/// structure: a marker-shaped line inside a fence in template-owned text is
/// *content* (§4.3).
class FormFenceTracker {
  FormFence? _open;

  /// Whether a fence is open right now (between its opening and closing line).
  bool get inFence => _open != null;

  /// Feeds the next line and returns whether it is **code** — a fence line
  /// itself or a line inside one — rather than ordinary text.
  bool isCode(String lineText) {
    final trimmed = lineText.trim();
    final open = _open;
    if (open == null) {
      final fence = formFenceOpen(trimmed);
      if (fence == null) return false;
      _open = fence;
      return true;
    }
    if (open.closes(trimmed)) _open = null;
    return true;
  }
}
