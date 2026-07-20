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

/// Normalizes stored / exported rich-text markdown for display.
///
/// Ontsnappingen gaan er hier bewust uit: `\-` hoort op het scherm als `-` te
/// verschijnen. Voor tekst die daarna weer wordt opgeslagen is dat juist fout \u2014
/// zie [normalizeRichTextMarkdownForStorage].
String normalizeRichTextMarkdown(String text) =>
    unescapeMarkdownEscapes(normalizeRichTextMarkdownForStorage(text));

/// Dezelfde normalisatie, maar z\u00F3nder de ontsnappingen weg te halen.
///
/// De parser bewaart wat hier uitkomt in [Slide.customMarkdown], en de
/// serialiser schrijft dat er ongewijzigd weer uit. Werd er bij het inlezen
/// ontsnapt, dan was `\-` na \u00E9\u00E9n keer opslaan een \u00E9chte opsommingsstreep en
/// `\*niet cursief\*` alsnog cursief: de tekst veranderde van betekenis zonder
/// dat iemand hem had aangeraakt, en er was geen weg terug omdat de
/// oorspronkelijke backslash nergens meer stond.
///
/// Regeleindes en onzichtbare tekens worden w\u00E9l gelijkgetrokken \u2014 die dragen
/// geen betekenis en zorgen anders voor ruis in elke diff.
String normalizeRichTextMarkdownForStorage(String text) {
  if (text.isEmpty) return text;

  var out = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  out = out.replaceAll('\u00A0', ' ');
  for (final ch in _invisibleChars) {
    out = out.replaceAll(ch, '');
  }
  return out;
}

/// Prepare plain-text clipboard content before it enters the markdown editor.
String sanitizeMarkdownPaste(String text) {
  if (text.isEmpty) return text;
  var out = normalizeRichTextMarkdown(text);
  out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return out.trim();
}
