// Een gerenderde SVG klaarmaken voor de PDF-lezer.
//
// De SVG's die hier binnenkomen zijn gemaakt voor een browser, en de
// SVG-lezer van `package:pdf` is dat niet. Twee dingen lopen daarop stuk, en
// allebei zijn ze in de eerste echte render zichtbaar geworden:
//
//  * **De maat.** Mermaid geeft zijn maat in pixels, MathJax in `ex`, en onze
//    grafiekgenerator zet er `100%` neer omdat dat in HTML "vul de kolom"
//    betekent. De lezer leest die waarden als punten: `12.3ex` wordt twaalf
//    punten, en dan is de formule een stipje. Daarom halen we de maat er hier af
//    en rekenen we hem zelf uit — zodat de renderer weet hoe groot de tekening
//    *bedoeld* is en hem niet hoeft te raden.
//  * **`currentColor`.** MathJax kleurt zijn glyphs daarmee: neem de kleur van de
//    omringende tekst. In een browser vanzelfsprekend, voor deze lezer een
//    onbekende kleur — en een onbekende kleur tekent niets. Hier wordt het de
//    inkt van het document.
//  * **Een streepjespatroon van niets.** Mermaid schrijft op elke verbindingslijn
//    `stroke-dasharray: 0px`. Een browser leest dat als "geen streepjes"; de
//    SVG-specificatie zegt dat een patroon waarin alles nul is genegeerd wordt.
//    Deze lezer neemt het letterlijk en tekent streepjes van lengte nul met
//    tussenruimtes van lengte nul — oftewel niets. In de eerste echte render
//    stond het stroomdiagram er mét zijn vakjes en pijlpunten maar zónder één
//    lijn ertussen, en dat is precies het soort fout dat geen enkele test met
//    verwachtingswaarden ziet.

/// De maat die een tekening zelf bedoelt, in punten.
class SvgIntrinsicSize {
  const SvgIntrinsicSize(this.width, this.height);

  final double width;
  final double height;

  @override
  String toString() =>
      'SvgIntrinsicSize(${width.toStringAsFixed(1)}×${height.toStringAsFixed(1)}pt)';
}

/// Een SVG zoals de PDF-lezer hem wil hebben, plus de maat die eruit bleek.
class PreparedSvg {
  const PreparedSvg(this.svg, this.size);

  final String svg;

  /// `null` wanneer de tekening geen bruikbare maat opgaf. De renderer geeft
  /// hem dan de volle bladspiegel.
  final SvgIntrinsicSize? size;
}

/// CSS-pixels naar PDF-punten. Een CSS-pixel is 1/96 duim, een punt 1/72.
const _pxToPt = 72 / 96;

/// Hoe hoog een `ex` is, uitgedrukt in de letterhoogte.
///
/// Een `ex` is de x-hoogte van de omringende letter, en die ligt voor vrijwel
/// elke tekstletter rond 45% van de korpsgrootte. MathJax rekent zijn hele maat
/// in deze eenheid; zonder omrekening komt een formule als een handvol punten
/// uit de bus.
const _exToEm = 0.45;

/// Maakt [svg] klaar voor de PDF-lezer: maat eraf en zelf uitgerekend,
/// `currentColor` vervangen door [inkHex].
///
/// [fontSizePt] is de letterhoogte van de lopende tekst; die bepaalt hoe groot
/// een `ex` is en dus hoe groot een formule wordt gezet.
PreparedSvg prepareSvgForPdf(
  String svg, {
  required String inkHex,
  required double fontSizePt,
}) {
  final root = _rootTag(svg);
  final size = root == null ? null : _intrinsicSize(root, fontSizePt);
  var out = svg;
  if (root != null) {
    // De maat eraf: wat de lezer aan `width`/`height` leest, zou hij als punten
    // opvatten. De `viewBox` blijft staan — dát is de tekening.
    final stripped = root.replaceAll(_sizeAttribute, '');
    out = out.replaceFirst(root, stripped);
  }
  // `currentColor` erft in een browser de tekstkleur; hier is er geen tekst om
  // van te erven, dus zeggen we welke inkt bedoeld is.
  out = out.replaceAll('currentColor', inkHex);
  out = _dropEmptyDashArrays(out);
  return PreparedSvg(out, size);
}

/// De openingstag van de SVG, of `null` als die er niet in staat.
String? _rootTag(String svg) {
  final match = RegExp(r'<svg\b[^>]*>', caseSensitive: false).firstMatch(svg);
  return match?.group(0);
}

final _sizeAttribute = RegExp(
  r'''\s(?:width|height)\s*=\s*(?:"[^"]*"|'[^']*')''',
  caseSensitive: false,
);

