// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview van een keuze-menudia (#1162): de blokken als raster van kaarten, in
/// de themakleuren (achtergrond/tekst/accent uit het [ThemeProfile], nooit een
/// eigen palet). Een blok met een doel oogt aanklikbaar met een accentrand; een
/// blok zonder doel is een rustig tekstblok. Interactie (de sprong bij een klik)
/// leeft in de presentator; de preview toont alleen hoe het eruitziet.
class _MenuPreview extends StatelessWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  /// Zie [SlidePreviewWidget.onMenuBlockTap]: gezet tijdens presenteren, dan zijn
  /// doel-blokken aanklikbaar. Null = alleen tonen.
  final void Function(String anchor)? onBlockTap;

  const _MenuPreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
    this.onBlockTap,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = menuBlocksFor(slide.bullets);
    final text = AppTheme.parseHexColor(profile.textColor);
    final accent = AppTheme.parseHexColor(profile.accentColor);
    return _PreviewScaffold(
      width: w,
      slide: slide,
      profile: profile,
      horizontalPadding: w * 0.05,
      verticalPadding: w * 0.045,
      background: AppTheme.parseHexColor(profile.slideBackgroundColor),
      children: [
        if (slide.title.trim().isNotEmpty) ...[
          _md(
            context,
            slide.title,
            _applyFont(
              font,
              TextStyle(
                color: text,
                fontSize: w * 0.05,
                fontWeight: FontWeight.bold,
                height: 1.15,
              ),
            ),
            linkColor: accent,
          ),
          SizedBox(height: w * 0.028),
        ],
        if (blocks.isNotEmpty)
          SizedBox(
            width: w,
            height: w * 0.46,
            child: _menuGrid(
              context,
              blocks,
              w,
              text,
              accent,
              projectPath,
              font,
              onBlockTap,
            ),
          ),
      ],
    );
  }
}

/// Het blokkenraster: zoveel kolommen als bij het aantal past, kaarten die de
/// resthoogte vullen. Top-level zodat de preview-widget klein blijft.
Widget _menuGrid(
  BuildContext context,
  List<MenuBlock> blocks,
  double w,
  Color text,
  Color accent,
  String? projectPath,
  String font,
  void Function(String anchor)? onBlockTap,
) {
  final n = blocks.length;
  final cols = n <= 1
      ? 1
      : n <= 4
      ? 2
      : n <= 9
      ? 3
      : 4;
  final rows = (n / cols).ceil();
  final gap = w * 0.02;
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
                      ? _MenuBlockCard(
                          block: blocks[r * cols + c],
                          w: w,
                          text: text,
                          accent: accent,
                          projectPath: projectPath,
                          font: font,
                          onTap: onBlockTap,
                        )
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

/// Eén keuzeblok als kaart. Met afbeelding: beeld boven, label eronder. Zonder
/// afbeelding: het label gecentreerd. De randkleur onderscheidt een blok dat
/// ergens heen springt van een gewoon tekstblok.
class _MenuBlockCard extends StatelessWidget {
  final MenuBlock block;
  final double w;
  final Color text;
  final Color accent;
  final String? projectPath;
  final String font;
  final void Function(String anchor)? onTap;

  const _MenuBlockCard({
    required this.block,
    required this.w,
    required this.text,
    required this.accent,
    this.projectPath,
    required this.font,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final actionable = block.hasTarget;
    final border = actionable
        ? accent.withValues(alpha: 0.55)
        : text.withValues(alpha: 0.22);
    final fill = accent.withValues(alpha: actionable ? 0.10 : 0.04);
    // Het label moet begrensd zijn: onder een afbeelding is er weinig verticale
    // ruimte, en een lang label liep de kaart uit (#1162, beeldkeuring). Onder een
    // afbeelding hoogstens twee regels, een tekstblok vult de hele kaart en mag er
    // meer; in beide gevallen breekt het af met een ellips i.p.v. over te lopen.
    Widget labelText(int maxLines) => Padding(
      padding: EdgeInsets.all(w * 0.02),
      child: _md(
        context,
        block.label,
        _applyFont(
          font,
          TextStyle(
            color: text,
            fontSize: w * 0.03,
            fontWeight: FontWeight.w600,
            height: 1.15,
          ),
        ),
        linkColor: accent,
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
      ),
    );
    final card = Container(
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: border, width: w * 0.003),
        borderRadius: BorderRadius.circular(w * 0.014),
      ),
      clipBehavior: Clip.antiAlias,
      child: block.hasImage
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _resolvedImage(
                    context,
                    block.imagePath,
                    projectPath,
                    fit: BoxFit.cover,
                  ),
                ),
                labelText(2),
              ],
            )
          : Center(child: labelText(5)),
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
}
