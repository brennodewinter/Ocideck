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
///   losse regel niet onder een half doorgesneden tabel plakt;
/// * een blok waarvan de index in [forcedBreakBefore] staat begint áltijd op
///   een verse pagina, hoeveel ruimte er ook over was;
/// * een blok in [keepWithNext] — een kop — blijft niet alleen onderaan een
///   vel achter: past er onder de kop niet minstens [minKeepHeight] aan inhoud
///   op hetzelfde vel, dan schuift de kop mee naar de volgende pagina;
/// * en een blok met [reservedRoom] eist bovenop zijn eigen hoogte nog ruimte
///   op het vel die niet in de tekststroom zit: de voetnoten die vanuit dat
///   blok worden aangehaald en onderaan de bladzijde komen te staan.
///
/// Dat vierde is geen luxe maar het formaat: een `---` in de body ís een
/// pagina-einde, en de instelling "nieuw hoofdstuk op een nieuwe pagina" doet
/// hetzelfde voor elke `H1` (FILE_FORMAT.md §14.6). De HTML- en LaTeX-export
/// honoreren die allebei; deed de weergave dat niet, dan zou het scherm iets
/// anders zeggen dan de druk.
///
/// Het vijfde is er voor de lezer: een kop onderaan een bladzijde met de tekst
/// die erbij hoort op de volgende belooft iets wat er niet staat, en één losse
/// regel onder die kop leest niet veel beter. LaTeX doet dit uit zichzelf, de
/// browser doet het met `break-after: avoid`, en deze weergave dus hier.
///
/// Het zesde is de voetnoot. De gereserveerde ruimte hoort bij het blok dat de
/// noot aanhaalt en niet bij de pagina, en dat is precies wat het klopjes
/// maakt: schuift dat blok naar het volgende vel, dan schuift de noot mee en
/// komt de ruimte hier weer vrij. Een aanpak die per pagina reserveert moet
/// daarvoor net zo lang heen en weer rekenen tot het stil ligt.
List<double> documentPageOffsets({
  required List<double> blockHeights,
  required double pageHeight,
  Set<int> forcedBreakBefore = const {},
  Set<int> keepWithNext = const {},
  double minKeepHeight = 0,
  List<double> reservedRoom = const [],
}) {
  if (pageHeight <= 0) return const [0];
  double reservedFor(int index) =>
      index < reservedRoom.length ? reservedRoom[index] : 0;
  final offsets = <double>[0];
  var pageTop = 0.0;
  var y = 0.0;
  // Wat er op dit vel al is weggelegd voor de voetnoten van de blokken die er
  // staan. Gaat van de bruikbare hoogte af, en begint bij elk vers vel op nul.
  var reserved = 0.0;
  // Of er sinds de bovenkant van dit vel nog niets anders staat dan koppen.
  // Twee regels hangen eraan: een te hoog blok mag dan onder die kop aanschuiven
  // in plaats van een vers vel te eisen (anders staat de kop gegarandeerd
  // alleen), en een volgende kop schuift dan niet nog eens door — dat zou de
  // eerste alsnog alleen achterlaten.
  var pageHoldsOnlyKeepBlocks = true;

  void startPage() {
    pageTop = y;
    offsets.add(pageTop);
    pageHoldsOnlyKeepBlocks = true;
    reserved = 0;
  }

  for (var index = 0; index < blockHeights.length; index++) {
    final height = blockHeights[index];
    // Een geforceerd einde telt alleen wanneer er al iets op het vel staat:
    // een breuk bovenaan een verse pagina zou een leeg vel opleveren.
    if (forcedBreakBefore.contains(index) && y > pageTop) {
      startPage();
    } else if (minKeepHeight > 0 &&
        keepWithNext.contains(index) &&
        y > pageTop &&
        !pageHoldsOnlyKeepBlocks &&
        _leadBelowKeepBlock(
              blockHeights: blockHeights,
              index: index,
              y: y,
              pageTop: pageTop,
              pageHeight: pageHeight,
              forcedBreakBefore: forcedBreakBefore,
              keepWithNext: keepWithNext,
              limit: minKeepHeight,
              reservedFor: reservedFor,
              reserved: reserved,
            ) <
            minKeepHeight) {
      startPage();
    }
    if (height + reservedFor(index) > pageHeight) {
      // Past op geen enkele pagina: verse pagina, en dan zoveel vensters als
      // het blok hoog is. Staat er alleen een kop boven, dan schuift het blok
      // daaronder aan — een vers vel eisen zou die kop juist achterlaten.
      if (y > pageTop && !pageHoldsOnlyKeepBlocks) startPage();
      var top = pageTop + pageHeight;
      while (top < y + height) {
        offsets.add(top);
        pageTop = top;
        top += pageHeight;
      }
      y += height;
      // Het volgende blok begint vers; het laatste venster van dit blok is al
      // vergeven. Alleen een nieuwe pagina openen als er nog iets komt — dat
      // weten we hier nog niet, dus dat doet de volgende ronde (of niemand).
      pageTop = y;
      pageHoldsOnlyKeepBlocks = true;
      continue;
    }
    if (y + height > pageTop + pageHeight - reserved - reservedFor(index)) {
      // Past niet meer op deze pagina: in zijn geheel doorschuiven.
      startPage();
    } else if (offsets.last < pageTop) {
      offsets.add(pageTop);
    }
    y += height;
    reserved += reservedFor(index);
    pageHoldsOnlyKeepBlocks =
        pageHoldsOnlyKeepBlocks && keepWithNext.contains(index);
  }
  return offsets;
}

