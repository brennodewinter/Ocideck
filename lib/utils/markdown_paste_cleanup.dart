/// Cleans markdown pasted from websites and normalizes Quill export quirks.
library;

/// Invisible characters often copied from news sites (nu.nl, etc.).
///
/// Alleen tekens die *binnen* een regel ruis zijn. De regelscheiders U+2028 en
/// U+2029 stonden hier ook in en werden dus gewist; daarmee plakte een geplakte
/// lijst tot één regel aan elkaar. Ze worden nu omgezet naar `\n`, want dat is
/// wat ze betekenen (#1560).
const _invisibleChars = {
  '\u00AD', // soft hyphen
  '\u2009', // thin space
  '\uFEFF', // BOM
};

/// Regelscheiders die als een echt regeleinde gelezen horen te worden.
const _lineSeparators = {
  '\u2028', // line separator
  '\u2029', // paragraph separator
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
  for (final ch in _lineSeparators) {
    out = out.replaceAll(ch, '\n');
  }
  out = out.replaceAll('\u00A0', ' ');
  out = _stripInvisiblesOutsideIndent(out);
  return out;
}

/// Wist de onzichtbare tekens, maar niet in de inspringing van een regel.
///
/// Een dunne spatie midden in een zin is ruis van een nieuwssite; dezelfde
/// dunne spatie aan het begin van een regel is de structuur van een geneste
/// lijst. Die werd meegewist, waarna elke opsomming plat binnenkwam — de klacht
/// uit #1556. In de inspringing wordt hij daarom een gewone spatie, net als een
/// NBSP hierboven; verderop in de regel blijft hij verdwijnen.
String _stripInvisiblesOutsideIndent(String text) {
  final lines = text.split('\n');
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    var indent = 0;
    while (indent < line.length && _isIndentChar(line[indent])) {
      indent++;
    }
    final head = line.substring(0, indent).replaceAll('\u2009', ' ');
    var tail = line.substring(indent);
    for (final ch in _invisibleChars) {
      tail = tail.replaceAll(ch, '');
    }
    lines[i] = '$head$tail';
  }
  return lines.join('\n');
}

bool _isIndentChar(String ch) => ch == ' ' || ch == '\t' || ch == '\u2009';

/// Prepare plain-text clipboard content before it enters the markdown editor.
String sanitizeMarkdownPaste(String text) {
  if (text.isEmpty) return text;
  var out = normalizeRichTextMarkdown(text);
  out = out.replaceAll(RegExp(r'\n{3,}'), '\n\n');
  return _trimBlankLines(out);
}

/// Haalt lege regels aan begin en eind weg — maar niet de inspringing.
///
/// Hier stond `trim()`, en die nam ook de leidende witruimte van de eerste
/// regel mee. Kopieerde je een stuk uit het midden van een geneste lijst, dan
/// sprong dat eerste item naar het hoofdniveau terwijl de rest bleef staan
/// (#1561).
String _trimBlankLines(String text) {
  final lines = text.split('\n');
  var first = 0;
  while (first < lines.length && lines[first].trim().isEmpty) {
    first++;
  }
  var last = lines.length;
  while (last > first && lines[last - 1].trim().isEmpty) {
    last--;
  }
  if (first >= last) return '';
  return lines.sublist(first, last).map((l) => l.trimRight()).join('\n');
}
