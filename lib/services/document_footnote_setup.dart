import '../utils/document_front_matter.dart';

/// Waar de voetnoten van een document terechtkomen.
enum FootnotePlacement {
  /// Onderaan de bladzijde waar de verwijzing staat — wat een voetnoot is. De
  /// standaard, en de enige stand die niets in het bestand schrijft.
  page,

  /// Achterin het document, als genummerde lijst. Noten die eerder toelichting
  /// zijn dan bronvermelding lezen zo prettiger, en een lange noot hoeft dan
  /// niet te vechten om de onderkant van het vel.
  document,
}

/// De front-mattersleutel waarin de keuze staat.
///
/// `reference-location:` is geen eigen vinding: Pandoc en Quarto voeren hem
/// uit, met precies deze betekenis (`document` = alles achterin). Daarmee
/// blijft de belofte van FILE_FORMAT.md §14.1 heel — OciDeck schrijft geen
/// sleutel die alleen binnen OciDeck iets doet. De prijs is dat de andere kant
/// van de keuze geen sleutel héét: "onderaan de pagina" is wat Pandoc en LaTeX
/// zonder enige aanwijzing al doen, en dus schrijft OciDeck er niets voor. Dat
/// is precies goed — een document dat niets bijzonders wil, blijft een `.md`
/// zonder front matter.
const String kFootnotePlacementKey = 'reference-location';

/// Waar de voetnoten van [source] horen te komen.
///
/// Alleen de waarde `document` betekent achterin. Pandoc kent daarnaast
/// `section` en `block` (noten per hoofdstuk of per blok), maar OciDeck voert
/// die plaatsing niet uit — ze stil als `document` (alles achterin) lezen gaf
/// een ander resultaat dan de ontvanger met Pandoc (#1678). Terugvallen op
/// `page` (noten op de pagina) is veiliger: dat staat dichter bij per-sectie
/// dan alles achterin, en het is wat elke lezer zonder aanwijzing al doet.
/// Een onbekende waarde valt eveneens terug op `page`.
FootnotePlacement documentFootnotePlacement(String source) =>
    switch (documentFrontMatterValue(source, kFootnotePlacementKey)?.trim()) {
      'document' => FootnotePlacement.document,
      _ => FootnotePlacement.page,
    };

/// [source] met de plaatsing gezet. [FootnotePlacement.page] wist de sleutel —
/// terug naar het gedrag dat elke lezer zonder aanwijzing al vertoont, en naar
/// een bestand dat er niets over zegt.
String withDocumentFootnotePlacement(
  String source,
  FootnotePlacement placement,
) => withDocumentFrontMatterKey(
  source,
  kFootnotePlacementKey,
  placement == FootnotePlacement.document ? 'document' : null,
);
