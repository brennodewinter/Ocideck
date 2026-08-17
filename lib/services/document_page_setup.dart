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
/// De `geometry`-string komt uit dezelfde bron als de LaTeX-export
/// ([PageMargins.latexMargin] en [PageSizeSpec.latexPaperWith]), zodat het
/// bestand en de export het niet oneens kunnen zijn.
typedef DocumentPageSetup = ({PageSizeSpec? size, PageMargins? margins});

/// Niets gezet: het document laat de opmaak aan de instellingen.
const DocumentPageSetup kNoDocumentPageSetup = (size: null, margins: null);

/// De paginaopmaak die [source] draagt. Beide velden zijn `null` wanneer het
/// document er niets over zegt; ze kunnen ook los voorkomen (alleen een maat,
/// alleen marges).
DocumentPageSetup documentPageSetup(String source) => (
  size: _parsePaperSize(documentFrontMatterValue(source, 'papersize')),
  margins: _parseGeometry(documentFrontMatterValue(source, 'geometry')),
);

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

/// Leest een `geometry`-waarde terug naar marges plus, wanneer het vel groter
/// is dan een ISO-maat, de afloop die dat verschil verklaart.
PageMargins? _parseGeometry(String? value) {
  final v = value?.trim();
  if (v == null || v.isEmpty) return null;
  final fields = <String, double>{};
  for (final part in v.split(',')) {
    final kv = part.split('=');
    if (kv.length != 2) continue;
    final mm = double.tryParse(kv[1].trim().replaceAll('mm', '').trim());
    if (mm != null) fields[kv[0].trim().toLowerCase()] = mm;
  }
  if (fields.isEmpty) return null;
  final bleed = _inferBleed(fields);
  return PageMargins(
    // De marges in het bestand zijn gemeten vanaf de rand van het vél; de
    // afloop hoort er weer af, want intern rekent OciDeck vanaf het
    // snijformaat.
    topMm: (fields['top'] ?? 25) - bleed,
    bottomMm: (fields['bottom'] ?? 25) - bleed,
    leftMm: (fields['left'] ?? 20) - bleed,
    rightMm: (fields['right'] ?? 20) - bleed,
    bleedMm: bleed,
  );
}

/// De afloop die uit een expliciete papiermaat volgt: is het vel aan beide
/// zijden even veel groter dan een bestaande ISO-maat, dan is dat verschil de
/// afloop. Anders is het gewoon een vrije maat en is er geen afloop.
///
/// Dit is een gemak voor de interface ("A4 + 3 mm"), geen betekenis in het
/// bestand: daar staat de effectieve maat, en die is op zichzelf compleet.
double _inferBleed(Map<String, double> fields) {
  final w = fields['paperwidth'];
  final h = fields['paperheight'];
  if (w == null || h == null) return 0;
  for (final series in PaperSeries.values) {
    for (var n = 0; n <= 10; n++) {
      for (final landscape in [false, true]) {
        final (pw, ph) = PageSizeSpec(
          series: series,
          number: n,
          landscape: landscape,
        ).dimensions;
        final dw = w - pw;
        final dh = h - ph;
        if (dw > 0 && (dw - dh).abs() < 0.51 && dw / 2 <= 20) {
          return (dw / 2 * 10).roundToDouble() / 10;
        }
      }
    }
  }
  return 0;
}

String _mm(double mm) =>
    mm == mm.roundToDouble() ? mm.toStringAsFixed(0) : mm.toString();
