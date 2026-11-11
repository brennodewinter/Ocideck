import 'package:markdown/markdown.dart' as md;

/// Herkent `<u>tekst</u>` als inline-element in `package:markdown` (#2866).
///
/// Onderstrepen is geen standaard-Markdown, en `__tekst__` betekent in
/// OciDeck al vet — daarom is de conventie het begrensde tagpaar `<u>…</u>`,
/// de enige inline-HTML die we naast `<br>` betekenis geven. Deze syntax maakt
/// er een `md.Element('u', …)` van; wie dat element kent (de
/// Markdown-naar-visueel-codec, de LaTeX-schrijver) beslist dan zelf wat de
/// onderstreping wordt. Inhoud tussen de tags wordt gewoon inline verder
/// geparsed — `<u>**vet**</u>` blijft dus vet én onderstreept.
class UnderlineTagSyntax extends md.InlineSyntax {
  UnderlineTagSyntax() : super(r'<u>');

  @override
  bool onMatch(md.InlineParser parser, Match match) {
    final innerStart = match.end;
    final close = parser.source.indexOf('</u>', innerStart);
    if (close <= innerStart) {
      // Losse `<u>` of een leeg paar is letterlijke tekst, zoals elke andere
      // onafgesloten markering. Zelf vooruitgaan is verplicht — `false`
      // teruggeven zonder te consumeren laat de parser op dezelfde plek
      // staan.
      parser.advanceBy(match.end - parser.pos);
      return false;
    }
    final inner = parser.source.substring(innerStart, close);
    parser.addNode(md.Element('u', parser.document.parseInline(inner)));
    // `consume` markeert de bron als opgegeten; `advanceBy` alleen zou de
    // rauwe `<u>…</u>`-tekst alsnog als tekst-node uitspugen naast het element.
    parser.consume(close + 4 - parser.pos);
    return false;
  }
}
