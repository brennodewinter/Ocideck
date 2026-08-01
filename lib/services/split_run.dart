import '../models/settings.dart';
import '../models/slide.dart';
import '../utils/lru_cache.dart';
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

/// Of de slide op [index] een voortzetting van zijn voorganger *kan* zijn: er is
/// een vorige slide, en die vormt met deze een reeks (zelfde type, zelfde
/// liststyle). Zegt niets over of de vlag aan staat — dit is de vraag of het
/// aanbieden van die keuze zinnig is.
///
/// Zelfde regel als [splitRunRange] gebruikt om een reeks af te bakenen, zodat
/// de schakelaar in de editor niet iets anders belooft dan de opmaak doet.
bool canContinueSplitFrom(List<Slide> slides, int index) {
  if (index <= 0 || index >= slides.length) return false;
  final slide = slides[index];
  final previous = slides[index - 1];
  return isSplitRunType(slide.type) &&
      previous.type == slide.type &&
      previous.listStyle == slide.listStyle;
}

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
  return splitRunLayoutIndex(slides, profile, font).fitScaleFor(index);
}

/// De voor één deck-/thema-/lettertyperevisie voorberekende split-runlayout.
///
/// Zowel de grenzen als de gedeelde minimumschaal staan per slide klaar. Een
/// thumbnail, presenter-rebuild of exportlus doet daardoor alleen nog een
/// indexlookup; het deck wordt niet opnieuw doorlopen en geen runlid wordt
/// opnieuw met TextPainter gemeten.
class SplitRunLayoutIndex {
  final List<(int, int)> _ranges;
  final List<double?> _fitScales;

  const SplitRunLayoutIndex._(this._ranges, this._fitScales);

  (int, int) rangeFor(int index) =>
      index < 0 || index >= _ranges.length ? (index, index) : _ranges[index];

  double? fitScaleFor(int index) =>
      index < 0 || index >= _fitScales.length ? null : _fitScales[index];
}

class _SplitRunLayoutMemo {
  final indexes = LruCache<(ThemeProfile, String), SplitRunLayoutIndex>(8);
}

/// Zwak gekoppeld aan de slidelijst: normale deckbewerkingen leveren een verse
/// lijst en dus vanzelf een verse revisie, terwijl een oude deckrevisie samen
/// met haar cache kan worden opgeruimd. [ThemeProfile] is immutable en wordt op
/// identiteit vergeleken; een themawijziging levert een nieuw profiel. [font]
/// staat apart in de sleutel, ook wanneer een aanroeper een override gebruikt.
/// Per slidelijst blijven de acht recentste combinaties warm, zodat een undo of
/// terugkeer uit de themavoorvertoning niet meteen alle tekst opnieuw meet en
/// langdurig thema uitproberen de cache tegelijk niet onbegrensd laat groeien.
final Expando<_SplitRunLayoutMemo> _splitRunLayoutCache =
    Expando<_SplitRunLayoutMemo>('splitRunLayout');

/// Geeft de gedeelde, voorberekende index voor deze deck-/themarevisie.
SplitRunLayoutIndex splitRunLayoutIndex(
  List<Slide> slides,
  ThemeProfile profile,
  String font,
) {
  final memo = _splitRunLayoutCache[slides] ?? _SplitRunLayoutMemo();
  _splitRunLayoutCache[slides] = memo;
  final key = (profile, font);
  final cached = memo.indexes[key];
  if (cached != null) return cached;
  final index = buildSplitRunLayoutIndex(slides, profile, font);
  memo.indexes[key] = index;
  return index;
}

/// Vergeet de index na een zeldzame in-place wijziging van [slides].
///
/// Deckbewerkingen in de editor vervangen de lijst en hoeven dit niet aan te
/// roepen. De live presentator en het publieksvenster houden om sessieredenen
/// dezelfde lijst vast en roepen dit direct na hun in-place wijziging aan.
void invalidateSplitRunLayout(List<Slide> slides) {
  _splitRunLayoutCache[slides] = null;
}

/// Bouwt grenzen en gedeelde schalen in één lineaire gang door [slides].
///
/// [measureMember] is injecteerbaar zodat de prestatietest het exacte aantal
/// dure lidmetingen kan bewaken zonder op wandkloktijden te vertrouwen.
SplitRunLayoutIndex buildSplitRunLayoutIndex(
  List<Slide> slides,
  ThemeProfile profile,
  String font, {
  double Function(Slide slide, ThemeProfile profile, String font)?
  measureMember,
}) {
  final ranges = <(int, int)>[for (var i = 0; i < slides.length; i++) (i, i)];
  final fitScales = List<double?>.filled(slides.length, null);
  final measure = measureMember ?? splitRunMemberScale;

  var start = 0;
  while (start < slides.length) {
    final first = slides[start];
    if (!isSplitRunType(first.type)) {
      start++;
      continue;
    }

    var end = start;
    while (end + 1 < slides.length) {
      final next = slides[end + 1];
      if (!next.continuesSplit ||
          next.type != slides[end].type ||
          next.listStyle != slides[end].listStyle) {
        break;
      }
      end++;
    }

    if (end > start) {
      var shared = double.infinity;
      for (var i = start; i <= end; i++) {
        ranges[i] = (start, end);
        final own = measure(slides[i], profile, font);
        if (own < shared) shared = own;
      }
      if (shared.isFinite) {
        for (var i = start; i <= end; i++) {
          fitScales[i] = shared;
        }
      }
    }
    start = end + 1;
  }

  return SplitRunLayoutIndex._(ranges, fitScales);
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
