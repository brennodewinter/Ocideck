// Part of the document-markdown-view library — see ../document_markdown_view.dart.
//
// De ontleedde bouwstenen van een Markdown-document (blokken, lijstregels, het
// afgeleide themaobject) en de bewerkbare inbedding. Losgeknipt van
// document_markdown_view.dart om dat bestand onder het regelplafond te houden:
// het groeide er met de tabelstijl, de past-op-scherm-tabel en de
// inhoudsopgave-preview overheen. Eén library, dus de weergave gebruikt ze
// ongewijzigd.
part of '../document_markdown_view.dart';

/// The kind of a parsed Markdown block.
enum _Kind {
  heading,
  paragraph,
  list,
  quote,
  code,
  mermaid,
  chart,
  table,
  rule,
  toc,
}

/// One parsed block: its kind plus whatever that kind needs to render and to be
/// searched. Kept as a plain data record so parsing is a pure step, decoupled
/// from widget building.
class _Block {
  const _Block(
    this.kind, {
    this.text = '',
    this.level = 0,
    this.items = const [],
    this.rows = const [],
    this.aligns = const [],
  });

  final _Kind kind;

  /// heading / paragraph / quote / code / mermaid content.
  final String text;

  /// Heading level 1–6 (0 otherwise).
  final int level;

  /// List item lines (for [_Kind.list]).
  final List<_ListLine> items;

  /// Raw table rows — header + body, *without* the delimiter row (for
  /// [_Kind.table]). The per-column alignment from that delimiter is parsed out
  /// into [aligns].
  final List<String> rows;

  /// Per-column alignment from the GFM delimiter row (for [_Kind.table]); shorter
  /// than the column count means the rest default to left (the GFM default).
  final List<TableAlign> aligns;

  /// The plain text a find-in-page query matches against. Rules never match;
  /// tables and lists flatten their cells/items into one searchable string.
  String get searchText => switch (kind) {
    _Kind.table => rows.join(' '),
    _Kind.list => items.map((e) => e.text).join(' '),
    _Kind.rule => '',
    _Kind.toc => 'inhoudsopgave table of contents',
    _ => text,
  };
}

/// One parsed list line with its nesting depth and (for ordered lists) number.
class _ListLine {
  const _ListLine({
    required this.text,
    required this.ordered,
    required this.number,
    required this.depth,
    this.checked,
  });

  final String text;
  final bool ordered;
  final int number;
  final int depth;

  /// Tick state of a GFM task item, or null when this is a plain list item.
  /// Null and `false` mean different things here: "not a checklist at all"
  /// versus "a box that is not ticked".
  final bool? checked;
}

/// Resolved, theme-derived colours and the base text style, computed once so
/// every block builder shares them.
/// An opaque [color] as `#RRGGBB` for handing to the hex-based SVG renderer.
String _hexRgb(Color color) {
  String two(double channel) =>
      (channel * 255).round().clamp(0, 255).toRadixString(16).padLeft(2, '0');
  return '#${two(color.r)}${two(color.g)}${two(color.b)}'.toUpperCase();
}

Color _profileColor(String? value, Color fallback) => value == null
    ? fallback
    : AppTheme.parseHexColor(value, fallback: fallback);

