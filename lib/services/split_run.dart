import '../models/settings.dart';
import '../models/slide.dart';
import 'rich_text_layout.dart';
import 'slide_layout_metrics.dart';

/// De *split-run*: de groep opeenvolgende bulletslides die samen één gesplitste
/// lijst vormen en daarom op één gedeelde tekstgrootte renderen.
///
/// Puur rekenwerk over een slidelijst, zonder thema of layout, zodat zowel de
/// preview (die de gedeelde schaal toepast) als de kwaliteitsanalyse (die
/// meldt wanneer die schaal een slide onnodig klein maakt) dezelfde definitie
/// van een run gebruiken.

/// Een run bestaat uit hooguit één pagina die de rest meetrekt; een pagina die
/// los minstens [kSplitRunDragRatio]× groter zou renderen dan de gedeelde
/// schaal, is geen legitieme deelgenoot van dezelfde lijst maar een slide die
/// per ongeluk aan de reeks vastzit. Twee keer zo groot is een zichtbaar
/// verschil dat geen enkele echte splitsing oplevert: pagina's van dezelfde
/// gesplitste lijst dragen vergelijkbare hoeveelheden tekst.
const double kSplitRunDragRatio = 2.0;

/// Of [type] überhaupt in een split-run kan zitten.
bool isSplitRunType(SlideType type) =>
    type == SlideType.bullets ||
    type == SlideType.twoBullets ||
    type == SlideType.bulletsImage;

/// De grenzen `(start, eind)` van de split-run waar de slide op [index] in zit,
/// beide inclusief. Een slide die geen deel van een reeks is levert
/// `(index, index)` — de aanroeper leest dat als "geen run".
///
/// Een run is een maximale groep slides van hetzelfde type en dezelfde
/// liststyle waarbij elke pagina ná de eerste [Slide.continuesSplit] draagt.
(int, int) splitRunRange(List<Slide> slides, int index) {
  if (index < 0 || index >= slides.length) return (index, index);
  if (!isSplitRunType(slides[index].type)) return (index, index);
  bool sameRun(Slide a, Slide b) =>
      a.type == b.type && a.listStyle == b.listStyle;

  var start = index;
  while (start > 0 &&
      slides[start].continuesSplit &&
      sameRun(slides[start - 1], slides[start])) {
    start--;
  }
  var end = index;
  while (end + 1 < slides.length &&
      slides[end + 1].continuesSplit &&
      sameRun(slides[end], slides[end + 1])) {
    end++;
  }
  return (start, end);
}

/// Welke pagina's van een run onnodig klein renderen, gegeven de schaal die elke
/// pagina op zichzelf zou halen ([scales], in runvolgorde).
///
/// De gedeelde schaal is het minimum: de volste pagina bepaalt de grootte van
/// alle andere. Dat is precies de bedoeling zolang de pagina's uit dezelfde
/// lijst komen, maar zodra één pagina veel voller is dan de rest is zij geen
/// deelgenoot meer maar een sta-in-de-weg. `offender` is die pagina, `dragged`
/// zijn de pagina's die er onnodig door krimpen — beide als index in [scales].
///
/// `null` wanneer er niets te melden valt: een run van één, een run die ruim
/// past (boven [warningScale] is de verkleining niet storend), of een run
/// waarin geen enkele pagina los minstens [ratio]× groter zou zijn.
({int offender, List<int> dragged})? splitRunDrag(
  List<double> scales, {
  required double warningScale,
  double ratio = kSplitRunDragRatio,
}) {
  if (scales.length < 2) return null;

  var offender = 0;
  for (var i = 1; i < scales.length; i++) {
    if (scales[i] < scales[offender]) offender = i;
  }
  final shared = scales[offender];
  // Een reeks die toch al comfortabel rendert heeft geen probleem om te melden.
  if (shared > warningScale) return null;

  final dragged = <int>[
    for (var i = 0; i < scales.length; i++)
      if (i != offender && scales[i] >= shared * ratio) i,
  ];
  return dragged.isEmpty ? null : (offender: offender, dragged: dragged);
}

/// De ene lettergrootte waarop elke pagina van de run rond [index] rendert, of
/// `null` als deze slide geen deel van een reeks van meerdere pagina's is.
///
/// Het minimum over de run — de volste pagina — zodat een lijst die over
/// pagina's is verdeeld overal even groot staat in plaats van per pagina uit te
/// dijen. Aanroepers die het hele deck vasthouden (previews, presentatiemodus,
/// publieksvenster, export) geven de uitkomst door als
/// `SlidePreviewWidget.fitScaleOverride`.
double? sharedSplitFitScale(
  List<Slide> slides,
  int index,
  ThemeProfile profile,
  String font,
) {
  final (start, end) = splitRunRange(slides, index);
  if (start == end) return null; // één pagina — niets te delen

  var minScale = double.infinity;
  for (var i = start; i <= end; i++) {
    final s = splitRunMemberScale(slides[i], profile, font);
    if (s < minScale) minScale = s;
  }
  return minScale.isFinite ? minScale : null;
}

/// De schaal waarop één pagina van een run zijn tekst rendert, op
/// referentiebreedte en met de logostrook gereserveerd — net als de live layout.
///
/// Ook de maatstaf waartegen de kwaliteitscontrole afmeet of een pagina door
/// zijn reeks wordt meegetrokken. Dezelfde functie voor beide, zodat een
/// gemelde grootte de grootte is die je ziet.
double splitRunMemberScale(Slide slide, ThemeProfile profile, String font) {
  // De smalle tekstkolom van een split-slide staat naast het beeld en volgt
  // daarom een eigen logoregel.
  final (top, bottom) = slide.showLogo
      ? logoSafeReserveEdges(
          kReferenceSlideWidth,
          profile,
          splitText: slide.type == SlideType.bulletsImage,
        )
      : (0.0, 0.0);
  final vReserve = top + bottom;
  return switch (slide.type) {
    SlideType.bulletsImage => bulletsImageSlideFitScale(
      slide: slide,
      font: font,
      extraVReserve: vReserve,
    ),
    SlideType.twoBullets => twoBulletsSlideFitScale(
      slide: slide,
      font: font,
      extraVReserve: vReserve,
    ),
    _ => bulletsSlideFitScale(
      slide: slide,
      font: font,
      extraVReserve: vReserve,
    ),
  };
}
