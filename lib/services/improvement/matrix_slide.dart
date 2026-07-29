// De brug tussen een `matrix`-dia en het matrixmodel (PROCESS_IMPROVEMENT §3.1).
//
// Op schijf is een matrix een gewone Markdown-tabel: de eerste rij is de kop,
// de rest zijn gegevens, en `<!-- ocideck_template: fmea -->` zegt welk artefact
// het is. Alles wat te berekenen valt — vandaag de RPN — staat er *niet* in.
//
// Dat laatste is geen zuinigheid maar de enige manier om te voorkomen dat het
// bestand iets anders beweert dan de cijfers ernaast: een opgeslagen RPN van 210
// blijft staan als de S naar 3 gaat. Dezelfde regel als de ernst uit de
// CVSS-vector in de pentestmodule, en als de regelgrenzen van een control chart.
//
// Puur Dart, geen Flutter: de layout-engine en de SVG-export leunen hierop.
library;

import '../../models/slide.dart';
import 'matrix_spec.dart';

/// De kop die een matrix wegschrijft: de Engelse kolomlabels.
///
/// Waarom Engels en niet de taal van de auteur. De kop is een *contract* — de
/// parser leest de kolommen eraan terug — en die mag niet van de interfacetaal
/// afhangen, anders opent een deck dat in het Nederlands is gemaakt straks in
/// het Frans met vijf onbekende kolommen. Precies de afspraak die de
/// MIAUW-tabellen al hanteren (`ID`, `Test`, `Status`), en het voorbeeld in
/// §3.1 schrijft hem ook zo. De weergave gebruikt het label van de gekozen
/// rapportagetaal; de kop op schijf blijft staan.
List<String> matrixHeaderRow(ImprovementTemplate template) => [
  for (final column in template.storedColumns) column.labelEn,
];

/// De kolommen zoals ze in [slide] *bewaard* zijn: die van het sjabloon, of —
/// bij een onbekend sjabloon — de opgeslagen kop als kolomnamen.
///
/// De terugval is wat een matrix leesbaar houdt als het sjabloon er niet is.
/// Zonder haar zou een deck met een eigen sjabloonpakket als leeg raster openen.
List<MatrixColumn> matrixStoredColumns(Slide slide) {
  final template = improvementTemplateById(slide.improvementTemplateId);
  if (template != null) return template.storedColumns;
  final header = slide.tableRows.isEmpty
      ? const <String>[]
      : slide.tableRows.first;
  return [
    for (final label in header)
      MatrixColumn(key: _keyFor(label), labelNl: label, labelEn: label),
  ];
}

/// Alle kolommen die de weergave toont — de bewaarde plus de afgeleide.
List<MatrixColumn> matrixDisplayColumns(Slide slide) {
  final template = improvementTemplateById(slide.improvementTemplateId);
  if (template == null) return matrixStoredColumns(slide);
  return template.columns;
}

/// De matrix van [slide] als model: kolommen van het sjabloon, rijen uit de
/// tabel zonder de kopregel.
MatrixSpec matrixSpecFromSlide(Slide slide) {
  final columns = matrixStoredColumns(slide);
  return MatrixSpec(
    templateId: slide.improvementTemplateId,
    columns: columns,
    rows: [
      for (final row in slide.tableRows.skip(1)) _fitRow(row, columns.length),
    ],
    layout: MatrixLayout.grid,
  );
}

/// De afgeleide RPN van [row], of null wanneer dit geen risicomatrix is of een
/// factor ontbreekt. Dunne doorgeefwikkel zodat de aanroepers niet allemaal
/// zelf de kolomlijst hoeven op te halen.
int? matrixRowRpn(Slide slide, List<String> row) =>
    MatrixSpec.derivedRpn(row, matrixStoredColumns(slide));

/// Of dit sjabloon een afgeleide kolom draagt (vandaag: de RPN van een FMEA).
bool matrixHasDerivedColumn(Slide slide) =>
    matrixDisplayColumns(slide).any((c) => c.derived);

/// De gegevensrijen in *weergave*-orde: hoogste RPN eerst.
///
/// Het bestand houdt de orde van de auteur — dat houdt de diff stabiel en laat
/// een rij staan waar hij hem zette. De dia argumenteert de andere kant op:
/// waar zit het risico. Dus wordt er hier gesorteerd en nergens opgeslagen.
///
/// Een rij zonder RPN zakt naar onderen, want "we weten het niet" is geen 0 en
/// hoort niet tussen de lage risico's te gaan staan.
List<List<String>> matrixDisplayRows(Slide slide) {
  final rows = [for (final row in slide.tableRows.skip(1)) row];
  if (!matrixHasDerivedColumn(slide)) return rows;
  final columns = matrixStoredColumns(slide);
  final ranked = [...rows];
  ranked.sort((a, b) {
    final ra = MatrixSpec.derivedRpn(a, columns);
    final rb = MatrixSpec.derivedRpn(b, columns);
    if (ra == null && rb == null) return 0;
    if (ra == null) return 1;
    if (rb == null) return -1;
    return rb.compareTo(ra);
  });
  return ranked;
}

/// De tabelrijen voor [templateId] met de gegevens van [slide] erin gepast.
///
/// Van sjabloon wisselen mag geen ingevuld werk weggooien: wat in dezelfde
/// kolom (op *sleutel*, niet op plek) bestond, verhuist mee; de rest komt leeg.
/// Zonder die overzetting zou één misklik in de keuzelijst een uur invulwerk
/// wissen — en dat is geen theoretisch risico, het is de eerste handeling die
/// iemand doet die zich vergist heeft in het artefact.
List<List<String>> matrixRowsForTemplate(Slide slide, String templateId) {
  final target = improvementTemplateById(templateId);
  if (target == null) return slide.tableRows;
  final oldColumns = matrixStoredColumns(slide);
  final newColumns = target.storedColumns;
  final moved = [
    for (final row in slide.tableRows.skip(1))
      [for (final column in newColumns) _cellFor(row, oldColumns, column.key)],
  ];
  return [
    matrixHeaderRow(target),
    if (moved.isEmpty) List<String>.filled(newColumns.length, '') else ...moved,
  ];
}

/// De cel van [row] die bij kolomsleutel [key] hoorde, of leeg.
String _cellFor(List<String> row, List<MatrixColumn> from, String key) {
  final i = from.indexWhere((c) => c.key == key);
  return i < 0 || i >= row.length ? '' : row[i];
}

/// [row] op precies [length] cellen: te kort wordt aangevuld, te lang afgekapt.
///
/// Een handgeschreven `.md` hoeft niet net te zijn, en de rekenkant leest op
/// index. Zonder deze normalisatie zou een rij met één cel te weinig een
/// RangeError geven op het openen van het deck — en dan gaat het hele bestand
/// niet open in plaats van één scheve rij.
List<String> _fitRow(List<String> row, int length) => [
  for (var i = 0; i < length; i++) i < row.length ? row[i] : '',
];

/// Een kolomsleutel uit een vrije kop: kleine letters, woorden met liggende
/// streepjes. Alleen voor de terugval bij een onbekend sjabloon.
String _keyFor(String label) => label
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
    .replaceAll(RegExp(r'^-+|-+$'), '');
