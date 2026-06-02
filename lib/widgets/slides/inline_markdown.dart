import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Lichtgewicht inline-markdown: **vet**, *cursief* / _cursief_, `code`,
/// ~~doorhalen~~ en [tekst](url). Geen block-niveau (dat doet de slide-layout
/// al); puur de opmaak binnen één tekstregel.
///
/// Twee gebruiken:
///  - [stripInlineMarkdown] geeft de kale tekst (voor de auto-fit-metingen).
///  - [InlineMarkdownText] / [buildInlineSpans] rendert met opmaak en
///    (optioneel) klikbare links.

/// Eén stuk tekst met de actieve opmaak.
class InlineRun {
  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final bool strike;
  final String? link;

  const InlineRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.strike = false,
    this.link,
  });

  InlineRun _with({
    bool? bold,
    bool? italic,
    bool? code,
    bool? strike,
    String? link,
  }) {
    return InlineRun(
      text,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      code: code ?? this.code,
      strike: strike ?? this.strike,
      link: link ?? this.link,
    );
  }
}

const _markers = r'*_~`[]()\';

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
  }
  return false;
}

void _parseInto(String s, InlineRun ctx, List<InlineRun> out) {
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      out.add(ctx._with()._copyText(buf.toString()));
      buf.clear();
    }
  }

  var i = 0;
  while (i < s.length) {
    final c = s[i];

    // Escape: \* → *
    if (c == r'\' && i + 1 < s.length && _markers.contains(s[i + 1])) {
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
    link: link,
  );
}

/// Bouw [InlineSpan]s uit [text]. Voor links worden recognizers aangemaakt en
/// in [recognizers] geplaatst zodat de aanroeper ze kan opruimen (anders lekt
/// het). Zonder [onTapLink] krijgen links alleen styling.
List<InlineSpan> buildInlineSpans(
  String text, {
  required TextStyle baseStyle,
  required Color linkColor,
  List<GestureRecognizer>? recognizers,
  void Function(String url)? onTapLink,
}) {
  final runs = parseInlineRuns(text);
  return [
    for (final run in runs)
      TextSpan(
        text: run.text,
        style: _styleFor(run, baseStyle, linkColor),
        recognizer: (run.link != null && onTapLink != null)
            ? _makeRecognizer(run.link!, onTapLink, recognizers)
            : null,
      ),
  ];
}

TextStyle _styleFor(InlineRun run, TextStyle base, Color linkColor) {
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
      color: linkColor,
      decoration: TextDecoration.underline,
      decorationColor: linkColor,
    );
  }
  return style;
}

GestureRecognizer _makeRecognizer(
  String url,
  void Function(String url) onTap,
  List<GestureRecognizer>? sink,
) {
  final recognizer = TapGestureRecognizer()..onTap = () => onTap(url);
  sink?.add(recognizer);
  return recognizer;
}

/// Rendert [text] met inline-opmaak. Beheert link-recognizers leak-vrij.
class InlineMarkdownText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  final void Function(String url)? onTapLink;
  final int? maxLines;
  final TextAlign textAlign;
  final TextOverflow overflow;
  final bool softWrap;

  const InlineMarkdownText(
    this.text, {
    super.key,
    required this.style,
    required this.linkColor,
    this.onTapLink,
    this.maxLines,
    this.textAlign = TextAlign.start,
    this.overflow = TextOverflow.clip,
    this.softWrap = true,
  });

  @override
  State<InlineMarkdownText> createState() => _InlineMarkdownTextState();
}

class _InlineMarkdownTextState extends State<InlineMarkdownText> {
  final List<GestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers(); // verse set per build
    final spans = buildInlineSpans(
      widget.text,
      baseStyle: widget.style,
      linkColor: widget.linkColor,
      recognizers: _recognizers,
      onTapLink: widget.onTapLink,
    );
    return Text.rich(
      TextSpan(children: spans),
      maxLines: widget.maxLines,
      textAlign: widget.textAlign,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
    );
  }
}
