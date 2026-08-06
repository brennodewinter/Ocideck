/// Splitsing van lange tabellen over meerdere dias — headless, zonder Flutter.
///
/// Het patroon volgt [splitBulletSlidePages]: de oorspronkelijke slide wordt
/// vervangen door een lijst slides, elk met een subset van de rijen. De koprij
/// herhaalt op elke pagina. Het aantal rijen per pagina is een leesbaarheids-
/// drempel, geen pixelmeting — de renderlaag schrapt het lettertype al terug
/// wanneer een pagina te vol is.
library;

import '../models/slide.dart';

/// Drempel: zoveel data-rijen (exclusief kop) passen leesbaar op één dia.
/// Boven dit aantal suggereert de quality-warning een split.
const int kTableRowsPerPage = 12;

/// Splits een tabel-slide in meerdere slides, elk met [kTableRowsPerPage]
/// data-rijen. De koprij herhaalt op elke pagina. Geeft `null` terug als de
/// tabel te weinig rijen heeft om te splitsen (≤ 1 data-rij of ≤ drempel).
///
/// De eerste slide erft de oorspronkelijke slide (met alle metadata);
/// vervolgslides zijn duplicaten met `continuesSplit: true`, net als bij
/// bullet-splitsing.
List<Slide>? splitTableSlidePages(Slide slide, {int? rowsPerPage}) {
  if (slide.type != SlideType.table) return null;
  final rows = slide.tableRows.where((r) => r.isNotEmpty).toList();
  if (rows.length < 2) return null; // alleen een kop — niets te splitsen
  final header = rows.first;
  final body = rows.sublist(1);
  final perPage = rowsPerPage ?? kTableRowsPerPage;
  if (body.length <= perPage) return null; // past op één dia

  List<Slide> build(List<List<List<String>>> pages) => [
    for (var i = 0; i < pages.length; i++)
      (i == 0 ? slide : Slide.duplicate(slide)).copyWith(
        tableRows: pages[i],
        continuesSplit: i == 0 ? slide.continuesSplit : true,
      ),
  ];

  final pages = <List<List<String>>>[];
  for (var i = 0; i < body.length; i += perPage) {
    final chunk = body.sublist(
      i,
      i + perPage > body.length ? null : i + perPage,
    );
    pages.add([header, ...chunk]);
  }
  return build(pages);
}
