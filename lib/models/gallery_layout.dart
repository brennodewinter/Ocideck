/// De lay-out van een `imageGallery`-dia (#2838): een **raster** (alle
/// afbeeldingen naast elkaar zichtbaar) of een **stapel** (over elkaar heen,
/// per klik één afbeelding erbij — zoals krantenkoppen die je op de dia laat
/// neervallen).
///
/// De keuze reist als `_class`-subtoken mee (`gallery-stack`), zoals de
/// tijdlijn zijn varianten in `timeline-steps`/`timeline-static` draagt:
/// een vreemde lezer negeert het token straffeloos, de `![](…)`-lijst eronder
/// blijft in elke Markdown-lezer gewoon zichtbaar.
enum GalleryLayout {
  /// Alle afbeeldingen als raster/rij naast elkaar. Geen stappen.
  grid,

  /// Afbeeldingen over elkaar heen met kleine verschuiving en draaiing
  /// (deterministisch uit het dia-id). In de presentatie onthult elke klik
  /// er één; de eerste staat er meteen, zodat de dia nooit leeg opent.
  stack,
}

/// De class-tokens die dit type schrijft naast zijn basistoken `gallery`.
/// `grid` is de stille standaard en schrijft niets weg — de kortste
/// weergave in het bestand, zoals `timeline` zonder subtoken `auto` betekent.
List<String> galleryClassTokens(GalleryLayout layout) => [
  if (layout == GalleryLayout.stack) 'gallery-stack',
];

/// Alle optietokens die dit type begrijpt (voor class-filtering en de
/// validator-allowlist). Omvat bewust niet het basistoken `gallery`.
const Set<String> galleryOptionTokens = {'gallery-stack'};

bool isGalleryOptionToken(String token) => galleryOptionTokens.contains(token);

/// Leest de lay-out uit de class-tokens. `gallery-stack` = stapel; al het
/// andere (inclusief geen token) is het raster — de stille standaard.
GalleryLayout galleryLayoutFromTokens(Iterable<String> tokens) =>
    tokens.contains('gallery-stack') ? GalleryLayout.stack : GalleryLayout.grid;
