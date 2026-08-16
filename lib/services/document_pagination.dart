import 'dart:math' as math;

/// Verdeelt een doorlopend document over pagina's.
///
/// De invoer is de gemeten hoogte van elk blok — niet een schatting. Een
/// vuistregel die voorspelt hoe hoog een alinea wordt, rot stil weg zodra het
/// lettertype, de tekstgrootte of de regelafstand verandert; een pagina-einde
/// dat er een halve regel naast zit valt meteen op. De aanroeper laat de
/// blokken dus eerst écht renderen en geeft de uitkomst hier door.
///
/// De uitvoer is de lijst met verticale posities waar elke pagina begint, in
/// dezelfde eenheid als de hoogtes. Pagina *k* toont het venster
/// `[offsets[k], offsets[k] + pageHeight)` van het doorlopende document.
///
/// De regels:
/// * een blok wordt niet doormidden gesneden zolang het op een pagina pást —
///   het schuift dan in zijn geheel door naar de volgende;
/// * een blok dat op géén pagina past (een tabel of afbeelding die hoger is dan
///   het tekstvlak) begint op een verse pagina en loopt door over zoveel
///   pagina's als het nodig heeft. Daar is snijden onvermijdelijk;
/// * na zo'n blok begint het volgende blok weer op een verse pagina, zodat een
///   losse regel niet onder een half doorgesneden tabel plakt.
List<double> documentPageOffsets({
  required List<double> blockHeights,
  required double pageHeight,
}) {
  if (pageHeight <= 0) return const [0];
  final offsets = <double>[0];
  var pageTop = 0.0;
  var y = 0.0;

  for (final height in blockHeights) {
    if (height > pageHeight) {
      // Past op geen enkele pagina: verse pagina, en dan zoveel vensters als
      // het blok hoog is.
      if (y > pageTop) {
        pageTop = y;
        offsets.add(pageTop);
      }
      final pages = math.max(1, (height / pageHeight).ceil());
      for (var i = 1; i < pages; i++) {
        offsets.add(pageTop + pageHeight * i);
      }
      y += height;
      // Het volgende blok begint vers; het laatste venster van dit blok is al
      // vergeven.
      pageTop = y;
      // Alleen een nieuwe pagina openen als er nog iets komt — dat weten we
      // hier nog niet, dus dat doet de volgende ronde (of niemand).
      continue;
    }
    if (y + height > pageTop + pageHeight) {
      // Past niet meer op deze pagina: in zijn geheel doorschuiven.
      pageTop = y;
      offsets.add(pageTop);
    } else if (offsets.last < pageTop) {
      offsets.add(pageTop);
    }
    y += height;
  }
  return offsets;
}

/// Het aantal pagina's dat [documentPageOffsets] oplevert — voor wie alleen wil
/// weten hoe dik het wordt.
int documentPageCount({
  required List<double> blockHeights,
  required double pageHeight,
}) => documentPageOffsets(
  blockHeights: blockHeights,
  pageHeight: pageHeight,
).length;
