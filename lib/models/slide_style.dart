import 'settings.dart';
import 'slide.dart';

/// De stijlwissel (#2996): welk [ThemeProfile] op welke dia geldt.
///
/// Het deck heeft één deckstijl; een dia kan een markering dragen
/// (`Slide.styleName`, in het `.md` een `<!-- ocideck_style: … -->`-commentaar)
/// die *vanaf die dia* geldt, tot een volgende markering. Alles wat een dia
/// tekent — editor, miniatuur, presentator, publieksscherm, export — gebruikt
/// deze resolutie in plaats van `deck.themeProfile`, zodat de wissel overal
/// hetzelfde valt.

/// De gereserveerde markering voor "terug naar de deckstijl".
const kDeckStyleToken = 'deck';

/// De naam van de stijl die op dia [index] geldt, of `null` voor de deckstijl.
///
/// De laatste markering tot en met [index] wint. `deck` betekent: hier loopt
/// geen bereik meer — dat is een effectief resultaat van `null`, net als een
/// deck zonder markeringen. De ruwe naam blijft bewust beschikbaar (en niet
/// alleen een opgelost profiel): de interface toont wat de gebruiker instelde,
/// ook als dat profiel hier niet bestaat.
String? slideStyleNameAt(List<Slide> slides, int index) {
  String? active;
  for (var i = 0; i <= index && i < slides.length; i++) {
    final marker = slides[i].styleName;
    if (marker.isEmpty) continue;
    active = marker == kDeckStyleToken ? null : marker;
  }
  return active;
}

/// De dia-index waar de markering staat die op [index] geldt, of `null` als de
/// deckstijl geldt — voor de erf-herkomst in de interface ("vanaf dia N").
/// Een `deck`-markering telt niet: die beëindigt een bereik, hij opent er geen.
int? slideStyleMarkerIndex(List<Slide> slides, int index) {
  int? active;
  for (var i = 0; i <= index && i < slides.length; i++) {
    final marker = slides[i].styleName;
    if (marker.isEmpty) continue;
    active = marker == kDeckStyleToken ? null : i;
  }
  return active;
}

/// Vervangt de markeringen vanaf [index] voor één doorlopend stijlbereik.
/// Geeft null terug voor een ongeldige index of ongewijzigde markeringen.
List<Slide>? slidesWithStyleFrom(
  List<Slide> slides,
  int index,
  String styleName,
) {
  if (index < 0 || index >= slides.length) return null;
  final inherited = slideStyleNameAt(slides, index - 1) ?? kDeckStyleToken;
  final marker = styleName == inherited ? '' : styleName;
  List<Slide>? result;
  for (var i = index; i < slides.length; i++) {
    final slide = slides[i];
    final newMarker = i == index ? marker : '';
    if (slide.styleName == newMarker) continue;
    (result ??= List<Slide>.of(slides))[i] = slide.copyWith(
      styleName: newMarker,
    );
  }
  return result;
}

/// Alle profielnamen waar een markering naar wijst — de set waarvoor exports
/// stijlregels moeten meenemen. `deck` telt niet: dat is géén profiel.
Set<String> usedSlideStyleNames(List<Slide> slides) => {
  for (final slide in slides)
    if (slide.styleName.isNotEmpty && slide.styleName != kDeckStyleToken)
      slide.styleName,
};

/// Het profiel dat op dia [index] gerenderd wordt: de actieve markering,
/// opgelost in [profiles]; de deckstijl [base] als er geen markering loopt of
/// de naam geen bekend profiel raakt — een gemist profiel breekt het deck
/// nooit, het degradeert naar de standaard.
ThemeProfile resolveSlideStyle(
  ThemeProfile base,
  List<ThemeProfile> profiles,
  List<Slide> slides,
  int index,
) {
  final name = slideStyleNameAt(slides, index);
  if (name == null) return base;
  for (final profile in profiles) {
    if (profile.name == name) return profile;
  }
  return base;
}

/// Het class-token waarmee de wissel in gegenereerde uitvoer reist: HTML en de
/// pakket-thema-CSS scopen hun regels op `section.<token>`, en de pakket-
/// markdown schrijft het token mee in de `_class` van elke dia in het bereik.
///
/// De profielnaam is vrije tekst, dus hij gaat door een slug — net als
/// `_safeThemeName` voor de thema-naam. Niet omgekeerd bepaald: de naam zelf
/// staat in de markering, de slug is alleen afgeleide presentatie.
String slideStyleClassToken(String profileName) {
  final slug = profileName
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return 'stijl-${slug.isEmpty ? 'x' : slug}';
}
