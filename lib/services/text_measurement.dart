import 'package:flutter/material.dart';

import '../widgets/slides/inline_markdown.dart';

double measureTextHeight(
  String text,
  double fontSize,
  double maxWidth, {
  double? lineHeight,
  bool bold = false,
  String? fontFamily,
}) {
  final painter = TextPainter(
    text: TextSpan(
      text: stripInlineMarkdown(text),
      style: TextStyle(
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
    text: TextSpan(
      text: stripInlineMarkdown(text),
      style: TextStyle(
        fontFamily: fontFamily,
        fontSize: fontSize,
        fontWeight: bold ? FontWeight.bold : null,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  return painter.width;
}
