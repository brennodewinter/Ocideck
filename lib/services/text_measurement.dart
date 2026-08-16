import 'package:flutter/painting.dart';

import '../utils/inline_markdown.dart';

/// Meet met dezelfde inline-spans als de render: vet/cursief/code lopen breder
/// dan kale tekst op normaal gewicht, dus een platte meting onderschat het
/// aantal wrap-regels — waardoor de onderste regel van een volle pagina half
/// achter de logo-/footergrens kon verdwijnen. Zonder opmaaktekens volstaat
/// één platte span (goedkoper op de meet-hot-paths).
TextSpan _measurementSpan(String text, TextStyle style) {
  if (!hasInlineMarkdown(text)) return TextSpan(text: text, style: style);
  return TextSpan(
    style: style,
    children: buildInlineSpans(text, baseStyle: style),
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
  return _painterFor(text, fontSize, bold: bold, fontFamily: fontFamily).width;
}

/// Breedte van het breedste ondeelbare woord in [text].
///
/// Onder deze breedte breekt de regel middenin een woord — en zakt de kolom
/// onder haar eigen celmarge, dan tekent de tekst zelfs buiten de cel, dwars
/// over de tabellijnen heen. Vandaar de ondergrens per tabelkolom.
///
/// Gememoiseerd: de tabelmaatvoering meet élke cel, en doet dat opnieuw bij
/// elke stap van de letterzoektocht en bij elke herbouw. De functie is zuiver,
/// dus het geheugen is onzichtbaar; het loopt niet vol dankzij [_wordWidthCap].
double measureTextWordWidth(
  String text,
  double fontSize, {
  bool bold = false,
  String? fontFamily,
}) {
  final key = '$fontFamily|$fontSize|$bold|$text';
  final hit = _wordWidthCache[key];
  if (hit != null) return hit;
  final width = _painterFor(
    text,
    fontSize,
    bold: bold,
    fontFamily: fontFamily,
  ).minIntrinsicWidth;
  // Bij overschrijding in één keer leeggooien in plaats van per element
  // verdringen: een LRU-boekhouding kost hier meer dan de hermeting die hij
  // bespaart, en een tabelherbouw vult de cache meteen weer met wat hij nodig
  // heeft.
  if (_wordWidthCache.length >= _wordWidthCap) _wordWidthCache.clear();
  return _wordWidthCache[key] = width;
}

const int _wordWidthCap = 4096;
final Map<String, double> _wordWidthCache = {};

TextPainter _painterFor(
  String text,
  double fontSize, {
  required bool bold,
  required String? fontFamily,
}) {
  return TextPainter(
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
}
