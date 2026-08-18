// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
//
// De drie indelingen van een keuze-menudia (#1162) en de kaart die ze delen.
// Gescheiden van `menu_preview.dart` zodat beide bestanden onder het
// bestandsplafond blijven en de vormen naast elkaar te lezen zijn.
part of '../slide_preview.dart';

/// Het blokkenvlak in de gekozen [MenuLayout]. Eén ingang voor de drie vormen,
/// zodat preview, presentator, beamer en slidestrook nooit uiteen kunnen lopen.
Widget _menuBlockArea(
  BuildContext context, {
  required List<MenuBlock> blocks,
  required MenuLayout layout,
  required double w,
  required Color text,
  required Color accent,
  required String? projectPath,
  required String font,
  required void Function(String anchor)? onBlockTap,
  required Color focusHalo,
}) {
  Widget card(MenuBlock block, {bool wide = false}) => _MenuBlockCard(
    block: block,
    w: w,
    text: text,
    accent: accent,
    focusHalo: focusHalo,
    projectPath: projectPath,
    font: font,
    onTap: onBlockTap,
    wide: wide,
  );
  return switch (layout) {
    MenuLayout.grid => _menuGrid(blocks, w, card),
    MenuLayout.list => _menuList(blocks, w, card),
    MenuLayout.circle => _MenuCircle(
      blocks: blocks,
      w: w,
      text: text,
      accent: accent,
      focusHalo: focusHalo,
      projectPath: projectPath,
      font: font,
      onTap: onBlockTap,
    ),
  };
}

/// Het telblok dat de plaats inneemt van wat niet meer leesbaar past. Een gewoon
/// blok zonder doel, met alleen het aantal erop — kort genoeg om in elke
/// indeling te passen, en zonder woorden dus in elke taal gelijk.
MenuBlock _menuMoreBlock(int hidden) => MenuBlock(label: '+$hidden');

/// De blokken die getoond worden, met het telblok er zo nodig achteraan.
List<MenuBlock> _menuWithCounter(List<MenuBlock> blocks, int fits) {
  final room = menuVisibleBlocks(blocks.length, fits);
  if (room.hidden == 0) return blocks;
  return [...blocks.take(room.shown), _menuMoreBlock(room.hidden)];
}