/// Hoeveel inhoud er onder de kop op [index] nog op ditzelfde vel terechtkomt,
/// afgekapt op [limit] — meer hoeft de aanroeper niet te weten.
///
/// Een kop die direct door een volgende kop wordt gevolgd telt als één groep:
/// de tekst onder de laatste kop is de inhoud die de hele groep vasthoudt.
/// Nul betekent: de kop zou hier alleen achterblijven.
double _leadBelowKeepBlock({
  required List<double> blockHeights,
  required int index,
  required double y,
  required double pageTop,
  required double pageHeight,
  required Set<int> forcedBreakBefore,
  required Set<int> keepWithNext,
  required double limit,
  required double Function(int) reservedFor,
  required double reserved,
}) {
  var pageBottom = pageTop + pageHeight - reserved;
  var cursor = y;
  var i = index;
  while (i < blockHeights.length && keepWithNext.contains(i)) {
    // Een geforceerd einde middenin de groep knipt hem door; wat erachter komt
    // staat op het volgende vel en houdt deze kop dus niet vast.
    if (i > index && forcedBreakBefore.contains(i)) return 0;
    pageBottom -= reservedFor(i);
    if (cursor + blockHeights[i] > pageBottom) return 0;
    cursor += blockHeights[i];
    i++;
  }
  var lead = 0.0;
  while (i < blockHeights.length && lead < limit) {
    if (forcedBreakBefore.contains(i)) break;
    final height = blockHeights[i];
    if (height > pageHeight) {
      // Een te hoog blok begint zelf een vers vel, tenzij er boven de kop niets
      // anders staat — dan schuift het aan en is het juist dát blok dat de kop
      // gezelschap houdt.
      if (lead == 0 && y <= pageTop) {
        return math.min(pageBottom - cursor, limit);
      }
      break;
    }
    pageBottom -= reservedFor(i);
    if (cursor + height > pageBottom) break;
    cursor += height;
    lead += height;
    i++;
  }
  return lead;
}

/// Het aantal pagina's dat [documentPageOffsets] oplevert — voor wie alleen wil
/// weten hoe dik het wordt.
int documentPageCount({
  required List<double> blockHeights,
  required double pageHeight,
  Set<int> forcedBreakBefore = const {},
  Set<int> keepWithNext = const {},
  double minKeepHeight = 0,
  List<double> reservedRoom = const [],
}) => documentPageOffsets(
  blockHeights: blockHeights,
  pageHeight: pageHeight,
  forcedBreakBefore: forcedBreakBefore,
  keepWithNext: keepWithNext,
  minKeepHeight: minKeepHeight,
  reservedRoom: reservedRoom,
).length;
