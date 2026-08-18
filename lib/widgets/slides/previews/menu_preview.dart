// Part of the slide_preview library — see ../slide_preview.dart.
// Split out for navigability; all imports live in the main library file.
part of '../slide_preview.dart';

/// Preview van een keuze-menudia (#1162): de blokken in de gekozen indeling
/// ([MenuLayout]) — raster, onder elkaar of in een cirkel — in de themakleuren
/// (achtergrond/tekst/accent uit het [ThemeProfile], nooit een eigen palet). Een
/// blok met een doel oogt aanklikbaar met een accentrand en een pijl; een blok
/// zonder doel is een rustig tekstblok. Draagt het menu categorieën, dan staat er
/// een keuzebalk boven de blokken.
///
/// Interactie (de sprong bij een klik) leeft in de presentator; de preview toont
/// hoe het eruitziet en, als de aanroeper een [onCategoryChanged] meegeeft, welke
/// categorie open staat.
class _MenuPreview extends StatefulWidget {
  final Slide slide;
  final double w;
  final String? projectPath;
  final String font;
  final ThemeProfile profile;

  /// Zie [SlidePreviewWidget.onMenuBlockTap]: gezet tijdens presenteren, dan zijn
  /// doel-blokken aanklikbaar. Null = alleen tonen.
  final void Function(String anchor)? onBlockTap;

  /// Welke categorie open staat. Van buiten gestuurd zodat het beamervenster
  /// dezelfde categorie toont als het presentatorscherm.
  final int category;

  /// Gezet = de categoriebalk is aanklikbaar en meldt een wissel terug. Null =
  /// de balk toont alleen (slidestrook, beamervenster).
  final ValueChanged<int>? onCategoryChanged;

  const _MenuPreview({
    required this.slide,
    required this.w,
    this.projectPath,
    required this.font,
    required this.profile,
    this.onBlockTap,
    this.category = 0,
    this.onCategoryChanged,
  });

  @override
  State<_MenuPreview> createState() => _MenuPreviewState();
}

class _MenuPreviewState extends State<_MenuPreview> {
  /// De open categorie. Lokaal bijgehouden zodat een tik meteen zichtbaar is,
  /// ook als de aanroeper de waarde pas een frame later terugstuurt.
  late int _selected = widget.category;

  @override
  void didUpdateWidget(_MenuPreview old) {
    super.didUpdateWidget(old);
    // Van buiten gestuurde wissel (beamervenster volgt de presentator) en het
    // wisselen van dia zelf: begin dan weer bij de eerste categorie.
    if (widget.category != old.category) _selected = widget.category;
    if (widget.slide.id != old.slide.id) _selected = 0;
  }

  void _select(int index) {
    if (index == _selected) return;
    setState(() => _selected = index);
    widget.onCategoryChanged?.call(index);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.w;
    final categories = menuCategoriesFor(widget.slide.bullets);
    final showTabs = menuHasCategories(categories);
    final index = _selected.clamp(0, categories.length - 1);
    final blocks = categories[index].blocks;
    final text = AppTheme.parseHexColor(widget.profile.textColor);
    final accent = AppTheme.parseHexColor(widget.profile.accentColor);
    final hasTitle = widget.slide.title.trim().isNotEmpty;

    // Het blokkenvlak krijgt de hoogte die na titel en keuzebalk overblijft, op
    // de echte diahoogte (16:9 min de marges). Vroeger stond hier een vaste
    // 0.46·w die mét titel niet paste, waarna de `FittedBox` de hele dia
    // omlaagschaalde en de blokken onnodig klein werden.
    final blocksHeight = math.max(
      w * 0.16,
      w * 0.4725 - (hasTitle ? w * 0.086 : 0) - (showTabs ? w * 0.062 : 0),
    );

    return _PreviewScaffold(
      width: w,
      slide: widget.slide,
      profile: widget.profile,
      horizontalPadding: w * 0.05,
      verticalPadding: w * 0.045,
      background: AppTheme.parseHexColor(widget.profile.slideBackgroundColor),
      children: [
        if (hasTitle) ...[
          _md(
            context,
            widget.slide.title,
            _applyFont(
              widget.font,
              TextStyle(
                color: text,
                fontSize: w * 0.05,
                fontWeight: FontWeight.bold,
                height: 1.15,
              ),
            ),
            linkColor: accent,
          ),
          SizedBox(height: w * 0.014),
        ],
        if (showTabs) ...[
          _MenuCategoryBar(
            categories: categories,
            selected: index,
            w: w,
            text: text,
            accent: accent,
            font: widget.font,
            onSelect: widget.onCategoryChanged == null ? null : _select,
          ),
          SizedBox(height: w * 0.018),
        ],
        if (blocks.isNotEmpty)
          // Raster en cirkel verdelen de ruimte die er is; de lijst houdt zijn
          // regelhoogte en mag dóórgroeien — dan schaalt de stellage de dia.
          ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: w,
              maxWidth: w,
              minHeight: blocksHeight,
              maxHeight: widget.slide.menuLayout == MenuLayout.list
                  ? double.infinity
                  : blocksHeight,
            ),
            child: _menuBlockArea(
              context,
              blocks: blocks,
              layout: widget.slide.menuLayout,
              w: w,
              text: text,
              accent: accent,
              projectPath: widget.projectPath,
              font: widget.font,
              onBlockTap: widget.onBlockTap,
            ),
          ),
      ],
    );
  }
}

/// De categoriebalk: pillen waarvan er één gevuld is. Aanklikbaar zodra
/// [onSelect] gezet is; anders alleen een aanduiding van wat er open staat.
class _MenuCategoryBar extends StatelessWidget {
  final List<MenuCategory> categories;
  final int selected;
  final double w;
  final Color text;
  final Color accent;
  final String font;
  final ValueChanged<int>? onSelect;

  const _MenuCategoryBar({
    required this.categories,
    required this.selected,
    required this.w,
    required this.text,
    required this.accent,
    required this.font,
    this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: w * 0.012,
      runSpacing: w * 0.008,
      children: [
        for (var i = 0; i < categories.length; i++)
          _pill(
            // Een naamloze eerste categorie (blokken vóór de eerste tussenkop)
            // heeft toch een naam nodig zodra er een balk staat.
            categories[i].isNamed ? categories[i].label : l10n.d('Algemeen'),
            i,
          ),
      ],
    );
  }

  Widget _pill(String label, int index) {
    final on = index == selected;
    final pill = Container(
      padding: EdgeInsets.symmetric(horizontal: w * 0.018, vertical: w * 0.008),
      decoration: BoxDecoration(
        color: on ? accent.withValues(alpha: 0.16) : Colors.transparent,
        border: Border.all(
          color: on
              ? accent.withValues(alpha: 0.7)
              : text.withValues(alpha: 0.2),
          width: w * 0.0022,
        ),
        borderRadius: BorderRadius.circular(w * 0.03),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: _applyFont(
          font,
          TextStyle(
            color: on ? accent : text.withValues(alpha: 0.7),
            fontSize: w * 0.021,
            fontWeight: on ? FontWeight.w700 : FontWeight.w500,
            height: 1.1,
          ),
        ),
      ),
    );
    if (onSelect == null) return pill;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onSelect!(index),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: pill),
    );
  }
}
