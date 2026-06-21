/// Cleans markdown pasted from websites and normalizes Quill export quirks.
library;

/// Invisible characters often copied from news sites (nu.nl, etc.).
const _invisibleChars = {
  '\u00AD', // soft hyphen
  '\u2009', // thin space
  '\u2028', // line separator
  '\u2029', // paragraph separator
  '\uFEFF', // BOM
};

/// ASCII punctuation that CommonMark allows to escape with a leading `\`.
const markdownEscapedPunctuation = '!"#\$%&\'()*+,-./:;<=>?@[\\]^_`{|}~';

/// Unescapes `\`-prefixed punctuation (repeat until stable for `\\.` etc.).
String unescapeMarkdownEscapes(String text) {
  if (text.isEmpty || !text.contains(r'\')) return text;
  var out = text;
  var prev = '';
  while (out != prev) {
    prev = out;
    final buf = StringBuffer();
    for (var i = 0; i < out.length; i++) {
      final c = out[i];
      if (c == r'\' &&
          i + 1 < out.length &&
          markdownEscapedPunctuation.contains(out[i + 1])) {
        buf.write(out[i + 1]);
        i++;
      } else {
        buf.write(c);
      }
    }
    out = buf.toString();
  }
  return out;
}

/// Normalizes stored / exported rich-text markdown for display and storage.
String normalizeRichTextMarkdown(String text) {
  if (text.isEmpty) return text;

  var out = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  out = out.replaceAll('\u00A0', ' ');
  for (final ch in _invisibleChars) {
    out = out.replaceAll(ch, '');
  }

  return unescapeMarkdownEscapes(out);
}

/// Prepare plain-text clipboard content before it enters the markdown editor.
String sanitizeMarkdownPaste(String text) {
  if (text.isEmpty) return text;
  var out = normalizeRichTextMarkdown(text);
  out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return out.trim();
}
