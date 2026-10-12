/// De toelichting bij een TLP-keuze, als gewone alinea.
///
/// Geen anker en geen eigen sleutel: na het invoegen is de tekst van de
/// gebruiker. Een latere opslag herschrijft hem niet, en weghalen laat `tlp:`
/// staan (#2396).
library;

/// Zet [paragraph] onder de eerste kop, of vooraan als er geen kop is.
///
/// Staat [sentence] al in [body], dan blijft de tekst zoals hij is: de
/// toelichting wordt niet verdubbeld.
String insertTlpExplanation(String body, String paragraph, String sentence) {
  if (paragraph.trim().isEmpty || sentence.trim().isEmpty) return body;
  if (body.contains(sentence)) return body;
  final lines = body.split('\n');
  var at = 0;
  for (var i = 0; i < lines.length; i++) {
    if (lines[i].startsWith('# ')) {
      at = i + 1;
      while (at < lines.length && lines[at].trim().isEmpty) {
        at++;
      }
      break;
    }
  }
  // Eén witregel vóór de alinea, tenzij die er al staat (de kop heeft er
  // meestal al een). Eén witregel erna, zodat de volgende alinea los blijft.
  final leading = at > 0 && lines[at - 1].trim().isNotEmpty
      ? const ['']
      : const <String>[];
  lines.insertAll(at, [...leading, paragraph.trim(), '']);
  return lines.join('\n');
}

/// De alinea: de standaardzin, dan de ontvangers, dan een eigen zin.
String tlpExplanationParagraph({
  required String sentence,
  required String audienceLine,
  String note = '',
}) {
  final extra = note.trim();
  return [
    sentence.trim(),
    if (audienceLine.trim().isNotEmpty) audienceLine.trim(),
    if (extra.isNotEmpty) extra,
  ].join('\n');
}
