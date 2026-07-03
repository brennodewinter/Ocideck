import 'package:flutter/material.dart';

import '../widgets/slides/inline_markdown.dart';

/// Meet met dezelfde inline-spans als de render: vet/cursief/code lopen breder
/// dan kale tekst op normaal gewicht, dus een platte meting onderschat het
/// aantal wrap-regels — waardoor de onderste regel van een volle pagina half
/// achter de logo-/footergrens kon verdwijnen. Zonder opmaaktekens volstaat
/// één platte span (goedkoper op de meet-hot-paths).
TextSpan _measurementSpan(String text, TextStyle style) {
  if (!hasInlineMarkdown(text)) return TextSpan(text: text, style: style);
  return TextSpan(
    style: style,
    children: buildInlineSpans(
      text,
      baseStyle: style,
      linkColor: const Color(0xFF000000),
    ),
  );
}

double measureTextHeight(
  String text,
  double fontSize,
  double maxWidth, {
  double? lineHeight,
  bool bold = false,
  String? fontFamily,
}) {
  final painter = TextPainter(
    text: _measurementSpan(
      text,
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        height: lineHeight,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth.isFinite ? maxWidth : double.infinity);
  return painter.height;
}

double measureTextWidth(
  String text,
  double fontSize, {
  bool bold = false,
  String? fontFamily,
}) {
  final painter = TextPainter(
    text: _measurementSpan(
      text,
      TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}
