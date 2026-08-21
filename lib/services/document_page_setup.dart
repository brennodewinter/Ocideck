import '../models/page_size.dart';
import '../utils/document_front_matter.dart';

/// De paginaopmaak die een document zélf draagt: papiermaat, marges en een
/// eventuele drukkersafloop, in de front matter van het platte `.md`.
///
/// Waarom in het bestand en niet (alleen) in de instellingen: de afloop is geen
/// voorkeur maar een eigenschap van dít drukwerk, en een verstuurde PDF hoort
/// reproduceerbaar te zijn. Wie niets kiest houdt een `.md` zonder front matter
/// en krijgt de app-instelling — er wordt niets automatisch geschreven.
///
/// Waarom in dit vocabulaire: `papersize:` en `geometry:` worden door Pandoc
/// écht uitgevoerd. Wie het bestand door zijn eigen Pandoc haalt krijgt dezelfde
/// pagina, zonder OciDeck. Een eigen `ocideck_page_size:` zou bytes meesturen
/// die alleen binnen OciDeck betekenis hebben, en FILE_FORMAT.md §14.1 belooft
/// dat OciDeck geen eigen sleutels toevoegt.
///
/// De marges in `geometry` komen uit [PageMargins.latexMargin] — dezelfde bron
/// als de LaTeX-export. De papiermaat wordt hier lokaal uitgerekend en niet uit
/// [PageSizeSpec.latexPaperWith] gehaald: die geeft niets terug zonder afloop,
/// terwijl een liggend vel hier óók expliciete maten nodig heeft. Zelfde
/// pagina, andere route — de LaTeX-export schrijft voor liggend-zonder-afloop
/// een papiernaam met `landscape`, dit bestand millimeters.
typedef DocumentPageSetup = ({PageSizeSpec? size, PageMargins? margins});

/// Niets gezet: het document laat de opmaak aan de instellingen.
const DocumentPageSetup kNoDocumentPageSetup = (size: null, margins: null);

/// Of [source] zélf een paginaopmaak draagt.
///
/// Kijkt naar béide sleutels en niet alleen naar de papiernaam: een document
/// dat OciDeck met afloop of liggend heeft vastgelegd draagt juist géén
/// `papersize:`, en werd dan aangemerkt als "komt uit je instellingen" —
/// precies verkeerd om.
bool documentCarriesPageSetup(String source) {
  final setup = documentPageSetup(source);
  return setup.size != null || setup.margins != null;
}

/// Of de `geometry:`-frontmatter in [source] ongeldig is: waarden die niet
/// eindig of negatief zijn, of marges die samen breder/hoger zijn dan het vel.
/// Geeft `null` wanneer de frontmatter geldig is of ontbreekt — alleen een
/// écht ongeldige opmaak die genegeerd is levert een reden, zodat de
/// aanroeper een begrijpelijke melding kan tonen.
String? documentPageSetupInvalidReason(String source) {
  final value = documentFrontMatterValue(source, 'geometry');
  final v = value?.trim();
  if (v == null || v.isEmpty) return null;
  // Een geometry met alleen rommel (geen parseerbare key=value) is geen
  // ongeldige opmaak maar een lege, en die hoort geen melding.
  final hasNumericField = v.split(',').any((part) {
    final kv = part.split('=');
    if (kv.length != 2) return false;
    return double.tryParse(kv[1].trim().replaceAll('mm', '').trim()) != null;
  });
  if (!hasNumericField) return null;
  final setup = _parseGeometry(value);
  if (setup == kNoDocumentPageSetup) return 'invalid-geometry';
  if (setup.margins != null && !setup.margins!.isValid) {
    return 'invalid-geometry';
  }
  // De marges kunnen individueel geldig zijn maar samen breder/hoger dan
  // het vel — dat levert een negatieve tekstspiegel op.
  final size =
      _parsePaperSize(documentFrontMatterValue(source, 'papersize')) ??
      setup.size;
  if (size != null &&
      setup.margins != null &&
      !marginsFitPaper(size, setup.margins!)) {
    return 'margins-exceed-paper';
  }
  return null;
}

/// De paginaopmaak die [source] draagt. Beide velden zijn `null` wanneer het
/// document er niets over zegt; ze kunnen ook los voorkomen (alleen een maat,
/// alleen marges).
DocumentPageSetup documentPageSetup(String source) {
  final geometry = _parseGeometry(documentFrontMatterValue(source, 'geometry'));
  return (
    // De papiernaam wint wanneer hij er staat; anders komt de maat uit de
    // expliciete millimeters in `geometry`. Dat tweede pad is niet optioneel:
    // met een afloop of liggend schríjven we geen papiernaam, want die zou
    // liegen — zonder deze terugweg viel de vastgelegde maat bij het inlezen
    // terug op de instelling, en was het vastleggen dus zinloos.
    size:
        _parsePaperSize(documentFrontMatterValue(source, 'papersize')) ??
        geometry.size,
    margins: geometry.margins,
  );
}

/// [source] met de paginaopmaak gezet, of eruit gehaald wanneer beide `null`
/// zijn. Byte-chirurgisch, met dezelfde regels als de stijl: zetten en weer
/// wissen geeft de oorspronkelijke bytes terug.
String withDocumentPageSetup(
  String source, {
  required PageSizeSpec? size,
  required PageMargins? margins,
}) {
  var out = withDocumentFrontMatterKey(
    source,
    'papersize',
    // Met afloop is het vel groter dan het snijformaat; dan zegt een
    // papiernaam niet meer wat het is en dragen de expliciete maten in
    // `geometry` het verhaal.
    size == null || (margins?.hasBleed ?? false) ? null : _paperSizeValue(size),
  );
  out = withDocumentFrontMatterKey(
    out,
    'geometry',
    margins == null ? null : _geometryValue(size, margins),
  );
  return out;
}

