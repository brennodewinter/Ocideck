// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// De buitenste stellage die de inhoudspreviews delen: een vlak in
/// [background], met de inhoud opgemaakt op de vaste slidebreedte [width] en
/// als geheel omlaaggeschaald zodra ze niet past.
///
/// Waarom een eigen widget: dezelfde zeven lagen — vlak, `SizedBox.expand`,
/// omlaagschalende `FittedBox`, vaste breedte, logo-bewuste marge, kolom —
/// stonden in acht previews letterlijk uitgeschreven. Een wijziging aan de
/// stellage moest dus acht keer worden nagelopen, en één overgeslagen bestand
/// week daarna stil af.
///
/// Bewust *niet* hierheen gehaald zijn de previews die wezenlijk anders zijn
/// opgebouwd: grafiek en cockpit rekenen hun eigen beeldverhouding uit, de
/// tabelpreview laat de `SizedBox.expand` weg, en de scorecard geeft de box
/// een vaste hoogte zodat de kaarten de resthoogte kunnen claimen. Die er met
/// schakelaars alsnog in persen levert één widget met tien standen op — wat
/// dezelfde kwaal is in een andere vorm.
class _PreviewScaffold extends StatelessWidget {
  /// De breedte waarop de inhoud wordt opgemaakt. Schalen doet de `FittedBox`,
  /// niet het lettertype, zodat de typografie in elke miniatuurgrootte
  /// dezelfde verhoudingen houdt.
  final double width;

  /// Bepaalt samen met [profile] hoeveel ruimte het logo boven- en onderaan
  /// opeist; zonder `showLogo` is dat niets.
  final Slide slide;
  final ThemeProfile profile;

  /// Zijmarge, links en rechts gelijk.
  final double horizontalPadding;

  /// Boven- en ondermarge vóór de logo-correctie.
  final double verticalPadding;

  /// De vlakvulling. Standaard wit: de rapportageslides houden dat aan
  /// ongeacht het thema, omdat ze als document gelezen worden. De previews die
  /// wél de themakleur volgen geven hem hier mee.
  final Color background;

  /// De inhoud van de kolom. De kolom zelf — links uitgelijnd, hoogte naar de
  /// inhoud — hoort bij de stellage, want daarop rekent de `FittedBox`.
  final List<Widget> children;

  const _PreviewScaffold({
    required this.width,
    required this.slide,
    required this.profile,
    required this.horizontalPadding,
    required this.verticalPadding,
    required this.children,
    this.background = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    // Panel slides (chart, code, table, ...) have opaque content that the logo
    // can sit on top of — no vertical strip needed (#1932). Text slides keep
    // a reduced strip so the text stops above the logo.
    final isPanel = !slideUsesRichText(slide);
    final safe = slide.showLogo
        ? _logoSafeInsets(width, profile, corner: isPanel)
        : EdgeInsets.zero;

    // De logostrook reserveren we búiten de `FittedBox`, niet als padding in de
    // kolom die de box omlaagschaalt. Zat de strook binnen die kolom, dan kromp
    // hij mee zodra de inhoud te hoog werd om te passen, terwijl het logo-overlay
    // op een vaste plek blijft — en dan schoof de inhoud er alsnog onderdoor. Dat
    // trof juist de schermvullende presentatie: `Math.tex` schaalt niet lineair
    // met de lettergrootte (breukstrepen en `\left(\right)`-delimiters springen in
    // discrete maten), dus bij de grote maat ging een formule net over de grens
    // die bij de kleine preview nog paste. Buiten de box is de strook vast, en
    // blijft de inhoud er schaalonafhankelijk boven — preview en presentatie
    // gelijk (#931).
    //
    // De binnenmarges houden de oorspronkelijke totale ruimte aan: de bovenmarge
    // was `verticalPadding + safe.top` (nu: `safe.top` buiten + `verticalPadding`
    // binnen), de ondermarge `max(verticalPadding, safe.bottom)` (nu: `safe.bottom`
    // buiten + de rest binnen). Voor inhoud die toch al past verandert er niets.
    final innerBottom = math.max(
      0.0,
      _logoAwareBottomPadding(verticalPadding, safe.bottom) - safe.bottom,
    );

    return Container(
      color: background,
      child: Padding(
        padding: EdgeInsets.only(top: safe.top, bottom: safe.bottom),
        child: SizedBox.expand(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  horizontalPadding,
                  verticalPadding,
                  horizontalPadding,
                  innerBottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: children,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// De logo-vrije zone als insets, gedeeld door alle previews die een logo
/// ontwijken (bullets, chart, code, cockpit). Hier omdat de scaffold al de
/// logo-bewuste marge kent; `slide_preview.dart` zit op zijn regelplafond.
EdgeInsets _logoSafeInsets(
  double w,
  ThemeProfile profile, {
  bool corner = false,
}) {
  final (top, bottom) = logoSafeReserveEdges(w, profile, corner: corner);
  return EdgeInsets.only(top: top, bottom: bottom);
}

double _logoAwareBottomPadding(double defaultPad, double safeBottom) =>
    safeBottom <= 0 ? defaultPad : math.max(defaultPad, safeBottom);
