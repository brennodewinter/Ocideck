import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import '../../utils/inline_markdown.dart';

/// De widgetkant van de inline-markdown: opmaak mét klikbare links. Het parsen
/// en de opmaak zelf staan in `utils/inline_markdown.dart`, zodat de headless
/// diensten (meten, kwaliteitsanalyse) daar terechtkunnen zonder widgets.

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

  /// Een span die ná de tekst in dezelfde paragraaf meeloopt — zodat hij tegen
  /// het laatste woord blijft plakken en met de tekst mee afbreekt in plaats van
  /// naast het blok te zweven. Gebruikt voor de "(2/3)"-titelteller (#1164).
  final InlineSpan? trailing;

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
    this.trailing,
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

  /// Zelfde spans als [buildInlineSpans], maar met een tikafhandelaar per link.
  /// De recognizers komen in [_recognizers] terecht omdat ze anders lekken:
  /// alleen deze State weet wanneer ze weg mogen.
  List<InlineSpan> _spans() {
    final onTapLink = widget.onTapLink;
    return [
      for (final run in parseInlineRuns(widget.text))
        if (run.math)
          // Inline `$…$` als echte formule; op de tekstbaseline zodat hij mee
          // op de regel staat. Faalt de TeX, dan valt hij terug op de kale bron
          // tussen dollartekens — zichtbaar fout is beter dan stilweg leeg.
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: Math.tex(
              run.text,
              textStyle: TextStyle(
                fontSize: widget.style.fontSize,
                color: widget.style.color,
              ),
              onErrorFallback: (_) =>
                  Text('\$${run.text}\$', style: widget.style),
            ),
          )
        else
          TextSpan(
            text: run.text,
            style: inlineRunStyle(run, widget.style, widget.linkColor),
            recognizer: (run.link != null && onTapLink != null)
                ? _recognizerFor(run.link!, onTapLink)
                : null,
          ),
    ];
  }

  GestureRecognizer _recognizerFor(String url, void Function(String) onTap) {
    final recognizer = TapGestureRecognizer()..onTap = () => onTap(url);
    _recognizers.add(recognizer);
    return recognizer;
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers(); // verse set per build
    return Text.rich(
      TextSpan(children: [..._spans(), ?widget.trailing]),
      maxLines: widget.maxLines,
      textAlign: widget.textAlign,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
    );
  }
}