/// De bedoelde maat, uit `width`/`height` en anders uit de `viewBox`.
SvgIntrinsicSize? _intrinsicSize(String root, double fontSizePt) {
  final width = _length(root, 'width', fontSizePt);
  final height = _length(root, 'height', fontSizePt);
  if (width != null && height != null) return SvgIntrinsicSize(width, height);

  // Geen bruikbare maat opgegeven (of alleen een percentage): val terug op de
  // `viewBox` en lees die als pixels, want zo bedoelen zowel mermaid als onze
  // eigen generator hem.
  final box = RegExp(
    r'''viewBox\s*=\s*["']\s*([-\d.eE]+)[,\s]+([-\d.eE]+)[,\s]+([-\d.eE]+)[,\s]+([-\d.eE]+)''',
    caseSensitive: false,
  ).firstMatch(root);
  if (box == null) return null;
  final w = double.tryParse(box.group(3)!);
  final h = double.tryParse(box.group(4)!);
  if (w == null || h == null || w <= 0 || h <= 0) return null;
  return SvgIntrinsicSize(w * _pxToPt, h * _pxToPt);
}

/// Eén lengte-attribuut, omgerekend naar punten. `null` bij een percentage of
/// iets onleesbaars — dan zegt het attribuut niets over een absolute maat.
double? _length(String root, String name, double fontSizePt) {
  final match = RegExp(
    '''$name\\s*=\\s*["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(root);
  if (match == null) return null;
  final raw = match.group(1)!.trim();
  if (raw.isEmpty || raw.endsWith('%')) return null;
  final number = double.tryParse(
    RegExp(r'^-?[\d.]+(?:[eE][-+]?\d+)?').firstMatch(raw)?.group(0) ?? '',
  );
  if (number == null || number <= 0) return null;
  if (raw.endsWith('ex')) return number * _exToEm * fontSizePt;
  if (raw.endsWith('em')) return number * fontSizePt;
  if (raw.endsWith('pt')) return number;
  // Kaal of in pixels: allebei CSS-pixels.
  return number * _pxToPt;
}

/// Haalt een streepjespatroon weg waarin alles nul is.
///
/// `stroke-dasharray: 0px` betekent in een browser "geen streepjes" — de
/// SVG-specificatie zegt dat een patroon zonder positieve waarde genegeerd
/// wordt. De lezer van `package:pdf` neemt het letterlijk, en dan is de lijn
/// weg. Mermaid schrijft dit op élke verbindingslijn.
String _dropEmptyDashArrays(String svg) => svg.replaceAllMapped(_dashArray, (
  match,
) {
  // Drie schrijfwijzen, één waarde: tussen dubbele of enkele aanhalingstekens
  // (los attribuut) of kaal (een regel in een `style`).
  final value = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
  final numbers = RegExp(
    r'-?\d*\.?\d+',
  ).allMatches(value).map((m) => double.tryParse(m.group(0)!) ?? 0);
  // Alleen weghalen wat werkelijk niets tekent; een echt streepjespatroon
  // hoort gewoon een streepjespatroon te blijven.
  if (numbers.isNotEmpty && numbers.any((n) => n > 0)) return match.group(0)!;
  // De scheiding die ervóór stond blijft staan, anders plakken twee regels of
  // twee attributen aan elkaar.
  return match.group(1) ?? '';
});

/// Een `stroke-dasharray`, als los attribuut of als regel in een `style`.
final _dashArray = RegExp(
  r'''(\s|;)?stroke-dasharray\s*[:=]\s*(?:"([^"]*)"|'([^']*)'|([^;"']*))\s*;?''',
  caseSensitive: false,
);

/// De letterlijke tekst uit de `<text>`- en `<tspan>`-knopen van [svg].
///
/// Waarvoor: een tekening wordt met één snede gezet, en een teken dat die snede
/// niet kent verdwijnt daar als leeg blokje — zonder foutmelding, en zonder dat
/// de tekstlaag er iets van laat zien. De export meldt zulke tekens al voor de
/// lopende tekst ([DocumentPdfFonts.unsupportedRunes]); zonder deze lezer stopt
/// die belofte bij de rand van elke grafiek en elk diagram (#1942).
///
/// Bewust krap gelezen, en precies andersom dan
/// [DocumentPdfFonts.svgTypesetting]: dáár is te ruim kiezen ongevaarlijk (een
/// tekening komt onnodig op een ander font), maar hier is te ruim lezen dat
/// niet. Een melding die een teken noemt dat wél gewoon in het bestand staat,
/// leert de gebruiker de melding negeren. Wat deze regel niet ziet, blijft dus
/// ongemeld — een teken minder gemeld is beter dan een teken ten onrechte.
String svgTextContent(String svg) =>
    _svgTextNode.allMatches(svg).map((match) => match.group(1)!).join(' ');

final _svgTextNode = RegExp(
  r'<(?:text|tspan)\b[^>]*>([^<]*)',
  caseSensitive: false,
);
