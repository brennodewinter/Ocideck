import 'package:flutter/painting.dart';

import 'markdown_paste_cleanup.dart';

/// Lichtgewicht inline-markdown: **vet**, *cursief* / _cursief_, `code`,
/// ~~doorhalen~~ en [tekst](url). Geen block-niveau (dat doet de slide-layout
/// al); puur de opmaak binnen één tekstregel.
///
/// Deze helft is opzettelijk widget-vrij: parsen en het omzetten naar
/// [InlineSpan]s is tekstopmaak, geen widgetboom. Daardoor kunnen de headless
/// meet- en analysediensten hem gebruiken zonder de UI-laag binnen te trekken.
/// De klikbare, af te breken kant leeft in `widgets/slides/inline_markdown.dart`.

/// Eén stuk tekst met de actieve opmaak.
///
/// [math] is de uitzondering: dan is [text] geen opgemaakte tekst maar de kale
/// TeX tussen `$…$`, die de widgetlaag als inline-formule tekent. De opmaakvlaggen
/// gelden er niet voor.
class InlineRun {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strike;
  final bool math;
  final String? link;

  const InlineRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.strike = false,
    this.math = false,
    this.link,
  });

  InlineRun _with({
    bool? bold,
    bool? italic,
    bool? code,
    bool? strike,
    bool? math,
    String? link,
  }) {
    return InlineRun(
      text,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      code: code ?? this.code,
      strike: strike ?? this.strike,
      math: math ?? this.math,
      link: link ?? this.link,
    );
  }
}

const _markers = r'*_~`[]()\$';

bool _isEscapedPunctuation(String c) =>
    c.length == 1 && markdownEscapedPunctuation.contains(c);

/// Parse [text] naar opeenvolgende [InlineRun]s. Onafgesloten of ongeldige
/// opmaaktekens blijven gewoon letterlijke tekst.
List<InlineRun> parseInlineRuns(String text) {
  final out = <InlineRun>[];
  _parseInto(text, const InlineRun(''), out);
  // Voeg aangrenzende identieke runs samen (netter en sneller om te renderen).
  final merged = <InlineRun>[];
  for (final r in out) {
    if (r.text.isEmpty) continue;
    if (merged.isNotEmpty &&
        !merged.last.math &&
        !r.math &&
        merged.last.bold == r.bold &&
        merged.last.italic == r.italic &&
        merged.last.code == r.code &&
        merged.last.strike == r.strike &&
        merged.last.link == r.link) {
      final prev = merged.removeLast();
      merged.add(
        InlineRun(
          prev.text + r.text,
          bold: prev.bold,
          italic: prev.italic,
          code: prev.code,
          strike: prev.strike,
          link: prev.link,
        ),
      );
    } else {
      merged.add(r);
    }
  }
  return merged;
}

/// Of [text] opmaaktekens bevat die [parseInlineRuns] zou verwerken.
bool hasInlineMarkdown(String text) => _hasMarker(text);

/// De kale tekst zonder opmaaktekens (linktekst blijft, de URL valt weg).
String stripInlineMarkdown(String text) {
  if (!_hasMarker(text)) return text;
  final buf = StringBuffer();
  for (final run in parseInlineRuns(text)) {
    buf.write(run.text);
  }
  return buf.toString();
}

bool _hasMarker(String s) {
  for (var i = 0; i < s.length; i++) {
    if (_markers.contains(s[i])) return true;
    if (s[i] == r'\' && i + 1 < s.length && _isEscapedPunctuation(s[i + 1])) {
      return true;
    }
  }
  return false;
}

