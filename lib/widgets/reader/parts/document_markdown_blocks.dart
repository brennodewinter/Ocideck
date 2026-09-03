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
  timeline,
  rule,
  image,
  toc,
}

/// One parsed block: its kind plus whatever that kind needs to render and to be
/// searched. Kept as a plain data record so parsing is a pure step, decoupled
/// from widget building.
class _Block {
  const _Block(
    this.kind, {
    this.text = '',
    this.source = '',
    this.level = 0,
    this.items = const [],
    this.rows = const [],
    this.aligns = const [],
    this.timelineMarker = '',
    this.timelineMarkerHeader = '',
    this.timelineEventHeader = '',
    this.timelineMetadata,
    this.timelineMetadataHeader,
    this.timelineFirst = false,
    this.timelineLast = false,
  });

  final _Kind kind;

  /// heading / paragraph / quote / code / mermaid content.
  final String text;

  /// De bron van een afbeelding `![alt](bron)` — het pad tussen de haakjes,
  /// zonder titel (voor [_Kind.image]). [text] draagt de alt-tekst.
  final String source;

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

  final String timelineMarker;
  final String timelineMarkerHeader;
  final String timelineEventHeader;
  final String? timelineMetadata;
  final String? timelineMetadataHeader;
  final bool timelineFirst;
  final bool timelineLast;

