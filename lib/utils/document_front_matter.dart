/// Reads and writes an OciDeck document's **style** — a `theme:` key in the
/// leading YAML front matter of a plain `.md` — always *byte-surgically*.
///
/// A document is its source verbatim (see [MarkdownDocument]); the style must
/// therefore live in the source itself, as ordinary YAML front matter that
/// Pandoc/Obsidian/GitHub recognise and hide. The red line is byte-faithfulness:
/// a document without a style carries **no** front matter, so opening and saving
/// it unchanged yields identical bytes. Only choosing a style writes a block;
/// choosing "none" removes it again, restoring the plain body.
///
/// Everything here is a pure string transform so it is exhaustively testable
/// apart from the editor. The functions never re-serialise the whole document —
/// they touch only the bytes of the `theme:` line and, when it is the last key,
/// the fences around it. Other front-matter keys a user wrote by hand are
/// preserved verbatim.
library;

const _fence = '---';

/// A document split into its leading front-matter [block] (verbatim, including
/// the blank line(s) that separate it from the body — `''` when there is none)
/// and the [body] that follows. Always `block + body == source`.
typedef DocumentSplit = ({String block, String body});

/// Splits [source] at the end of a well-formed leading YAML front-matter block.
///
/// A block is recognised only when the source opens with a line that is exactly
/// `---` (a trailing `\r` is tolerated for CRLF files) and a later line closes
/// it with another `---`. A `---` with no closing fence is a horizontal rule,
/// not front matter, so the whole source is the body. Trailing blank lines after
/// the closing fence are folded into the block, so the body starts at real
/// content.
DocumentSplit splitDocumentFrontMatter(String source) {
  final firstBreak = source.indexOf('\n');
  if (firstBreak < 0) return (block: '', body: source);
  if (_stripCr(source.substring(0, firstBreak)) != _fence) {
    return (block: '', body: source);
  }
  var i = firstBreak + 1;
  while (i <= source.length) {
    final lineEnd = _lineEnd(source, i);
    final line = _stripCr(source.substring(i, lineEnd));
    final afterLine = lineEnd < source.length ? lineEnd + 1 : lineEnd;
    if (line == _fence) {
      var blockEnd = afterLine;
      // Fold any blank (whitespace-only) lines after the closing fence into the
      // block, so the body begins at the first content line.
      while (blockEnd < source.length) {
        final e = _lineEnd(source, blockEnd);
        if (source.substring(blockEnd, e).trim().isNotEmpty) break;
        blockEnd = e < source.length ? e + 1 : e;
      }
      return (
        block: source.substring(0, blockEnd),
        body: source.substring(blockEnd),
      );
    }
    if (lineEnd >= source.length) break; // last line, no closing fence
    i = afterLine;
  }
  return (block: '', body: source);
}

/// The document body — [source] with any leading front-matter block removed.
String documentBody(String source) => splitDocumentFrontMatter(source).body;

/// The style (`theme:` value) declared in the leading front matter, or `null`
/// when the document has no front matter or no `theme:` key. Quotes are removed.
String? documentStyleName(String source) {
  final block = splitDocumentFrontMatter(source).block;
  if (block.isEmpty) return null;
  for (final raw in block.split('\n')) {
    final m = _themeLine.firstMatch(_stripCr(raw));
    if (m == null) continue;
    final value = _unquote(m.group(1)!.trim());
    return value.isEmpty ? null : value;
  }
  return null;
}

/// Returns [source] with its document style set to [name], or removed when
/// [name] is `null` or empty.
///
/// Byte-surgical: adding a style to a plain document prepends a minimal block;
/// removing the last key drops the whole block, restoring the exact plain body;
/// other front-matter keys and the body are never touched. A no-op change
/// returns the same bytes.
String withDocumentStyleName(String source, String? name) {
  final split = splitDocumentFrontMatter(source);
  final eol = _detectEol(source);
  final trimmed = name?.trim() ?? '';

  if (trimmed.isEmpty) {
    if (split.block.isEmpty) return source;
    final without = _removeThemeFromBlock(split.block, eol);
    // `null` means the block held only the theme key → drop it entirely.
    return without == null ? split.body : without + split.body;
  }

  final value = _yamlScalar(trimmed);
  if (split.block.isEmpty) {
    return '$_fence$eol' 'theme: $value$eol' '$_fence$eol$eol${split.body}';
  }
  return _setThemeInBlock(split.block, value, eol) + split.body;
}

// --- block editors -----------------------------------------------------------

/// Replaces the `theme:` line in [block] with `theme: <value>`, or inserts one
/// before the closing fence when absent. Preserves every other line verbatim.
String _setThemeInBlock(String block, String value, String eol) {
  final lines = block.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (_themeLine.hasMatch(_stripCr(lines[i]))) {
      lines[i] = 'theme: $value${_trailingCr(lines[i])}';
      return lines.join('\n');
    }
  }
  // No theme key yet: insert before the closing fence (the last `---` line).
  for (var i = lines.length - 1; i >= 0; i--) {
    if (_stripCr(lines[i]) == _fence) {
      lines.insert(i, 'theme: $value${i == 0 ? '' : _trailingCr(lines[i])}');
      return lines.join('\n');
    }
  }
  return block; // defensive: splitDocumentFrontMatter guarantees a closing fence
}

/// Removes the `theme:` line from [block]. Returns `null` when nothing but the
/// fences (and blank lines) remains, signalling the whole block should be
/// dropped; otherwise the block without its theme line.
String? _removeThemeFromBlock(String block, String eol) {
  final lines = block.split('\n');
  lines.removeWhere((l) => _themeLine.hasMatch(_stripCr(l)));
  final hasOtherKeys = lines.any((l) {
    final s = _stripCr(l).trim();
    return s.isNotEmpty && s != _fence;
  });
  return hasOtherKeys ? lines.join('\n') : null;
}

// --- small helpers -----------------------------------------------------------

final _themeLine = RegExp(r'^\s*theme\s*:\s*(.*)$');

int _lineEnd(String s, int from) {
  final nl = s.indexOf('\n', from);
  return nl < 0 ? s.length : nl;
}

String _stripCr(String line) =>
    line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

String _trailingCr(String line) => line.endsWith('\r') ? '\r' : '';

String _detectEol(String source) => source.contains('\r\n') ? '\r\n' : '\n';

/// A YAML scalar for [s]: bare when safe, else double-quoted with escapes. Keeps
/// plain names (`LibreKAT`) unquoted while making an odd custom name (a colon, a
/// leading dash, surrounding spaces) safe to round-trip.
String _yamlScalar(String s) {
  final needsQuote =
      s.isEmpty ||
      s != s.trim() ||
      RegExp('''[:#\\n"'\\[\\]{},&*!|>%@`]''').hasMatch(s) ||
      RegExp(r'^[-?]').hasMatch(s);
  if (!needsQuote) return s;
  return '"${s.replaceAll('\\', r'\\').replaceAll('"', r'\"')}"';
}

String _unquote(String v) {
  if (v.length >= 2 && v.startsWith('"') && v.endsWith('"')) {
    return v
        .substring(1, v.length - 1)
        .replaceAll(r'\"', '"')
        .replaceAll(r'\\', '\\');
  }
  if (v.length >= 2 && v.startsWith("'") && v.endsWith("'")) {
    return v.substring(1, v.length - 1).replaceAll("''", "'");
  }
  return v;
}
