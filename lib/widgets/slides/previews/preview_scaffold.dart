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
  });

  @override
  Widget build(BuildContext context) {
    final safe = slide.showLogo
        ? _logoSafeInsets(width, profile)
        : EdgeInsets.zero;

    return Container(
      color: Colors.white,
      child: SizedBox.expand(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                verticalPadding + safe.top,
                horizontalPadding,
                _logoAwareBottomPadding(verticalPadding, safe.bottom),
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
    );
  }
}