/// Spiegelt de HTML-escape uit `sanitizeImportedText` voor weergave: `&amp;`,
/// `&lt;`, `&gt;`, `&quot;` worden weer `&`, `<`, `>`, `"`. Numerieke entities
/// (`&#60;`) blijven staan — de sanitizer escaped `&` juist als eerste zodat een
/// bron-`&#60;` `&amp;#60;` wordt en na deze decode niet als `<` terugkomt.
/// `&amp;` gaat als laatste, anders wordt een letterlijke `&lt;` na twee stappen
/// alsnog `<` (zelfde volgorde als `_unescapeHtml` in markdown_service_helpers).
String _decodeNamedHtmlEntities(String text) {
  if (!text.contains('&')) return text;
  return text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&amp;', '&');
}

void _parseInto(String s, InlineRun ctx, List<InlineRun> out) {
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      // Geïmporteerde tekst landt HTML-escaped in het `.md` (#876); de
      // Flutter-preview rendert via deze runs, dus de named entities gaan hier
      // terug. Alleen named, nooit numeriek — anders wordt een bron-`&#60;`
      // alsnog `<` en dat is juist de evasie die de sanitizer blokkeert.
      // Code-spans voegen hun tekst direct toe (hieronder) en slaan deze stap
      // over, zodat `` `&amp;` `` letterlijk blijft.
      out.add(ctx._with()._copyText(_decodeNamedHtmlEntities(buf.toString())));
      buf.clear();
    }
  }

  var i = 0;
  while (i < s.length) {
    final c = s[i];

    // CommonMark: \X → X for punctuation (Quill export / pasted web markdown).
    if (c == r'\' && i + 1 < s.length && _isEscapedPunctuation(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }

    // `code` (letterlijk, geen nesting)
    if (c == '`') {
      final end = s.indexOf('`', i + 1);
      if (end > i) {
        flush();
        out.add(ctx._with(code: true)._copyText(s.substring(i + 1, end)));
        i = end + 1;
        continue;
      }
    }

    // [tekst](url)
    if (c == '[') {
      final close = _matchClosingBracket(s, i);
      if (close != -1 && close + 1 < s.length && s[close + 1] == '(') {
        final paren = s.indexOf(')', close + 2);
        if (paren != -1) {
          flush();
          final inner = s.substring(i + 1, close);
          final url = s.substring(close + 2, paren).trim();
          _parseInto(inner, ctx._with(link: url), out);
          i = paren + 1;
          continue;
        }
      }
    }

    // **vet**
    if (c == '*' && i + 1 < s.length && s[i + 1] == '*') {
      final end = _findDelimiter(s, i + 2, '**');
      if (end != -1) {
        flush();
        _parseInto(s.substring(i + 2, end), ctx._with(bold: true), out);
        i = end + 2;
        continue;
      }
    }

    // ~~doorhalen~~
    if (c == '~' && i + 1 < s.length && s[i + 1] == '~') {
      final end = _findDelimiter(s, i + 2, '~~');
      if (end != -1) {
        flush();
        _parseInto(s.substring(i + 2, end), ctx._with(strike: true), out);
        i = end + 2;
        continue;
      }
    }

    // *cursief* of _cursief_
    if (c == '*' || c == '_') {
      final end = _findDelimiter(s, i + 1, c);
      if (end != -1 && end > i + 1) {
        flush();
        _parseInto(s.substring(i + 1, end), ctx._with(italic: true), out);
        i = end + 1;
        continue;
      }
    }

    // $inline-formule$ — alleen als de inhoud een LaTeX-commando bevat, zodat
    // gewone valuta (`$5`) en losse dollartekens tekst blijven. De inhoud gaat
    // ongeparsed als TeX door; de opmaakcontext (`ctx`) geldt er niet voor.
    if (c == r'$' && (i + 1 >= s.length || s[i + 1] != r'$')) {
      final end = _findInlineMathClose(s, i + 1);
      if (end != -1) {
        final tex = s.substring(i + 1, end);
        if (_looksLikeMath(tex)) {
          flush();
          out.add(const InlineRun('', math: true)._copyText(tex));
          i = end + 1;
          continue;
        }
      }
    }

    buf.write(c);
    i++;
  }
  flush();
}