  /// The plain text a find-in-page query matches against. Rules never match;
  /// tables and lists flatten their cells/items into one searchable string.
  String get searchText => switch (kind) {
    _Kind.table => rows.join(' '),
    _Kind.timeline => [timelineMarker, text, ?timelineMetadata].join(' '),
    _Kind.list => items.map((e) => e.text).join(' '),
    _Kind.rule => '',
    _Kind.image => text,
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

  /// Hetzelfde item met [more] eraan geplakt — voor een regel die in de bron is
  /// afgebroken maar bij dit item hoort.
  _ListLine continued(String more) => _ListLine(
    text: '$text $more',
    ordered: ordered,
    number: number,
    depth: depth,
    checked: checked,
  );
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

/// De typografie van een documentpagina, gedeeld met het schrijfvlak.
///
/// De visuele editor neemt deze maten over wanneer je op een pagina schrijft.
/// Ze horen dus op één plek te staan: liepen ze uiteen, dan liep ook de
/// pagina-indeling van de schrijfstand uiteen met die van de druk — en dat is
/// niet zichtbaar aan de code, alleen aan een lijn die op de verkeerde plek
/// staat.
const double kDocumentBodyFontSize = kDocumentDefaultBodyFontSize;
const double kDocumentBodyLineHeight = 1.55;
const double kDocumentParagraphGap = 12;
const double kDocumentHeadingGapTop = 26;
const double kDocumentSubheadingGapTop = 18;
const double kDocumentHeadingGapBottom = 8;
const double kDocumentListRowGap = 4;

/// Hoeveel regels bodytekst er onder een kop op hetzelfde vel moeten passen
/// voordat de kop daar mag blijven staan.
///
/// Twee, en niet één: een kop met één losse regel eronder en de rest op het
/// volgende vel leest net zo verkeerd als een kop die helemaal alleen staat.
/// Zelfde getal als de `widows`/`orphans` in de print-CSS van de HTML-export,
/// zodat scherm en druk hetzelfde zeggen.
const int kDocumentKeepWithNextLines = 2;

/// De hoogte die [kDocumentKeepWithNextLines] regels bodytekst innemen onder
/// [scaler] — de tekstschaal van het toestel, met de zoom van de editor erin.
///
/// Via de schaler en niet via een kale factor: een niet-lineaire schaal (de
/// toegankelijkheidsinstelling van het toestel) rekent per lettergrootte, en
/// dan is de factor bij maat 1 niet die bij maat 15,5.
double documentKeepWithNextHeight(
  TextScaler scaler, {
  double bodyFontSize = kDocumentBodyFontSize,
}) =>
    scaler.scale(bodyFontSize) *
    kDocumentBodyLineHeight *
    kDocumentKeepWithNextLines;

/// De blokken die op een verse pagina horen te beginnen, als index in
/// dezelfde lijst als [DocumentMarkdownView.blockTexts].
///
/// Twee soorten, allebei uit het formaat en allebei gehonoreerd door de HTML-
/// en LaTeX-export (FILE_FORMAT.md §14.6): een `---` in de body ís een
/// pagina-einde, en met [chapterBreak] begint elk hoofdstuk (`H1`) op een
/// nieuw vel. Het eerste blok telt nooit mee — een breuk vóór de eerste regel
/// zou een leeg vel opleveren.
Set<int> documentForcedPageBreaks(
  String markdown, {
  bool chapterBreak = false,
}) {
  final blocks = DocumentMarkdownView._parse(markdown);
  final breaks = <int>{};
  // Wat er sinds de vorige breuk aan échte inhoud staat. Een `---` telt niet
  // mee: in een paginaweergave ís hij het einde zelf, geen inhoud.
  var contentSinceBreak = 0;
  for (var i = 0; i < blocks.length; i++) {
    final rule = blocks[i].kind == _Kind.rule;
    final chapter =
        chapterBreak && blocks[i].kind == _Kind.heading && blocks[i].level == 1;
    if ((rule || chapter) && contentSinceBreak > 0) {
      breaks.add(i);
      contentSinceBreak = 0;
    }
    if (!rule) contentSinceBreak++;
  }
  return breaks;
}

/// De blokken die een kop zijn, als index in dezelfde lijst als
/// [DocumentMarkdownView.blockTexts].
///
/// De paginaverdeling houdt ze vast aan de tekst eronder: een kop hoort niet
/// alleen onderaan een vel achter te blijven (zie `documentPageOffsets`).
Set<int> documentHeadingBlocks(String markdown) {
  final blocks = DocumentMarkdownView._parse(markdown);
  return {
    for (var i = 0; i < blocks.length; i++)
      if (blocks[i].kind == _Kind.heading) i,
  };
}

/// De voetnoten als genummerde lijst, met een scheiding erboven.
///
/// Eén tekenaar voor twee plekken: achterin een doorlopende weergave, en
/// onderaan het vel in de Pagina's-stand. Zou elk van die twee zijn eigen
/// noten tekenen, dan zouden ze uiteenlopen in maat en marge — en juist bij een
/// noot valt dat op, want hij staat naast de tekst waar hij bij hoort.
Widget _footnoteList(
  BuildContext context,
  _Theme t,
  List<Footnote> notes, {
  Key? key,
}) {
  final style = t.body.copyWith(
    // Kleiner dan de bodytekst: een noot is een terzijde, en op papier is dat
    // al eeuwen hoe je dat laat zien.
    fontSize: t.bodyFontSize * 0.82,
    height: 1.35,
  );
  return Padding(
    key: key,
    padding: const EdgeInsets.only(top: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Geen volle streep over de breedte: dat is de klassieke voetnootlijn,
        // en een streep van rand tot rand leest als een scheiding in de tekst.
        SizedBox(
          width: 140,
          child: Divider(height: 1, thickness: 1, color: t.border),
        ),
        const SizedBox(height: 6),
        for (final note in notes)
          Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 22,
                  child: Text(
                    '${note.number}',
                    style: style.copyWith(
                      color: t.marker,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
                Expanded(
                  child: InlineMarkdownText(
                    note.text,
                    style: style,
                    linkColor: t.link,
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

/// De voetnoten van een document als los tekenbaar blok, in dezelfde maat en
/// stijl als waarin ze achterin een doorlopende weergave staan.
///
/// Bestaat voor de vellenweergave: die zet de noten onderaan het blad waar de
/// verwijzing staat, en moet ze dus zelf kunnen uitmeten en tekenen. Zonder dit
/// venster zou zij haar eigen notenlijst bouwen — en dan ziet dezelfde noot op
/// papier er anders uit dan op het scherm.
class DocumentFootnotesView extends StatelessWidget {
  const DocumentFootnotesView({
    super.key,
    required this.notes,
    this.themeProfile,
  });

  final List<Footnote> notes;
  final ThemeProfile? themeProfile;

  @override
  Widget build(BuildContext context) =>
      _footnoteList(context, _Theme(Theme.of(context), themeProfile), notes);
}

/// De lettergrootte van een kop op niveau [level], bij een bodytekst van
/// [bodyFontSize] beeldpunten.
///
/// De vijf maten hieronder gelden bij de standaardmaat; een documentstijl die
/// een andere bodytekst kiest schaalt ze mee met dezelfde verhouding. Zouden de
/// koppen vaste maten houden, dan zou een grotere bodytekst zijn eigen kop
/// inhalen.
double documentHeadingSize(
  int level, {
  double bodyFontSize = kDocumentBodyFontSize,
}) {
  final base = switch (level) {
    1 => 27.0,
    2 => 22.0,
    3 => 18.5,
    4 => 16.0,
    _ => 14.5,
  };
  return base * (bodyFontSize / kDocumentBodyFontSize);
}

class _Theme {
  _Theme(
    ThemeData theme,
    ThemeProfile? profile, {
    this.footnoteNumbers = const {},
  }) : dark = theme.brightness == Brightness.dark,
       bodyFontSize = documentBodyFontSizeToCssPx(
         profile?.documentBodyFontSize ?? kDocumentBodyFontSize,
       ),
       paper = _profileColor(
         profile?.slideBackgroundColor,
         theme.colorScheme.surface,
       ),
       body = TextStyle(
         fontFamily: profile?.fontFamily,
         fontSize: documentBodyFontSizeToCssPx(
           profile?.documentBodyFontSize ?? kDocumentBodyFontSize,
         ),
         height: kDocumentBodyLineHeight,
         color: _profileColor(profile?.textColor, theme.colorScheme.onSurface),
       ),
       heading = _profileColor(
         profile?.effectiveDocumentHeadingColor,
         theme.colorScheme.onSurface,
       ),
       subheading = _profileColor(
         profile?.effectiveDocumentSubheadingColor,
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
       // Inline `code` krijgt géén codeblok-kleur, maar een tint van de
       // tekstkleur — zie [AppTheme.inlineCodeBackground].
       inlineCodeBg = AppTheme.inlineCodeBackground(
         _profileColor(profile?.textColor, theme.colorScheme.onSurface),
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

  /// De basislettergrootte van dit document. Alles wat zich naar de bodytekst
  /// verhoudt — koppen, noten, de tijdstempel van een tijdlijn — rekent hiermee
  /// in plaats van met de vaste standaardmaat.
  final double bodyFontSize;

  /// Label → volgnummer van de voetnoten van dit document; leeg wanneer er geen
  /// zijn. Hoort hier omdat dit het enige object is dat per opbouw één keer
  /// wordt gemaakt en overal langskomt — de noten opnieuw ontleden bij elke
  /// alinea zou het document per blok nog eens doorlopen.
  final Map<String, int> footnoteNumbers;

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

  /// Het vlakje achter een inline `code`-stuk. Los van [codeBg]: dat is het
  /// paneel van een codeblok, en dat is midden in een alinea onleesbaar.
  final Color inlineCodeBg;

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

// ── Line classification helpers ───────────────────────────────────────────

int _headingLevel(String trimmed) {
  var n = 0;
  while (n < trimmed.length && trimmed[n] == '#') {
    n++;
  }
  // A real ATX heading needs a space after the hashes and at most six.
  if (n >= 1 && n <= 6 && n < trimmed.length && trimmed[n] == ' ') return n;
  return 0;
}

bool _isHorizontalRule(String trimmed) {
  return RegExp(
    r'^(-{3,}|\*{3,}|_{3,})$',
  ).hasMatch(trimmed.replaceAll(' ', ''));
}

/// Of [line] een Setext-onderstreping is: `=`+ voor H1, `-`+ voor H2.
/// De aanroeper garandeert dat de regel direct op een tekstregel volgt
/// (geen lege regel ertussen) — dat onderscheidt een Setext-kop van een
/// horizontale streep (#1647).
bool _isSetextUnderline(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return false;
  return RegExp(r'^=+$').hasMatch(trimmed) || RegExp(r'^-+$').hasMatch(trimmed);
}

_ListLine? _listItem(String line) {
  final m = RegExp(r'^(\s*)([-*+]|\d+\.)\s+(.*)$').firstMatch(line);
  if (m == null) return null;
  final indent = m.group(1)!.length;
  final bullet = m.group(2)!;
  final ordered = bullet.endsWith('.');
  var text = m.group(3)!;

  // GFM task item: the content starts with `[ ]` or `[x]`. Strip the marker
  // so it becomes a rendered box instead of literal brackets in the text.
  // Without this the reader showed documentation checklists as "• [ ] item".
  bool? checked;
  final task = RegExp(r'^\[([ xX])\]\s+(.*)$').firstMatch(text);
  if (task != null) {
    checked = task.group(1)! != ' ';
    text = task.group(2)!;
  }

  return _ListLine(
    text: text,
    ordered: ordered,
    number: ordered
        ? int.tryParse(bullet.substring(0, bullet.length - 1)) ?? 1
        : 0,
    depth: indent ~/ 2,
    checked: checked,
  );
}

bool _isParagraphLine(String line) {
  final trimmed = line.trim();
  if (trimmed.isEmpty) return false;
  if (_headingLevel(trimmed) > 0) return false;
  if (markdownFenceOpen(trimmed) != null) return false;
  if (_isHorizontalRule(trimmed)) return false;
  if (trimmed.startsWith('>')) return false;
  if (_listItem(line) != null) return false;
  if (isMarkdownTableLine(line)) return false;
  return true;
}

/// Herkent een regel die precies één markdown-afbeelding is: `![alt](bron)`,
/// optioneel met een titel (`bron "titel"`). De alt mag leeg zijn; de bron moet
/// er zijn. Dezelfde syntaxis als `MarkdownImageSyntax` (image_embed_syntax),
/// zodat de lezer en het schrijfvlak dezelfde afbeelding herkennen.
///
/// Ondersteunt angle-bracket-bestemmingen `<path met spaties>` en ontsnapte
/// haakjes `path\(1\).png`, zodat bestandsnamen met haakjes of spaties niet
/// op de eerste `)` of whitespace afkappen.
({String alt, String source})? _parseImageLine(String line) {
  final match = _imageLinePattern.firstMatch(line);
  if (match == null) return null;
  final alt = match.group(1) ?? '';
  final raw = (match.group(2) ?? '').trim();
  if (raw.isEmpty) return null;
  final source = _extractImageSource(raw);
  if (source.isEmpty) return null;
  return (alt: alt, source: source);
}

/// Haalt de bron uit de inhoud van `](…)`: angle-bracket, ontsnapte haakjes
/// en een optionele `"titel"` achteraan.
String _extractImageSource(String raw) {
  // Angle-bracket: `<…>` — alles tussen de haken is de bron.
  if (raw.startsWith('<')) {
    final close = raw.indexOf('>');
    if (close < 0) return raw.substring(1);
    return raw.substring(1, close);
  }
  // Titels staan tussen aanhalingstekens achteraan: `bron "titel"`.
  final titleMatch = RegExp(r'\s+"[^"]*"\s*$').firstMatch(raw);
  final withoutTitle = titleMatch != null
      ? raw.substring(0, titleMatch.start).trim()
      : raw;
  // Ontsnapte haakjes tellen mee, niet als afsluiting.
  return withoutTitle.replaceAll(r'\(', '(').replaceAll(r'\)', ')');
}

final RegExp _imageLinePattern = RegExp(r'^!\[([^\]]*)\]\((.+)\)$');
