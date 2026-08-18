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

/// Hoogte van één regel in de indeling "onder elkaar", en de ruimte ertussen.
/// Vast, niet verdeeld over de dia: een regel houdt zo dezelfde leeshoogte of er
/// nu drie of dertig blokken staan. Passen ze samen niet meer op de dia, dan
/// schaalt de `FittedBox` van de stellage het geheel omlaag — hetzelfde gedrag
/// als bij te veel tekst op een gewone dia, in plaats van regels die tot een
/// streepje worden geperst.
const double _menuRowHeightFactor = 0.075;
const double _menuRowGapFactor = 0.012;

/// Onder elkaar: brede kaarten, één per regel, gecentreerd in de ruimte die er
/// is.
Widget _menuList(
  List<MenuBlock> blocks,
  double w,
  Widget Function(MenuBlock, {bool wide}) card,
) => Column(
  mainAxisAlignment: MainAxisAlignment.center,
  mainAxisSize: MainAxisSize.min,
  children: [
    for (var i = 0; i < blocks.length; i++) ...[
      if (i > 0) SizedBox(height: w * _menuRowGapFactor),
      SizedBox(
        height: w * _menuRowHeightFactor,
        child: card(blocks[i], wide: true),
      ),
    ],
  ],
);

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
    final pad = w * 0.014;
    final inner = box.maxHeight - pad * 2;
    final thumb = math.min(inner, math.min(box.maxWidth * 0.3, w * 0.1));
    // Wat er nog bij past, in volgorde van belang: eerst het label, dan de
    // uitleg, dan de pijl. Onder de drempels zou het toch niet leesbaar zijn.
    final roomForDescription =
        block.hasDescription && box.maxHeight > w * 0.055;
    final showArrow = block.hasTarget && box.maxWidth > w * 0.16;
    final centred = !wide && !block.hasImage && !roomForDescription;

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
              crossAxisAlignment: centred
                  ? CrossAxisAlignment.center
                  : CrossAxisAlignment.start,
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
                        fontSize: w * 0.026,
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    linkColor: accent,
                    maxLines: roomForDescription ? 2 : 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: centred ? TextAlign.center : TextAlign.start,
                  ),
                ),
                if (roomForDescription) ...[
                  SizedBox(height: w * 0.005),
                  Flexible(
                    child: _md(
                      context,
                      block.description,
                      _applyFont(
                        font,
                        TextStyle(
                          color: text.withValues(alpha: 0.7),
                          fontSize: w * 0.019,
                          height: 1.2,
                        ),
                      ),
                      linkColor: accent,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: centred ? TextAlign.center : TextAlign.start,
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
              size: w * 0.024,
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
              // De ringlijn zelf: hij bindt de schijven visueel samen.
              Container(
                width: radius * 2,
                height: radius * 2,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.18),
                    width: w * 0.0022,
                  ),
                ),
              ),
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
    final showDescription = block.hasDescription && !block.hasImage;
    final disc = Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: actionable
              ? [accent.withValues(alpha: 0.22), accent.withValues(alpha: 0.08)]
              : [text.withValues(alpha: 0.08), text.withValues(alpha: 0.03)],
        ),
        border: Border.all(
          color: actionable
              ? accent.withValues(alpha: 0.6)
              : text.withValues(alpha: 0.2),
          width: w * 0.0026,
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
            Flexible(
              child: _md(
                context,
                block.label,
                _applyFont(
                  font,
                  TextStyle(
                    color: text,
                    fontSize: diameter * 0.15,
                    fontWeight: FontWeight.w700,
                    height: 1.1,
                  ),
                ),
                linkColor: accent,
                maxLines: block.hasImage ? 2 : 3,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            if (showDescription)
              Flexible(
                child: _md(
                  context,
                  block.description,
                  _applyFont(
                    font,
                    TextStyle(
                      color: text.withValues(alpha: 0.7),
                      fontSize: diameter * 0.11,
                      height: 1.15,
                    ),
                  ),
                  linkColor: accent,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
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
