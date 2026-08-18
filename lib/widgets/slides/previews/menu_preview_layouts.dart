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
}) {
  Widget card(MenuBlock block, {bool wide = false}) => _MenuBlockCard(
    block: block,
    w: w,
    text: text,
    accent: accent,
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
      projectPath: projectPath,
      font: font,
      onTap: onBlockTap,
    ),
  };
}

/// Het raster: rijen die de hoogte verdelen, kolommen naar het aantal blokken.
Widget _menuGrid(
  List<MenuBlock> blocks,
  double w,
  Widget Function(MenuBlock, {bool wide}) card,
) {
  final n = blocks.length;
  final cols = menuGridColumns(n);
  final rows = (n / cols).ceil();
  final gap = w * 0.018;
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
                      ? card(blocks[r * cols + c])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ),
      ],
    ],
  );
}

/// De prettigste hoogte van één regel in de indeling "onder elkaar", en de
/// ruimte ertussen. Passen zoveel regels niet op de dia, dan worden ze lager —
/// en krimpt de tekst mee ([_MenuBlockCard._content]) in plaats van eronder weg
/// te vallen.
const double _menuRowHeightFactor = 0.09;
const double _menuRowGapFactor = 0.012;

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
      final n = blocks.length;
      final even = (box.maxHeight - gap * (n - 1)) / n;
      final height = math.min(even, w * _menuRowHeightFactor);
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) SizedBox(height: gap),
            SizedBox(height: height, child: card(blocks[i], wide: true)),
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
          width: w * 0.0026,
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap!(block.targetAnchor),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: card),
    );
  }

  Widget _content(BuildContext context, BoxConstraints box) {
    // De marge krimpt mee met een lage kaart: bij zestien blokken in een lijst
    // is een vaste marge al hoger dan de kaart zelf, en dan blijft er niets voor
    // de tekst over.
    final pad = math.min(w * 0.014, box.maxHeight * 0.12);
    final inner = math.max(0.0, box.maxHeight - pad * 2);
    final thumb = math.min(inner, math.min(box.maxWidth * 0.3, w * 0.1));

    // Lettergrootte en regelbudget volgen uit de ruimte, niet uit een vast
    // getal; zie [menuTextFit] voor waarom dat het verschil maakt tussen
    // afbreken met een ellips en onzichtbaar weggeknipt worden.
    final fit = menuTextFit(
      available: inner,
      maxLabelSize: w * 0.026,
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
  final String? projectPath;
  final String font;
  final void Function(String anchor)? onTap;

  const _MenuCircle({
    required this.blocks,
    required this.w,
    required this.text,
    required this.accent,
    this.projectPath,
    required this.font,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, box) {
      final side = math.min(box.maxWidth, box.maxHeight);
      final n = blocks.length;
      final disc = side * menuDiscFraction(n);
      final radius = side * menuRingRadius(n);
      return Center(
        child: SizedBox(
          width: side,
          height: side,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Bewust géén ringlijn tussen de schijven. Hij stond er, maar de
              // schijven zijn doorschijnend, dus hij liep zichtbaar dwars door
              // hun labels — hij las als een doorhaling (#1162, beeldkeuring).
              // De ring is als vorm al af zonder hulplijn.
              for (var i = 0; i < n; i++)
                _positioned(context, i, n, side, disc, radius),
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
    int i,
    int n,
    double side,
    double disc,
    double radius,
  ) {
    final angle = -math.pi / 2 + i * 2 * math.pi / n;
    return Positioned(
      left: side / 2 + radius * math.cos(angle) - disc / 2,
      top: side / 2 + radius * math.sin(angle) - disc / 2,
      width: disc,
      height: disc,
      child: _MenuDisc(
        block: blocks[i],
        w: w,
        diameter: disc,
        text: text,
        accent: accent,
        projectPath: projectPath,
        font: font,
        onTap: onTap,
      ),
    );
  }
}

/// Eén blok als ronde schijf: de afbeelding klein bovenin, het label eronder,
/// alles binnen de cirkel. De uitleg past hier alleen zonder afbeelding.
class _MenuDisc extends StatelessWidget {
  final MenuBlock block;
  final double w;
  final double diameter;
  final Color text;
  final Color accent;
  final String? projectPath;
  final String font;
  final void Function(String anchor)? onTap;

  const _MenuDisc({
    required this.block,
    required this.w,
    required this.diameter,
    required this.text,
    required this.accent,
    this.projectPath,
    required this.font,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final actionable = block.hasTarget;
    final thumb = diameter * 0.34;
    // Net als bij de kaart volgt het regelbudget uit de hoogte die er is; de
    // ruimte binnen een cirkel is de padding eraf, min wat het beeld en de
    // tussenruimte innemen. Géén extra voorwaarde op de schijfmaat: die stond
    // er (`diameter > w * 0.22`) maar kon nooit waar worden — een schijf haalt
    // hoogstens 0,16·w — dus viel de uitleg naast een afbeelding altijd weg,
    // precies wat de voorwaarde moest voorkomen (#1162, beeldkeuring). Of het
    // past, weet [menuTextFit] al.
    final gap = diameter * 0.04;
    // De rand zit binnen de schijf, dus hij gaat van de inhoud af. Vergeten
    // betekende een overloop van een paar pixels bij de zwaarste rand — precies
    // die van een springend blok.
    final borderWidth = w * (actionable ? 0.005 : 0.0026);
    final fit = menuTextFit(
      available:
          diameter * 0.68 -
          borderWidth * 2 -
          (block.hasImage ? thumb + diameter * 0.05 : 0) -
          gap,
      maxLabelSize: diameter * 0.15,
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
        padding: EdgeInsets.all(diameter * 0.16),
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
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onTap!(block.targetAnchor),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: disc),
    );
  }
}
