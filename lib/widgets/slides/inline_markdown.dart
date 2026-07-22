import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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

  /// Zelfde spans als [buildInlineSpans], maar met een tikafhandelaar per link.
  /// De recognizers komen in [_recognizers] terecht omdat ze anders lekken:
  /// alleen deze State weet wanneer ze weg mogen.
  List<InlineSpan> _spans() {
    final onTapLink = widget.onTapLink;
    return [
      for (final run in parseInlineRuns(widget.text))
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
      TextSpan(children: _spans()),
      maxLines: widget.maxLines,
      textAlign: widget.textAlign,
      overflow: widget.overflow,
      softWrap: widget.softWrap,
    );
  }
}