/// Vind het index van het sluitteken [delim] vanaf [from], rekening houdend
/// met escapes. Geeft -1 als het er niet is.
int _findDelimiter(String s, int from, String delim) {
  var i = from;
  while (i <= s.length - delim.length) {
    if (s[i] == r'\') {
      i += 2;
      continue;
    }
    if (s.startsWith(delim, i)) return i;
    i++;
  }
  return -1;
}

/// De sluitende `$` van een inline-formule vanaf [from], escapes (`\$`)
/// overslaand. Geeft -1 als er geen sluitteken is, of als het volgende teken óók
/// een `$` is — dan is het `$$`-blokwiskunde en die hoort niet in een tekstregel.
int _findInlineMathClose(String s, int from) {
  var i = from;
  while (i < s.length) {
    if (s[i] == r'\') {
      i += 2;
      continue;
    }
    if (s[i] == r'$') {
      if (i + 1 < s.length && s[i + 1] == r'$') return -1;
      return i;
    }
    i++;
  }
  return -1;
}

/// Of [tex] eruitziet als een formule in plaats van valuta: minstens één
/// LaTeX-commando (`\` gevolgd door een letter). Zo blijft `$5` of `$5 tot $10`
/// gewoon tekst — alleen echte wiskunde wordt gerenderd.
bool _looksLikeMath(String tex) => RegExp(r'\\[a-zA-Z]').hasMatch(tex);

/// Vind de bijbehorende ']' voor de '[' op [open] (geneste haken meegerekend).
int _matchClosingBracket(String s, int open) {
  var depth = 0;
  for (var i = open; i < s.length; i++) {
    if (s[i] == r'\') {
      i++;
      continue;
    }
    if (s[i] == '[') depth++;
    if (s[i] == ']') {
      depth--;
      if (depth == 0) return i;
    }
  }
  return -1;
}

extension on InlineRun {
  InlineRun _copyText(String t) => InlineRun(
    t,
    bold: bold,
    italic: italic,
    code: code,
    strike: strike,
    math: math,
    link: link,
  );
}

/// De opmaak van één [run] boven op [base]. Links krijgen [linkColor] en een
/// onderstreping — ook zonder tikafhandelaar, want de lezer moet ze herkennen.
/// Zonder [linkColor] houdt een link de kleur van [base]: wie alleen meet heeft
/// geen kleur nodig, want kleur verandert geen enkele afmeting.
TextStyle inlineRunStyle(InlineRun run, TextStyle base, Color? linkColor) {
  var style = base;
  if (run.bold) style = style.copyWith(fontWeight: FontWeight.bold);
  if (run.italic) style = style.copyWith(fontStyle: FontStyle.italic);
  if (run.code) {
    style = style.copyWith(
      fontFamily: 'monospace',
      fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
    );
  }
  if (run.strike) {
    style = style.copyWith(
      decoration: TextDecoration.combine([
        if (style.decoration != null && style.decoration != TextDecoration.none)
          style.decoration!,
        TextDecoration.lineThrough,
      ]),
    );
  }
  if (run.link != null) {
    style = style.copyWith(
      color: linkColor ?? style.color,
      decoration: TextDecoration.underline,
      decorationColor: linkColor ?? style.color,
    );
  }
  return style;
}

/// Bouw opgemaakte, niet-klikbare [InlineSpan]s uit [text] — voor meten en
/// voor elk oppervlak dat geen tikafhandeling nodig heeft. Klikbare links
/// vragen om recognizers die iemand moet opruimen; dat doet `InlineMarkdownText`.
List<InlineSpan> buildInlineSpans(
  String text, {
  required TextStyle baseStyle,
  Color? linkColor,
}) {
  return [
    for (final run in parseInlineRuns(text))
      TextSpan(
        text: run.text,
        style: inlineRunStyle(run, baseStyle, linkColor),
      ),
  ];
}