/// De Pandoc-waarde voor een papiermaat: kleine letters, zoals `a4`. Alleen
/// staande ISO-maten hebben een naam die Pandoc kent; liggend en de rest gaan
/// als expliciete maten door `geometry`.
String? _paperSizeValue(PageSizeSpec size) =>
    size.landscape ? null : size.sizeName.toLowerCase();

/// De `geometry`-waarde: de marges, met bij een afloop of een liggende maat ook
/// het vel zelf. Dat is exact wat de LaTeX-export al schrijft.
String _geometryValue(PageSizeSpec? size, PageMargins margins) {
  final paper = size == null
      ? null
      : (margins.hasBleed || size.landscape
            ? _explicitPaper(size, margins)
            : null);
  return paper == null ? margins.latexMargin : '$paper,${margins.latexMargin}';
}

String _explicitPaper(PageSizeSpec size, PageMargins margins) {
  final (w, h) = size.dimensions;
  final bleed = margins.bleedMm * 2;
  return 'paperwidth=${_mm(w + bleed)}mm,paperheight=${_mm(h + bleed)}mm';
}

PageSizeSpec? _parsePaperSize(String? value) {
  final v = value?.trim().toLowerCase();
  if (v == null || v.isEmpty) return null;
  // `a4` en `a4paper` zijn allebei in omloop; beide lezen we.
  final m = RegExp(r'^([abc])(\d{1,2})(?:paper)?$').firstMatch(v);
  if (m == null) return null;
  return PageSizeSpec.fromId('${m.group(1)!.toUpperCase()}${m.group(2)}');
}

/// Leest een `geometry`-waarde terug naar de maat (als het vel een ISO-formaat
/// is, eventueel plus afloop) en de marges.
DocumentPageSetup _parseGeometry(String? value) {
  final v = value?.trim();
  if (v == null || v.isEmpty) return kNoDocumentPageSetup;
  final fields = <String, double>{};
  for (final part in v.split(',')) {
    final kv = part.split('=');
    if (kv.length != 2) continue;
    final mm = double.tryParse(kv[1].trim().replaceAll('mm', '').trim());
    if (mm == null) continue;
    // double.tryParse aanvaardt 'NaN' en 'Infinity' als geldige doubles.
    // Die bereiken de layout als negatieve of oneindige maten en crashen
    // de paginering. Een ongeldig getal legt het hele geometry-blok plat
    // (terugval op defaults met een melding), in plaats van stíl één veld
    // te vervangen — de gebruiker hoort te weten dat zijn frontmatter
    // genegeerd is, niet dat de helft ervan stiekum vervangen is.
    if (!mm.isFinite || mm < 0) return kNoDocumentPageSetup;
    fields[kv[0].trim().toLowerCase()] = mm;
  }
  if (fields.isEmpty) return kNoDocumentPageSetup;
  final paper = _inferPaper(fields);
  final bleed = paper?.bleedMm ?? 0;
  final margins = PageMargins(
    // De marges in het bestand zijn gemeten vanaf de rand van het vél; de
    // afloop hoort er weer af, want intern rekent OciDeck vanaf het
    // snijformaat.
    topMm: (fields['top'] ?? 25) - bleed,
    bottomMm: (fields['bottom'] ?? 25) - bleed,
    leftMm: (fields['left'] ?? 20) - bleed,
    rightMm: (fields['right'] ?? 20) - bleed,
    bleedMm: bleed,
  );
  // De afloop kan groter zijn dan een marge (bijv. top=20mm met 30mm afloop
  // geeft topMm=-10), of een NaN glipt erdoor via een edge-case. Een
  // ongeldig resultaat valt terug op defaults, net als een afwezige geometry.
  if (!margins.isValid) return kNoDocumentPageSetup;
  return (size: paper?.size, margins: margins);
}

/// Het vel dat uit een expliciete papiermaat volgt: welke ISO-maat het is, en
/// hoeveel afloop er dan omheen zit.
///
/// Is het vel aan beide zijden even veel groter dan een bestaande ISO-maat, dan
/// is dat verschil de afloop. Past het op geen enkele maat, dan is het een vrije
/// maat: geen ISO-naam, geen afloop.
///
/// Dit is een gemak voor de interface ("A4 + 3 mm"), geen betekenis in het
/// bestand: daar staat de effectieve maat, en die is op zichzelf compleet.
({PageSizeSpec size, double bleedMm})? _inferPaper(Map<String, double> fields) {
  final w = fields['paperwidth'];
  final h = fields['paperheight'];
  if (w == null || h == null) return null;
  for (final series in PaperSeries.values) {
    for (var n = 0; n <= 10; n++) {
      for (final landscape in [false, true]) {
        final spec = PageSizeSpec(
          series: series,
          number: n,
          landscape: landscape,
        );
        final (pw, ph) = spec.dimensions;
        final dw = w - pw;
        final dh = h - ph;
        // Even veel eraf aan beide zijden, en niet negatief: dan is dit de maat
        // met die afloop eromheen. Nul verschil is gewoon de maat zelf.
        if (dw >= -0.01 && (dw - dh).abs() < 0.51 && dw / 2 <= 20) {
          return (size: spec, bleedMm: (dw / 2 * 10).roundToDouble() / 10);
        }
      }
    }
  }
  return null;
}

String _mm(double mm) =>
    mm == mm.roundToDouble() ? mm.toStringAsFixed(0) : mm.toString();