/// Het raster: rijen die de hoogte verdelen, kolommen naar het aantal blokken.
Widget _menuGrid(
  List<MenuBlock> blocks,
  double w,
  Widget Function(MenuBlock, {bool wide}) card,
) {
  final cols = menuGridColumns(blocks.length);
  final gap = w * 0.018;
  return LayoutBuilder(
    builder: (context, box) {
      // Zoveel rijen als er leesbaar passen; de rest wordt geteld. Zelfde
      // aftelling als bij de lijst, en om dezelfde reden.
      var fitRows = (blocks.length / cols).ceil();
      while (fitRows > 1 &&
          menuRowLabelSize(
                rowHeight: _menuRowHeight(
                  box.maxHeight,
                  gap,
                  fitRows,
                  w,
                  cap: false,
                ),
                w: w,
                hasDescription: false,
              ) <
              w * kMenuMinLabelFraction) {
        fitRows--;
      }
      final shown = _menuWithCounter(blocks, fitRows * cols);
      final n = shown.length;
      final rows = (n / cols).ceil();
      return Column(
        children: [
          for (var r = 0; r < rows; r++) ...[
            if (r > 0) SizedBox(height: gap),
            Expanded(
              child: Row(
                children: [
                  for (var c = 0; c < cols; c++) ...[
                    if (c > 0) SizedBox(width: gap),
                    Expanded(
                      child: (r * cols + c) < n
                          ? card(shown[r * cols + c])
                          : const SizedBox.shrink(),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      );
    },
  );
}

/// De prettigste hoogte van één regel in de indeling "onder elkaar", en de
/// ruimte ertussen. Passen zoveel regels niet op de dia, dan worden ze lager —
/// en krimpt de tekst mee ([_MenuBlockCard._content]) in plaats van eronder weg
/// te vallen.
const double _menuRowHeightFactor = 0.09;
const double _menuRowGapFactor = 0.012;

/// De hoogte van één regel als [n] regels met [gap] ertussen de hoogte [box]
/// verdelen — nooit hoger dan de prettige leeshoogte.
double _menuRowHeight(
  double box,
  double gap,
  int n,
  double w, {
  bool cap = true,
}) {
  final even = (box - gap * (n - 1)) / n;
  return cap ? math.min(even, w * _menuRowHeightFactor) : even;
}

/// Onder elkaar: brede kaarten, één per regel, gecentreerd in de ruimte die er
/// is. De regels verdelen de hoogte die er is; ze groeien nooit voorbij de
/// leeshoogte hierboven, want twee blokken horen geen halve dia hoog te zijn.
Widget _menuList(
  List<MenuBlock> blocks,
  double w,
  Widget Function(MenuBlock, {bool wide}) card,
) {
  final gap = w * _menuRowGapFactor;
  return LayoutBuilder(
    builder: (context, box) {
      // Zoveel regels als er op leeshoogte passen; wat overblijft wordt geteld.
      // Zonder deze grens werden zestien regels elk 11 px hoog met een letter
      // van 3,7 px — heel, en volstrekt onleesbaar (#1162, beeldkeuring).
      //
      // Aftellen en niet uitrekenen: de rijhoogte die bij een aantal hoort is
      // eenvoudig, maar de labelmaat die daar weer uit volgt loopt via marge,
      // rand en het regelbudget. Die som naschatten is precies hoe een
      // heuristiek stil uit de pas gaat lopen met wat er getekend wordt; dus
      // vragen we het de rekensom zelf, met dezelfde functie die de kaart
      // gebruikt.
      var fits = blocks.length;
      while (fits > 1 &&
          menuRowLabelSize(
                rowHeight: _menuRowHeight(box.maxHeight, gap, fits, w),
                w: w,
                hasDescription: false,
              ) <
              w * kMenuMinLabelFraction) {
        fits--;
      }
      final shown = _menuWithCounter(blocks, fits);
      final n = shown.length;
      final height = _menuRowHeight(box.maxHeight, gap, n, w);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(height: gap),
            SizedBox(height: height, child: card(shown[i], wide: true)),
          ],
        ],
      );
    },
  );
}

/// Eén keuzeblok als kaart: een kleine afbeelding links, label en uitleg
/// ernaast, en een pijl rechts als het blok ergens heen springt. De randkleur
/// onderscheidt een doelblok van een gewoon tekstblok.
///
/// Alles is begrensd op de hoogte die de kaart krijgt: in een raster van twaalf
/// is die klein, dus uitleg en pijl verdwijnen als eerste en het label breekt af
/// met een ellips. Overlopen mag nooit (#1162, beeldkeuring).
class _MenuBlockCard extends StatelessWidget {
  final MenuBlock block;
  final double w;
  final Color text;
  final Color accent;

  /// De tweede kleur van de focusring; zie [menuFocusHalo].
  final Color focusHalo;
  final String? projectPath;
  final String font;
  final void Function(String anchor)? onTap;

  /// Brede kaart (indeling "onder elkaar"): het label mag links uitlijnen en de
  /// afbeelding krijgt wat meer ruimte.
  final bool wide;

  const _MenuBlockCard({
    required this.block,
    required this.w,
    required this.text,
    required this.accent,
    required this.focusHalo,
    this.projectPath,
    required this.font,
    this.onTap,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final actionable = block.hasTarget;
    final card = Container(
      decoration: BoxDecoration(
        // Een subtiel verloop in plaats van een vlakke vulling: dat geeft de
        // kaart diepte zonder een tweede kleur uit te vinden.
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: actionable
              ? [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.06)]
              : [text.withValues(alpha: 0.07), text.withValues(alpha: 0.03)],
        ),
        border: Border.all(
          color: actionable
              ? accent.withValues(alpha: 0.55)
              : text.withValues(alpha: 0.18),
          width: w * kMenuCardBorderFraction,
        ),
        borderRadius: BorderRadius.circular(w * 0.016),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: _content),
    );
    // Aanklikbaar alleen tijdens presenteren (onTap gezet) en alleen als het blok
    // ergens heen springt (#1162). Een tekstblok of de preview in de editor blijft
    // gewoon een kaart.
    if (onTap == null || !actionable) return card;
    return _MenuFocusable(
      onActivate: () => onTap!(block.targetAnchor),
      semanticLabel: _menuSemanticLabel(block),
      ring: accent,
      halo: focusHalo,
      ringWidth: w * 0.005,
      cornerRadius: w * 0.016,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap!(block.targetAnchor),
        child: card,
      ),
    );
  }

  Widget _content(BuildContext context, BoxConstraints box) {
    // De marge krimpt mee met een lage kaart: bij zestien blokken in een lijst
    // is een vaste marge al hoger dan de kaart zelf, en dan blijft er niets voor
    // de tekst over.
    //
    // De rand hoeft hier — anders dan bij de schijf — niet apart te worden
    // afgetrokken: een `Container` met een `border` springt zijn kind al in met
    // de randdikte, dus `box.maxHeight` is hier de netto binnenmaat. De schijf
    // rekent vanaf zijn brúto doorsnede en trekt hem daarom wél zelf af.
    final pad = menuCardPadding(box.maxHeight, w);
    final inner = menuCardTextHeight(box.maxHeight, w);
    final thumb = math.min(inner, math.min(box.maxWidth * 0.3, w * 0.1));

    // Lettergrootte en regelbudget volgen uit de ruimte, niet uit een vast
    // getal; zie [menuTextFit] voor waarom dat het verschil maakt tussen
    // afbreken met een ellips en onzichtbaar weggeknipt worden.
    final fit = menuTextFit(
      available: inner,
      maxLabelSize: w * kMenuCardLabelFraction,
      hasDescription: block.hasDescription,
    );
    final showArrow = block.hasTarget && box.maxWidth > w * 0.16;

    return Padding(
      padding: EdgeInsets.all(pad),
      child: Row(
        children: [
          if (block.hasImage && thumb > w * 0.015) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(w * 0.009),
              child: SizedBox(
                width: thumb,
                height: thumb,
                child: _resolvedImage(
                  context,
                  block.imagePath,
                  projectPath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            SizedBox(width: pad),
          ],
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              // Altijd links: één kaart in een rij die zijn label centreerde
              // terwijl de buren links uitlijnden, maakte de rij rafelig.
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Flexible: bij een kleine kaart moet de tekst inbinden in
                // plaats van de kaart uit te lopen — `maxLines` alleen kapt op
                // regels, niet op de hoogte die er werkelijk is.
                Flexible(
                  child: _md(
                    context,
                    block.label,
                    _applyFont(
                      font,
                      TextStyle(
                        color: text,
                        fontSize: fit.labelSize,
                        fontWeight: FontWeight.w700,
                        height: kMenuLabelLineHeight,
                      ),
                    ),
                    linkColor: accent,
                    maxLines: fit.labelLines,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (fit.showsDescription) ...[
                  SizedBox(height: w * 0.005),
                  Flexible(
                    child: _md(
                      context,
                      block.description,
                      _applyFont(
                        font,
                        TextStyle(
                          // 0.85 en niet 0.7: op een lichte kaart met een
                          // accenttint eronder haalde 0.7 de contrastvloer van
                          // 4,5:1 niet (#1162, beeldkeuring). Kleiner en lichter
                          // van gewicht maakt de uitleg al ondergeschikt genoeg.
                          color: text.withValues(alpha: 0.85),
                          fontSize: fit.descriptionSize,
                          height: kMenuDescriptionLineHeight,
                        ),
                      ),
                      linkColor: accent,
                      maxLines: fit.descriptionLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (showArrow) ...[
            SizedBox(width: pad * 0.5),
            Icon(
              Icons.arrow_forward_rounded,
              size: math.min(w * 0.024, inner),
              color: accent.withValues(alpha: 0.8),
            ),
          ],
        ],
      ),
    );
  }
}

/// De cirkelindeling: de blokken als schijven op een ring, met een flauwe
/// cirkellijn ertussen. Alles blijft binnen de ring — een schijf is een vaste
/// maat en de tekst erin breekt af, zodat geen enkel aantal blokken de dia uit
/// kan lopen.
class _MenuCircle extends StatelessWidget {
  final List<MenuBlock> blocks;
  final double w;
  final Color text;
  final Color accent;
  final Color focusHalo;
  final String? projectPath;
  final String font;
  final void Function(String anchor)? onTap;

  const _MenuCircle({
    required this.blocks,
    required this.w,
    required this.text,
    required this.accent,
    required this.focusHalo,
    this.projectPath,
    required this.font,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = math.min(box.maxWidth, box.maxHeight);
      // Hoeveel schijven er leesbaar op de ring passen: de schijf krimpt met het
      // aantal, en het label is een vaste fractie van de schijf. Bij zestien
      // stond er nog 3,4 px letter op (#1162, beeldkeuring); wat er niet bij
      // past wordt geteld.
      // Draagt één blok een afbeelding, dan telt dat voor de hele ring: de
      // schijven zijn even groot, dus de krapste bepaalt wat er past.
      final anyImage = blocks.any((b) => b.hasImage);
      var fits = blocks.length;
      while (fits > 1 &&
          menuDiscLabelSize(
                diameter: side * menuDiscFraction(fits),
                borderWidth: w * _menuDiscTargetBorder,
                hasImage: anyImage,
                hasDescription: false,
              ) <
              w * kMenuMinLabelFraction) {
        fits--;
      }
      final shown = _menuWithCounter(blocks, fits);
      final n = shown.length;
      final disc = side * menuDiscFraction(n);
      final radius = side * menuRingRadius(n);
      // De focusring hangt buiten de schijf en eet dus van de lucht tussen twee
      // buren; bij een volle ring is die lucht krap.
      final ringWidth = menuDiscRingWidth(
        side: side,
        n: n,
        maxWidth: w * _menuDiscRingFactor,
      );
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(
            alignment: Alignment.center,
            // De focusring van een schijf steekt buiten de schijf uit, en bij
            // de bovenste schijf ook buiten dit vierkant. Zonder dit knipte de
            // stapel hem vlak af — en alleen bij bepaalde maten, want of een
            // schijf de rand raakt hangt van de rendermaat af (#1162, derde
            // beeldkeuring).
            clipBehavior: Clip.none,
            children: [
              // Bewust géén ringlijn tussen de schijven. Hij stond er, maar de
              // schijven zijn doorschijnend, dus hij liep zichtbaar dwars door
              // hun labels — hij las als een doorhaling (#1162, beeldkeuring).
              // De ring is als vorm al af zonder hulplijn.
              for (var i = 0; i < n; i++)
                _positioned(
                  context,
                  shown[i],
                  i,
                  n,
                  side,
                  disc,
                  radius,
                  ringWidth,
                ),
            ],
          ),
        ),
      );
    },
  );

  /// Schijf [i] op zijn plek in de ring. Beginnend bovenaan en met de klok mee —
  /// dat leest als een wijzerplaat, dus als een volgorde.
  Widget _positioned(
    BuildContext context,
    MenuBlock block,
    int i,
    int n,
    double side,
    double disc,
    double radius,
    double ringWidth,
  ) {
    final angle = -math.pi / 2 + i * 2 * math.pi / n;
    return Positioned(
      left: side / 2 + radius * math.cos(angle) - disc / 2,
      top: side / 2 + radius * math.sin(angle) - disc / 2,
      width: disc,
      height: disc,
      child: _MenuDisc(
        block: block,
        focusHalo: focusHalo,
        w: w,
        diameter: disc,
        text: text,
        accent: accent,
        projectPath: projectPath,
        font: font,
        onTap: onTap,
        ringWidth: ringWidth,
      ),
    );
  }
}

/// De randdikte van een springende schijf, als fractie van de diabreedte — de
/// zwaarste van de twee, en dus de krapste inhoud. Een tekstblok heeft
/// [_menuDiscPlainBorder].
const double _menuDiscTargetBorder = 0.005;

/// De gewenste dikte van de focusring om een schijf, als fractie van de
/// diabreedte. Zwaarder dan bij een kaart, omdat een springende schijf zelf al
/// een accentrand draagt; [menuDiscRingWidth] kort hem in als de ring vol staat.
const double _menuDiscRingFactor = 0.008;
const double _menuDiscPlainBorder = 0.0026;

/// Eén blok als ronde schijf: de afbeelding klein bovenin, het label eronder,
/// alles binnen de cirkel. De uitleg past hier alleen zonder afbeelding.
class _MenuDisc extends StatelessWidget {
  final MenuBlock block;
  final double w;
  final double diameter;
  final Color text;
  final Color accent;
  final Color focusHalo;
  final String? projectPath;
  final String font;
  final void Function(String anchor)? onTap;

  /// De dikte van de focusring, uitgerekend door de ring eromheen: hij hangt
  /// buiten de schijf, dus hoe dik hij mag zijn hangt af van de lucht tussen
  /// twee buren. Zie [menuDiscRingWidth].
  final double ringWidth;

  const _MenuDisc({
    required this.block,
    required this.w,
    required this.diameter,
    required this.text,
    required this.accent,
    required this.focusHalo,
    this.projectPath,
    required this.font,
    this.onTap,
    required this.ringWidth,
  });

  @override
  Widget build(BuildContext context) {
    final actionable = block.hasTarget;
    final thumb = diameter * kMenuDiscThumbFraction;
    // Net als bij de kaart volgt het regelbudget uit de hoogte die er is; de
    // ruimte binnen een cirkel is de padding eraf, min wat het beeld en de
    // tussenruimte innemen. Géén extra voorwaarde op de schijfmaat: die stond
    // er (`diameter > w * 0.22`) maar kon nooit waar worden — een schijf haalt
    // hoogstens 0,16·w — dus viel de uitleg naast een afbeelding altijd weg,
    // precies wat de voorwaarde moest voorkomen (#1162, beeldkeuring). Of het
    // past, weet [menuTextFit] al.
    final gap = diameter * kMenuDiscGapFraction;
    // De rand zit binnen de schijf, dus hij gaat van de inhoud af. Vergeten
    // betekende een overloop van een paar pixels bij de zwaarste rand — precies
    // die van een springend blok.
    final borderWidth =
        w * (actionable ? _menuDiscTargetBorder : _menuDiscPlainBorder);
    final fit = menuTextFit(
      available: menuDiscTextHeight(
        diameter: diameter,
        borderWidth: borderWidth,
        hasImage: block.hasImage,
      ),
      maxLabelSize: diameter * kMenuDiscLabelFraction,
      hasDescription: block.hasDescription,
      maxLabelLines: 2,
    );

    final disc = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: actionable
              ? [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.08)]
              : [text.withValues(alpha: 0.08), text.withValues(alpha: 0.03)],
        ),
        // In een schijf is geen plek voor de pijl die een kaart draagt, dus doet
        // de rand het werk: een springend blok krijgt er een die twee keer zo
        // zwaar is. Zonder dat verschil was een doelblok in de ring alleen aan
        // een tintje te herkennen (#1162, beeldkeuring).
        border: Border.all(
          color: actionable
              ? accent.withValues(alpha: 0.75)
              : text.withValues(alpha: 0.2),
          width: borderWidth,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        // De tekst binnen een cirkel houden vraagt een ruimere marge dan bij een
        // rechthoek: in de hoeken is er geen vlak.
        padding: EdgeInsets.all(diameter * kMenuDiscPadFraction),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (block.hasImage) ...[
              ClipOval(
                child: SizedBox(
                  width: thumb,
                  height: thumb,
                  child: _resolvedImage(
                    context,
                    block.imagePath,
                    projectPath,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              SizedBox(height: diameter * 0.05),
            ],
            // Elk stuk tekst krijgt precies de hoogte die [menuTextFit] eraan
            // toewees. Stonden ze allebei in een gewone `Flexible`, dan deelde
            // de kolom de ruimte gelijk en negeerde ze het budget dat er net
            // was uitgerekend — label en uitleg liepen dan over elkaar heen
            // (#1162, beeldkeuring).
            SizedBox(
              height: fit.labelLines * fit.labelLineHeight,
              child: _md(
                context,
                block.label,
                _applyFont(
                  font,
                  TextStyle(
                    color: text,
                    fontSize: fit.labelSize,
                    fontWeight: FontWeight.w700,
                    height: kMenuLabelLineHeight,
                  ),
                ),
                linkColor: accent,
                maxLines: fit.labelLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (fit.showsDescription) ...[
              SizedBox(height: gap),
              SizedBox(
                height: fit.descriptionLines * fit.descriptionLineHeight,
                child: _md(
                  context,
                  block.description,
                  _applyFont(
                    font,
                    TextStyle(
                      color: text.withValues(alpha: 0.85),
                      fontSize: fit.descriptionSize,
                      height: kMenuDescriptionLineHeight,
                    ),
                  ),
                  linkColor: accent,
                  maxLines: fit.descriptionLines,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (onTap == null || !actionable) return disc;
    return _MenuFocusable(
      onActivate: () => onTap!(block.targetAnchor),
      semanticLabel: _menuSemanticLabel(block),
      ring: accent,
      halo: focusHalo,
      // Zwaarder dan bij een kaart — een springende schijf draagt zélf al een
      // accentrand — maar begrensd door de lucht tussen twee buren, anders ligt
      // de ring over de buurschijf heen (#1162, beeldkeuring).
      ringWidth: ringWidth,
      shape: BoxShape.circle,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onTap!(block.targetAnchor),
        child: disc,
      ),
    );
  }
}

/// De tweede kleur van de focusring: die van tekst- of achtergrondkleur die het
/// verst van het accent af ligt.
///
/// De ring dankt zijn zichtbaarheid aan het verschil tussen zijn twee banden —
/// op welke achtergrond de dia ook staat, één ervan steekt af. Dat vangnet
/// verdwijnt zodra beide banden dezelfde kleur krijgen, en dat is geen
/// theoretisch geval: in het meegeleverde LibreKAT-profiel zijn `textColor` en
/// `accentColor` allebei `#003399`, en dat profiel staat standaard geselecteerd.
/// De ring viel daar terug op één blauwe band (#1162, vierde beeldkeuring).
///
/// Vandaar niet blind de tekstkleur, maar de verste van de twee die de dia toch
/// al draagt. Een derde kleur verzinnen zou de themaregel breken; kiezen tussen
/// wat er is niet.
Color menuFocusHalo({
  required Color accent,
  required Color text,
  required Color background,
}) {
  final target = accent.computeLuminance();
  return (text.computeLuminance() - target).abs() >=
          (background.computeLuminance() - target).abs()
      ? text
      : background;
}

/// De focusring van een keuzeblok, zodat een proef hem kan aanwijzen.
const Key menuFocusRingKey = ValueKey('menuFocusRing');

/// Wat een schermlezer van een keuzeblok voorleest: het label, en de uitleg
/// erachter omdat die op de dia ook onder het label staat. De vorm — kaart of
/// schijf — doet er voor het oor niet toe; dat het een knop is, zegt
/// [Semantics.button] al.
String _menuSemanticLabel(MenuBlock block) =>
    block.hasDescription ? '${block.label}. ${block.description}' : block.label;

/// Maakt een keuzeblok, een schijf of een categoriepil bedienbaar met het
/// toetsenbord: focusbaar met Tab, activeerbaar met Enter of spatie, en met een
/// focusring die van achter in de zaal te zien is.
///
/// Waarom één widget voor alle drie: de drie vormen verschillen alleen in hun
/// omtrek. Drie keer dezelfde focus-, toets- en semantiekafhandeling
/// uitschrijven is drie plekken waar er één achterblijft — en juist bij
/// toegankelijkheid is dat de plek waar niemand naar kijkt tot iemand het nodig
/// heeft.
///
/// **Toetsen.** Enter en spatie zijn in de presentator "volgende dia". Dat botst
/// niet: een toetsaanslag gaat eerst naar het gefocuste onderdeel, en pas als
/// dat hem laat lopen naar de presentator eromheen. Staat de focus dus op een
/// blok, dan activeert spatie dat blok; staat hij nergens, dan bladert spatie
/// door. Escape geeft de focus terug aan de dia, zodat je met één toets weer
/// gewoon kunt bladeren. De pijltjestoetsen blijven altijd van de presentatie —
/// ze onderscheppen zou betekenen dat je met de focus op een blok niet meer
/// verder kunt.
///
/// Niet aanklikbaar = niet focusbaar: in de editor-voorvertoning, de slidestrook
/// en het beamervenster is [onActivate] null, en dan is dit een gewone doorgeef-
/// widget. Een focusring op het beamerscherm zou het publiek iets tonen wat van
/// de presentator is.
class _MenuFocusable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onActivate;

  /// Wat een schermlezer voorleest. De uitleg gaat mee, want die staat op de
  /// dia ook onder het label.
  final String semanticLabel;

  /// De omtrek van de focusring: rond voor een schijf, afgerond voor een kaart
  /// of een pil. [cornerRadius] is de hoekstraal van het blok zelf; de ring
  /// eromheen krijgt die straal plus zijn eigen dikte, zodat hij evenwijdig
  /// loopt in plaats van de hoeken af te snijden.
  final BoxShape shape;
  final double? cornerRadius;

  /// De ringkleuren. [ring] is de accentkleur van het thema; [halo] ligt er
  /// buiten en zorgt dat de ring ook zichtbaar is op een dia waarvan de
  /// achtergrond toevallig dicht bij het accent ligt.
  final Color ring;
  final Color halo;
  final double ringWidth;

  const _MenuFocusable({
    required this.child,
    required this.onActivate,
    required this.semanticLabel,
    required this.ring,
    required this.halo,
    required this.ringWidth,
    this.shape = BoxShape.rectangle,
    this.cornerRadius,
  });

  @override
  State<_MenuFocusable> createState() => _MenuFocusableState();
}

class _MenuFocusableState extends State<_MenuFocusable> {
  late final _node = FocusNode(debugLabel: 'menu:${widget.semanticLabel}');
  bool _focused = false;

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// Geef de toetsen terug aan wie ze boven ons afhandelt.
  ///
  /// Kaal `unfocus()` is niet genoeg: de focus landt dan op de omhullende
  /// scope, en de presentator — die zijn eigen `Focus` met `onKeyEvent` heeft —
  /// krijgt daarna niets meer. Je drukt Escape en de spatiebalk doet niets. Dus
  /// zoeken we de dichtstbijzijnde voorouder die wél toetsen afhandelt en geven
  /// hem de focus. Dat is generiek: het werkt voor de presentator en voor elke
  /// andere gastheer, zonder dat dit blok hem hoeft te kennen.
  void _releaseFocus() {
    for (final ancestor in _node.ancestors) {
      if (ancestor is FocusScopeNode) continue;
      final context = ancestor.context;
      // De knopen die deze widget zélf opbouwt (de `Shortcuts` van de
      // FocusableActionDetector) staan óók boven ons in de focusboom en
      // handelen toetsen af. Die overslaan, anders geeft Escape de focus aan
      // onszelf terug en verandert er niets.
      if (context == null ||
          context.findAncestorStateOfType<_MenuFocusableState>() == this) {
        continue;
      }
      if (ancestor.onKeyEvent != null) {
        ancestor.requestFocus();
        return;
      }
    }
    _node.unfocus();
  }

  /// Twee ringen **om** [child] heen: buitenom de accentkleur, daarbinnen een
  /// dunnere lijn in de tekstkleur.
  ///
  /// Waarom twee kleuren en geen gloed: de eerste poging gebruikte een
  /// `BoxShadow` zonder vervaging als halo. Een `BoxShadow` tekent geen omtrek
  /// maar een **gevulde** vorm; normaal verdwijnt die onder de achtergrond van
  /// de decoratie, maar deze had er geen en stond in de voorgrond. Het blok met
  /// de focus werd dus volledig overschilderd — label, uitleg en pijl weg,
  /// precies op het blok dat de presentator moest kunnen lezen (#1162,
  /// beeldkeuring). Twee randen tekenen wél omtrekken, en het kleurverschil doet
  /// hetzelfde werk als de gloed: op welke achtergrond de dia ook staat, één van
  /// de twee steekt af.
  ///
  /// Waarom eromhéén en niet erin: `Border.all` tekent binnen de doosgrenzen, en
  /// die ruimte is nergens gereserveerd. De ring is een fractie van de
  /// diabréédte, het blok krimpt met het aantal blokken — dus bij het
  /// gedocumenteerde maximum at een ring van 19 px een schijf van 84 px op en
  /// werd het label aangesneden (tweede beeldkeuring). Een `Stack` met
  /// `Clip.none` legt de ring buiten de doos zonder de layout te raken: het blok
  /// blijft even groot en de tekst staat waar hij stond, met of zonder focus.
  /// De ruimte ernaast is er: de tussenruimte in het raster en op de ring is
  /// ruimer dan de ring dik is.
  Widget _ringed(Widget child) {
    final total = widget.ringWidth * 1.9;
    final circle = widget.shape == BoxShape.circle;
    BoxDecoration ring(Color color, double width, double grown) =>
        BoxDecoration(
          shape: widget.shape,
          borderRadius: circle ? null : BorderRadius.circular(grown),
          border: Border.all(color: color, width: width),
        );
    final radius = widget.cornerRadius ?? 0;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        // De ring hangt buiten het blok en mag geen tikken opvangen: die horen
        // bij het blok eronder.
        Positioned(
          left: -total,
          top: -total,
          right: -total,
          bottom: -total,
          child: IgnorePointer(
            // Gesleuteld zodat een proef de ring kan aanwijzen zonder hem te
            // verwarren met de decoratie van de kaart eronder.
            key: menuFocusRingKey,
            child: DecoratedBox(
              // Let op de volgorde: een achtergrond-decoratie schildert vóór
              // haar kind, dus de buitenste doos komt als eerste aan de beurt en
              // het kind schildert eroverheen. De brede contrastlijn hoort dus
              // buitenaan te staan en de smalle accentband erbinnen — dan dekt
              // het accent de buitenste `ringWidth` af en blijft de contrastlijn
              // daarbinnen zichtbaar. Andersom (zoals het even stond) verdwijnt
              // het accent volledig onder de contrastlijn en houd je een
              // eenkleurige donut over (#1162, derde beeldkeuring).
              decoration: ring(widget.halo, total, radius + total),
              child: DecoratedBox(
                decoration: ring(widget.ring, widget.ringWidth, radius + total),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final activate = widget.onActivate;
    if (activate == null) return widget.child;
    return Semantics(
      container: true,
      button: true,
      label: widget.semanticLabel,
      // De tekst ín het blok zegt hetzelfde als het label hierboven; zonder
      // uitsluiten leest een schermlezer alles dubbel.
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: _node,
        onShowFocusHighlight: (value) {
          if (value != _focused) setState(() => _focused = value);
        },
        onFocusChange: (value) {
          if (!value && _focused) setState(() => _focused = false);
        },
        // Enter, numpad-Enter en spatie staan hier expliciet en niet op de
        // standaardafspraken van het platform: Enter bleek daar niet op
        // `ActivateIntent` te vallen, viel door naar de presentator, en deed dus
        // "volgende dia" terwijl de focus op een blok stond. Twee proeven waren
        // daardoor groen om de verkeerde reden — ze landden op de dia erna, die
        // toevallig ook de doeldia was.
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              activate();
              return null;
            },
          ),
          // Escape geeft de focus terug aan de dia, zodat de presentator met één
          // toets weer gewoon bladert. Alleen bereikbaar als dit onderdeel de
          // focus heeft, dus de gelaagde Escape van de presentator blijft heel.
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              _releaseFocus();
              return null;
            },
          ),
        },
        mouseCursor: SystemMouseCursors.click,
        child: _focused ? _ringed(widget.child) : widget.child,
      ),
    );
  }
}