class _Theme {
  _Theme(ThemeData theme, ThemeProfile? profile)
    : dark = theme.brightness == Brightness.dark,
      paper = _profileColor(
        profile?.slideBackgroundColor,
        theme.colorScheme.surface,
      ),
      body = TextStyle(
        fontFamily: profile?.fontFamily,
        fontSize: 15.5,
        height: 1.55,
        color: _profileColor(profile?.textColor, theme.colorScheme.onSurface),
      ),
      heading = _profileColor(profile?.textColor, theme.colorScheme.onSurface),
      subheading = _profileColor(
        profile?.accentColor,
        theme.colorScheme.onSurface,
      ),
      marker = _profileColor(
        profile?.accentColor,
        AppPalette.of(theme).accentInk,
      ),
      checkboxEmpty = _profileColor(
        profile?.checklistUncheckedColor,
        theme.colorScheme.onSurfaceVariant,
      ),
      checkboxChecked = _profileColor(
        profile?.checklistCheckedColor,
        AppPalette.of(theme).accentInk,
      ),
      link = _profileColor(
        profile?.accentColor,
        AppPalette.of(theme).accentInk,
      ),
      border = profile == null
          ? theme.colorScheme.outlineVariant
          : _profileColor(
              profile.textColor,
              theme.colorScheme.onSurface,
            ).withValues(alpha: 0.22),
      quoteBg = profile == null
          ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
          : _profileColor(
              profile.accentColor,
              AppPalette.of(theme).accentInk,
            ).withValues(alpha: 0.10),
      quoteBar = _profileColor(
        profile?.accentColor,
        AppPalette.of(theme).accentInk,
      ),
      quoteText = _profileColor(
        profile?.textColor,
        theme.colorScheme.onSurfaceVariant,
      ),
      codeBg = _profileColor(
        profile?.codeBackgroundColor,
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      ),
      chartCardHex = _hexRgb(
        Color.alphaBlend(
          _profileColor(
            profile?.codeBackgroundColor,
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          ),
          _profileColor(
            profile?.slideBackgroundColor,
            theme.colorScheme.surface,
          ),
        ),
      ),
      codeText = _profileColor(
        profile?.codeTextColor,
        theme.colorScheme.onSurface,
      ),
      tableHeaderBg = _profileColor(
        profile?.tableHeaderBackgroundColor,
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
      ),
      tableHeaderText = _profileColor(
        profile?.tableHeaderTextColor,
        theme.colorScheme.onSurface,
      ),
      tableText = _profileColor(
        profile?.tableTextColor,
        theme.colorScheme.onSurface,
      ),
      tableZebraStriped = profile?.tableZebraStriped ?? false,
      tableZebraBg = _profileColor(
        profile?.tableZebraColor,
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
      ),
      tableBorderStyle = profile?.tableBorderStyle ?? TableBorderStyle.boxed,
      tableBorder = _profileColor(
        profile?.tableBorderColor,
        theme.colorScheme.outlineVariant,
      ),
      tableCellPad = profile?.tableCellPaddingPx ?? 8.0,
      tableAccentHeaderBorder = profile?.tableAccentHeaderBorder ?? false,
      tableAccent = _profileColor(
        profile?.accentColor,
        AppPalette.of(theme).accentInk,
      ),
      findMatch = AppTheme.findHighlight,
      findActive = AppTheme.findHighlightActive;

  final bool dark;
  final Color paper;
  final TextStyle body;
  final Color heading;
  final Color subheading;
  final Color marker;
  final Color checkboxEmpty;
  final Color checkboxChecked;
  final Color link;
  final Color border;
  final Color quoteBg;
  final Color quoteBar;
  final Color quoteText;
  final Color codeBg;
  final String chartCardHex;
  final Color codeText;
  final Color tableHeaderBg;
  final Color tableHeaderText;
  final Color tableText;
  final bool tableZebraStriped;
  final Color tableZebraBg;
  final TableBorderStyle tableBorderStyle;
  final Color tableBorder;
  final double tableCellPad;
  final bool tableAccentHeaderBorder;
  final Color tableAccent;
  final Color findMatch;
  final Color findActive;
}

/// Omhult een bewerkbare embed (grafiek of tabel) in de editor: hand-cursor,
/// dubbelklik om te bewerken, én een zichtbaar potlood-knopje rechtsboven dat
/// bij één klik dezelfde editor opent. Het potlood is altijd subtiel zichtbaar
/// en licht op bij hover — zodat de bewerkbaarheid ontdekbaar is zonder dat je
/// de dubbelklik hoeft te raden (vgl. #1210: een dubbelklik-alleen affordance
/// vond niemand). Alleen in de editor gemonteerd; de docs-lezer geeft geen
/// bewerk-callback en krijgt dus geen potlood.
class _EditableEmbed extends StatefulWidget {
  const _EditableEmbed({required this.child, required this.onEdit});

  final Widget child;
  final VoidCallback onEdit;

  @override
  State<_EditableEmbed> createState() => _EditableEmbedState();
}

class _EditableEmbedState extends State<_EditableEmbed> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onDoubleTap: widget.onEdit,
        child: Stack(
          children: [
            widget.child,
            Positioned(
              top: 6,
              right: 6,
              child: AnimatedOpacity(
                opacity: _hover ? 1 : 0.6,
                duration: const Duration(milliseconds: 120),
                child: Material(
                  // Volledig dekkend + een lichte schaduw: waar het potlood over
                  // een cel valt (een smalle tabelkop) leest het als een knop
                  // erbovenop in plaats van door de tekst heen te schemeren.
                  color: scheme.surface,
                  elevation: 2,
                  shadowColor: Colors.black45,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(color: scheme.outlineVariant),
                  ),
                  child: Tooltip(
                    message: context.l10n.d('Bewerken'),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: widget.onEdit,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          Icons.edit_outlined,
                          size: 16,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
