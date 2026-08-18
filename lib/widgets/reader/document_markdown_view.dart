import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chart.dart';
import '../../models/settings.dart' show ThemeProfile, TableBorderStyle;
import '../../models/slide.dart' show TableAlign;
import '../../services/marp_html_service.dart';
import '../../services/markdown_table_codec.dart';
import '../../services/table_layout_metrics.dart';
import '../../services/table_of_contents.dart';
import '../../theme/app_theme.dart';
import '../../utils/doc_link.dart' show headingSlug;
import '../slides/inline_markdown.dart';
import '../slides/mermaid_diagram.dart' show MermaidRenderer;
import 'doc_mermaid_view.dart';
import 'table_edit_controller.dart';
import 'table_edit_scaffold.dart';
import 'table_editable_cell.dart';

part 'parts/document_markdown_blocks.dart';
part 'parts/document_markdown_table.dart';

/// Renders a full Markdown document as widgets — headings, paragraphs, bullet
/// and numbered lists, GFM task lists, block quotes, fenced code, ```mermaid
/// diagrams, horizontal rules and GFM pipe tables. Inline formatting
/// (bold/italic/code/links) reuses the slide renderer's [InlineMarkdownText],
/// which manages its own link recognisers.
///
/// This is a pragmatic reader, not a full CommonMark engine: it covers what the
/// bundled documentation uses. Anything it doesn't recognise falls back to a
/// paragraph, so unknown syntax is shown as readable text rather than dropped.
///
/// Typography is theme-driven (so it follows light/dark mode) and uses logical
/// font sizes, which Flutter scales with the OS text-size setting for
/// accessibility.
///
/// Prose (paragraphs, headings, lists, quotes, rules) is bounded to
/// [maxTextWidth] so the line length stays readable even in a wide window, while
/// tables, code blocks and diagrams are left unbounded: they use the full width
/// they are given (and scroll horizontally beyond it), so wide tables and
/// flowcharts are no longer squeezed into a narrow column. Pass `null` to bound
/// nothing.
///
/// Find-in-page: parsing is separated from rendering ([blockTexts] exposes the
/// searchable text of each block in render order), so the reader can locate the
/// block that holds a search term, drive next/previous, and — via
/// [activeMatchBlockIndex] and [activeMatchKey] — scroll it into view. Blocks
/// whose text contains [searchTerm] are tinted; the active one is tinted more
/// strongly and carries the key the reader scrolls to.
class DocumentMarkdownView extends StatelessWidget {
  const DocumentMarkdownView(
    this.markdown, {
    super.key,
    this.onTapLink,
    this.maxTextWidth,
    this.mermaidRenderer,
    this.chartTheme,
    this.themeProfile,
    this.onEditChart,
    this.onEditTable,
    this.tableEditController,
    this.tableEditOrdinal = 0,
    this.hideRules = false,
    this.searchTerm,
    this.activeMatchBlockIndex = -1,
    this.activeMatchKey,
    this.anchorBlockIndex = -1,
    this.anchorKey,
    this.tocSource,
    this.blockWrapper,
  });

  final String markdown;

  /// De markdown waaruit de inhoudsopgave-voorbeeldweergave haar koppen haalt,
  /// wanneer dat een ándere tekst is dan [markdown]. De visuele editor tekent de
  /// marker als los embed-blok; die kent de koppen van het document niet, en
  /// geeft ze hier mee. `null` → de koppen komen uit [markdown] zelf, zoals in
  /// de lezer.
  final String? tocSource;

  /// Haakje om elk blok, in renderervolgorde. De pagina-weergave gebruikt het
  /// om de hoogte van elk blok op te nemen: pagina-einden mogen alleen tussen
  /// blokken vallen, dus moet iemand weten waar die grenzen liggen — en dan
  /// gemeten aan de echte render, niet geschat. `null` → de boom is exact die
  /// van een gewone lezer.
  final Widget Function(int index, Widget block)? blockWrapper;
  final void Function(String url)? onTapLink;

  /// Absolute block index the reader wants to scroll an `#anchor` link to (from
  /// [headingBlockIndex]), or `-1` for none. That block carries [anchorKey] so
  /// the reader can `ensureVisible` it — the same single-moving-key trick the
  /// find-in-page scroll uses, which is why it stays attached reliably.
  final int anchorBlockIndex;

  /// Attached to the [anchorBlockIndex] block so the reader can scroll to it.
  final GlobalKey? anchorKey;

  /// Maximum measure for prose blocks; tables and code ignore it. `null` leaves
  /// prose unbounded too (the whole document then fills the available width).
  final double? maxTextWidth;

  /// Injectable Mermaid renderer for ```mermaid fences; defaults (via
  /// [DocMermaidView]) to the shared render service. Tests pass a fake so the
  /// diagram path can be exercised without a WebView.
  final MermaidRenderer? mermaidRenderer;

  /// Stijlprofiel voor de kleuren van een ```chart-blok. `null` → de
  /// standaardkleuren van de grafiek-SVG. Een document heeft geen deck-thema, dus
  /// de aanroeper geeft hier het actieve app-profiel of niets.
  final ThemeProfile? chartTheme;

  final ThemeProfile? themeProfile;

  /// Aangeroepen bij dubbelklik op een grafiek — alleen in de editor gezet (de
  /// docs-lezer is alleen-lezen). Geeft het volgnummer van de grafiek (de
  /// hoeveelheidste ```chart in het document, vanaf 0) en de blokinhoud mee, zodat
  /// de editor de juiste fence in de bron kan vervangen. `null` → geen bewerking.
  final void Function(int chartOrdinal, String chartBlock)? onEditChart;

  /// Aangeroepen bij dubbelklik op een tabel — alleen in de editor gezet. Geeft
  /// het volgnummer van de tabel (de hoeveelheidste GFM-tabel in het document,
  /// vanaf 0) en de rauwe regels (koprij + body, zónder scheidingsrij) mee, zodat
  /// de editor precies dat tabelblok in de bron kan vervangen. `null` → geen
  /// bewerking.
  final void Function(int tableOrdinal, List<String> tableRows)? onEditTable;

  /// Maakt de tabel ter plekke invulbaar: elke cel wordt een tekstveld binnen
  /// dezelfde gerenderde tabel, zodat je typt in de vorm die je krijgt — de
  /// kolomverdeling, randen en huisstijl zijn per definitie die van de gelezen
  /// tabel, want het is dezelfde tekenaar. `null` → de tabel is alleen-lezen.
  ///
  /// Geldt voor de tabel met volgnummer [tableEditOrdinal]; de overige tabellen
  /// in hetzelfde document blijven gewoon gerenderd.
  final TableEditController? tableEditController;
  final int tableEditOrdinal;

  /// Tekent een `---` niet als streep.
  ///
  /// In de pagina-weergave *is* een `---` het pagina-einde (FILE_FORMAT.md
  /// §14.6). Hem dan óók als lijn tekenen levert een vers vel op dat opent met
  /// een streep boven de kop — een pagina-einde hoort geen inkt achter te
  /// laten. In de lezer blijft hij gewoon een horizontale lijn.
  final bool hideRules;

  /// Case-insensitive find-in-page term. When non-empty, every block whose text
  /// contains it is tinted. `null`/empty means no search is active and the tree
  /// is identical to the plain document (no wrappers), so non-search callers are
  /// unaffected.
  final String? searchTerm;

  /// Absolute index (into [blockTexts]/the block list) of the block that is the
  /// current find-in-page hit, or `-1` for none. That block is tinted more
  /// strongly and carries [activeMatchKey].
  final int activeMatchBlockIndex;

  /// Attached to the active-match block so the reader can `ensureVisible` it.
  final GlobalKey? activeMatchKey;

  /// The searchable plain text of each block, in the same order [build] renders
  /// them. The reader uses this to find which blocks contain a term and to map a
  /// match ordinal to an absolute block index — sharing this one parser with
  /// [build] keeps the indices aligned.
  static List<String> blockTexts(String markdown) =>
      _parse(markdown).map((b) => b.searchText).toList(growable: false);

  /// De blokken die op een verse pagina horen te beginnen, als index in
  /// dezelfde lijst als [blockTexts].
  ///
  /// Twee soorten, allebei uit het formaat en allebei gehonoreerd door de HTML-
  /// en LaTeX-export (FILE_FORMAT.md §14.6): een `---` in de body ís een
  /// pagina-einde, en met [chapterBreak] begint elk hoofdstuk (`H1`) op een
  /// nieuw vel. Het eerste blok telt nooit mee — een breuk vóór de eerste regel
  /// zou een leeg vel opleveren.
  static Set<int> forcedPageBreaks(
    String markdown, {
    bool chapterBreak = false,
  }) {
    final blocks = _parse(markdown);
    final breaks = <int>{};
    // Wat er sinds de vorige breuk aan échte inhoud staat. Een `---` telt niet
    // mee: in een paginaweergave ís hij het einde zelf, geen inhoud.
    var contentSinceBreak = 0;
    for (var i = 0; i < blocks.length; i++) {
      final rule = blocks[i].kind == _Kind.rule;
      final chapter =
          chapterBreak &&
          blocks[i].kind == _Kind.heading &&
          blocks[i].level == 1;
      if ((rule || chapter) && contentSinceBreak > 0) {
        breaks.add(i);
        contentSinceBreak = 0;
      }
      if (!rule) contentSinceBreak++;
    }
    return breaks;
  }

  /// De blokken die een kop zijn, als index in dezelfde lijst als [blockTexts].
  ///
  /// De paginaverdeling houdt ze vast aan de tekst eronder: een kop hoort niet
  /// alleen onderaan een vel achter te blijven (zie `documentPageOffsets`).
  static Set<int> headingBlocks(String markdown) {
    final blocks = _parse(markdown);
    return {
      for (var i = 0; i < blocks.length; i++)
        if (blocks[i].kind == _Kind.heading) i,
    };
  }

  /// De regelnummers (vanaf 0) van elke hoofdstukkop (`H1`) in [source], geteld
  /// met exact dezelfde grammatica als de weergave: een `#` binnen een fenced
  /// blok is code en telt niet mee, en een kop heeft een spatie na de hekjes.
  /// De editor gebruikt dit om hoofdstukafbrekingen in de bron te zetten zonder
  /// een eigen kop-herkenning naast die van de weergave te bouwen.
  static List<int> chapterHeadingLines(String source) {
    final lines = source.split('\n');
    final headings = <int>[];
    var i = 0;
    while (i < lines.length) {
      final trimmed = lines[i].trim();
      final marker = _fenceMarker(trimmed);
      if (marker != null) {
        var end = i + 1;
        while (end < lines.length && lines[end].trim() != marker) {
          end++;
        }
        i = end < lines.length ? end + 1 : end;
        continue;
      }
      if (_headingLevel(trimmed) == 1) headings.add(i);
      i++;
    }
    return headings;
  }

  /// Of [line] een thematische breuk is (`---`, `***`, `___`) — precies de regel
  /// die de weergave als scheiding tekent en die de export (FILE_FORMAT.md
  /// §14.6) als pagina-einde honoreert. Zegt niets over de context: de beller
  /// moet zelf weten dat de regel buiten een fenced blok staat.
  static bool isThematicBreakLine(String line) =>
      _isHorizontalRule(line.trim());

  /// The absolute block index (into the same block list [build] renders) of the
  /// first heading whose [headingSlug] equals [slug], or `-1` when this document
  /// has no such heading. The reader uses it to point [anchorBlockIndex] at the
  /// section an `#anchor` link names. First match wins, mirroring how the anchor
  /// key attaches to the first heading with a slug.
  static int headingBlockIndex(String markdown, String slug) {
    final blocks = _parse(markdown);
    for (var i = 0; i < blocks.length; i++) {
      final b = blocks[i];
      if (b.kind == _Kind.heading && headingSlug(b.text) == slug) return i;
    }
    return -1;
  }

  /// De regel-reikwijdte `[start, eind)` van het `ordinal`-de GFM-tabelblok
  /// (vanaf 0) in [source] — koprij + scheidingsrij + body — geteld met exact
  /// dezelfde grammatica als de weergave (fenced blokken worden overgeslagen, en
  /// een pipe-regel bereikt altijd de tabelherkenning). `null` als er geen
  /// zoveelste tabel is. De editor gebruikt dit om precies dat blok in de bron te
  /// vervangen zonder de omringende bytes aan te raken.
  static List<int>? nthTableBlockRange(String source, int ordinal) {
    final lines = source.split('\n');
    var seen = 0;
    var i = 0;
    while (i < lines.length) {
      final marker = _fenceMarker(lines[i].trim());
      if (marker != null) {
        var end = i + 1;
        while (end < lines.length && lines[end].trim() != marker) {
          end++;
        }
        i = end < lines.length ? end + 1 : end;
        continue;
      }
      if (isMarkdownTableLine(lines[i]) &&
          i + 1 < lines.length &&
          isMarkdownTableDelimiterRow(lines[i + 1])) {
        var j = i + 2;
        while (j < lines.length && isMarkdownTableLine(lines[j])) {
          j++;
        }
        if (seen == ordinal) return [i, j];
        seen++;
        i = j;
        continue;
      }
      i++;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final t = _Theme(Theme.of(context), themeProfile);
    final blocks = _parse(markdown);
    final term = (searchTerm ?? '').trim().toLowerCase();
    return ColoredBox(
      color: t.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grafieken en tabellen worden elk apart geteld, zodat een dubbelklik het
          // juiste blok (de hoeveelheidste van zíjn soort) in de bron kan vervangen.
          for (var i = 0, chart = 0, table = 0; i < blocks.length; i++)
            _wrapped(
              i,
              _decorated(
                context,
                t,
                blocks[i],
                i,
                term,
                switch (blocks[i].kind) {
                  _Kind.chart => chart++,
                  _Kind.table => table++,
                  _ => -1,
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrapped(int index, Widget block) =>
      blockWrapper?.call(index, block) ?? block;

  /// Wraps a block in a search tint when it matches [term]; the active match
  /// carries [activeMatchKey] and the anchor target carries [anchorKey] so the
  /// reader can scroll to either. With no term and no anchor the block is
  /// returned untouched, so a non-searching, non-navigating reader gets exactly
  /// the old tree.
  Widget _decorated(
    BuildContext context,
    _Theme t,
    _Block b,
    int index,
    String term,
    int kindOrdinal,
  ) {
    var widget = _buildWidget(context, t, b, kindOrdinal);
    // The anchor target carries its own key (one moving key, like the search
    // scroll) so `#anchor` links land on the section.
    if (index == anchorBlockIndex && anchorKey != null) {
      widget = KeyedSubtree(key: anchorKey, child: widget);
    }
    if (term.isEmpty || !b.searchText.toLowerCase().contains(term)) {
      return widget;
    }
    final active = index == activeMatchBlockIndex;
    return Container(
      key: active ? activeMatchKey : null,
      decoration: BoxDecoration(
        color: active ? t.findActive : t.findMatch,
        borderRadius: BorderRadius.circular(4),
      ),
      child: widget,
    );
  }

  Widget _buildWidget(
    BuildContext context,
    _Theme t,
    _Block b,
    int kindOrdinal,
  ) => switch (b.kind) {
    _Kind.heading => _bounded(_heading(t, b.level, b.text)),
    _Kind.paragraph => _bounded(_paragraph(t, b.text)),
    _Kind.list => _bounded(_list(t, b.items)),
    _Kind.quote => _bounded(_blockQuote(t, b.text)),
    _Kind.code => _codeBlock(t, b.text),
    _Kind.mermaid => _mermaid(t, b.text),
    _Kind.chart => _chart(t, b.text, kindOrdinal),
    _Kind.table => _table(t, b.rows, b.aligns, kindOrdinal),
    _Kind.rule => hideRules ? const SizedBox.shrink() : _bounded(_rule(t)),
    _Kind.toc => _bounded(_tocPreview(context, t)),
  };

  /// Feature 4: live preview van de inhoudsopgave. Genereert de TOC uit de
  /// koppen in de huidige body en toont hem als een gestileerde nav-block.
  Widget _tocPreview(BuildContext context, _Theme t) {
    final l10n = context.l10n;
    final toc = generateTocMarkdown(tocSource ?? markdown);
    if (toc.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.quoteBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.border),
        ),
        child: Row(
          children: [
            Icon(Icons.list_outlined, size: 16, color: t.subheading),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                l10n.d(
                  'Inhoudsopgave — voeg koppen toe om de inhoudsopgave te vullen.',
                ),
                style: t.body.copyWith(
                  fontSize: 13,
                  color: t.quoteText,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ],
        ),
      );
    }
    final lines = toc.split('\n');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.quoteBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.list_outlined, size: 16, color: t.subheading),
              const SizedBox(width: 8),
              Text(
                l10n.d('Inhoudsopgave'),
                style: t.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: t.heading,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines) _tocLine(t, line),
        ],
      ),
    );
  }

  Widget _tocLine(_Theme t, String line) {
    final match = RegExp(r'^(\s*)- \[(.*?)\]\(#(.*)\)$').firstMatch(line);
    if (match == null) return const SizedBox.shrink();
    final indent = match.group(1)!.length;
    final text = match.group(2)!;
    return Padding(
      padding: EdgeInsets.only(left: indent * 8.0, top: 2, bottom: 2),
      child: Text(
        text,
        style: t.body.copyWith(
          fontSize: 13,
          color: t.link,
          decoration: TextDecoration.underline,
          decorationColor: t.link.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  /// Keep prose within a readable measure; tables and code blocks skip this and
  /// use the full width available to the document.
  Widget _bounded(Widget child) {
    final max = maxTextWidth;
    if (max == null) return child;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: max),
      child: child,
    );
  }

  // ── Parsing (pure; shared by build and blockTexts) ────────────────────────

  /// Splits [markdown] into ordered block descriptors. Deterministic and free of
  /// any BuildContext, so [build] (widgets) and [blockTexts] (search text) share
  /// one classification and can never drift apart.
  static List<_Block> _parse(String markdown) {
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final blocks = <_Block>[];

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Fenced block: ``` … ``` (or ~~~). The info string after the opening
      // fence selects the renderer: `mermaid` is drawn as a diagram, everything
      // else is a monospace code block.
      final fence = _fenceMarker(trimmed);
      if (fence != null) {
        final lang = trimmed.substring(fence.length).trim().toLowerCase();
        final start = i + 1;
        var end = start;
        while (end < lines.length && lines[end].trim() != fence) {
          end++;
        }
        final code = lines.sublist(start, end).join('\n');
        blocks.add(
          _Block(switch (lang) {
            'mermaid' => _Kind.mermaid,
            'chart' => _Kind.chart,
            _ => _Kind.code,
          }, text: code),
        );
        i = end < lines.length ? end + 1 : end;
        continue;
      }

      // GFM pipe table: a header row followed by a |---|:--:| delimiter row.
      if (isMarkdownTableLine(line) &&
          i + 1 < lines.length &&
          isMarkdownTableDelimiterRow(lines[i + 1])) {
        final rows = <String>[line];
        // De per-kolomuitlijning zit in de scheidingsrij (`:--`, `--:`, `:-:`);
        // die halen we eruit voordat we hem overslaan.
        final aligns = decodeMarkdownTableWithAlignment([
          line,
          lines[i + 1],
        ]).alignments;
        var j = i + 2;
        while (j < lines.length && isMarkdownTableLine(lines[j])) {
          rows.add(lines[j]);
          j++;
        }
        blocks.add(_Block(_Kind.table, rows: rows, aligns: aligns));
        i = j;
        continue;
      }

      // Horizontal rule: ---, *** or ___ (three or more).
      if (_isHorizontalRule(trimmed)) {
        blocks.add(const _Block(_Kind.rule));
        i++;
        continue;
      }

      // Feature 4: TOC-marker `<!-- toc -->` op een eigen regel.
      if (trimmed == '<!-- toc -->') {
        blocks.add(const _Block(_Kind.toc));
        i++;
        continue;
      }

      // ATX heading: # … ######.
      final heading = _headingLevel(trimmed);
      if (heading > 0) {
        blocks.add(
          _Block(
            _Kind.heading,
            level: heading,
            text: trimmed.substring(heading).trim(),
          ),
        );
        i++;
        continue;
      }

      // Block quote: one or more consecutive `> ` lines.
      if (trimmed.startsWith('>')) {
        final quote = <String>[];
        while (i < lines.length && lines[i].trimLeft().startsWith('>')) {
          quote.add(lines[i].trimLeft().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        blocks.add(_Block(_Kind.quote, text: quote.join('\n')));
        continue;
      }

      // List (bulleted or numbered): consecutive item lines, indent = nesting.
      if (_listItem(line) != null) {
        final items = <_ListLine>[];
        while (i < lines.length) {
          final item = _listItem(lines[i]);
          if (item != null) {
            items.add(item);
            i++;
            continue;
          }
          // Een regel die in de bron is afgebroken hoort nog bij het item
          // erboven (CommonMark noemt dat een lazy continuation). Zonder deze
          // tak eindigde de lijst hier en werd de rest van de zin een losse
          // alinea: zonder bolletje, op de linkermarge, met de lijst in tweeën.
          // Een lege regel sluit de lijst wél af, en een regel die zelf een
          // blok begint (kop, streep, citaat, tabel, fence) ook.
          if (items.isEmpty || !_isParagraphLine(lines[i])) break;
          items[items.length - 1] = items.last.continued(lines[i].trim());
          i++;
        }
        blocks.add(_Block(_Kind.list, items: items));
        continue;
      }

      // Paragraph — the fallback for any line no earlier branch consumed. Take
      // the current line UNCONDITIONALLY (advancing i), then gather following
      // paragraph lines. Taking it unconditionally is what makes the fallback
      // real: a line that starts with `|` but is not a valid GFM table (no
      // delimiter row) satisfies no branch above and fails `_isParagraphLine`,
      // so without consuming it here i would never advance — an infinite loop
      // that built empty blocks until the app ran out of memory (it hung the
      // reader on FILE_FORMAT.md and SBOM.md). "Anything it doesn't recognise
      // falls back to a paragraph" only holds if the fallback always advances.
      final para = <String>[lines[i].trim()];
      i++;
      while (i < lines.length && _isParagraphLine(lines[i])) {
        para.add(lines[i].trim());
        i++;
      }
      blocks.add(_Block(_Kind.paragraph, text: para.join(' ')));
    }

    return blocks;
  }

  // ── Block builders ────────────────────────────────────────────────────────

  Widget _heading(_Theme t, int level, String text) {
    final size = documentHeadingSize(level);
    return Padding(
      padding: EdgeInsets.only(
        top: level <= 2 ? kDocumentHeadingGapTop : kDocumentSubheadingGapTop,
        bottom: kDocumentHeadingGapBottom,
      ),
      child: _inline(
        text,
        t.body.copyWith(
          fontSize: size,
          fontWeight: level <= 2 ? FontWeight.w800 : FontWeight.w700,
          height: 1.25,
          color: level == 1 ? t.heading : t.subheading,
        ),
        t,
      ),
    );
  }

  Widget _paragraph(_Theme t, String text) => Padding(
    padding: const EdgeInsets.only(bottom: kDocumentParagraphGap),
    child: _inline(text, t.body, t),
  );

  Widget _list(_Theme t, List<_ListLine> items) {
    // Track a running counter per indent depth so nested ordered lists restart.
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final it in items) _listRow(t, it)],
      ),
    );
  }

  Widget _listRow(_Theme t, _ListLine it) {
    final row = Padding(
      padding: EdgeInsets.only(left: 4 + it.depth * 20.0, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          it.checked == null
              ? _bulletMarker(t, it)
              : _checkMarker(t, checked: it.checked!),
          Expanded(child: _inline(it.text, t.body, t)),
        ],
      ),
    );
    if (it.checked == null) return row;
    // Announce the box as a checkbox with its state, so a screen reader says
    // "checked"/"unchecked" instead of reading out a decorative icon. Using the
    // semantics flag rather than a label keeps this translated by the platform,
    // which is the only way it stays right in all thirty languages.
    return Semantics(checked: it.checked, child: row);
  }

  Widget _bulletMarker(_Theme t, _ListLine it) => SizedBox(
    width: it.ordered ? 24 : 18,
    child: Text(
      it.ordered ? '${it.number}.' : '•',
      style: t.body.copyWith(
        fontWeight: it.ordered ? FontWeight.w600 : FontWeight.w400,
        color: it.ordered ? t.body.color : t.marker,
      ),
    ),
  );

  /// The box of a GFM task item. Read-only on purpose: this renders bundled
  /// documentation shipped as an asset, so a tick here would have nowhere to be
  /// written back to. It reports progress, it does not record it.
  Widget _checkMarker(_Theme t, {required bool checked}) => SizedBox(
    width: 24,
    child: Padding(
      // Nudge the box onto the text baseline; the glyph sits higher than the
      // cap height of the line it labels.
      padding: const EdgeInsets.only(top: 2),
      child: Icon(
        checked ? Icons.check_box_outlined : Icons.check_box_outline_blank,
        size: 17,
        color: checked ? t.checkboxChecked : t.checkboxEmpty,
      ),
    ),
  );

  Widget _blockQuote(_Theme t, String text) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.fromLTRB(14, 8, 12, 8),
    decoration: BoxDecoration(
      color: t.quoteBg,
      border: Border(left: BorderSide(color: t.quoteBar, width: 3)),
      borderRadius: const BorderRadius.only(
        topRight: Radius.circular(6),
        bottomRight: Radius.circular(6),
      ),
    ),
    child: _inline(text, t.body.copyWith(color: t.quoteText), t),
  );

  Widget _codeBlock(_Theme t, String code) => Container(
    width: double.infinity,
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: t.codeBg,
      border: Border.all(color: t.border),
      borderRadius: BorderRadius.circular(8),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SelectableText(
        code,
        style: t.body.copyWith(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
          fontSize: 13.5,
          height: 1.45,
          color: t.codeText,
        ),
      ),
    ),
  );

  /// A ```mermaid fence, drawn as a diagram. Like code blocks it is full-width
  /// (not bounded to the prose measure) so a wide flowchart has room; on a
  /// render failure or under `flutter test` it falls back to the same code block
  /// the source would otherwise have shown.
  Widget _mermaid(_Theme t, String code) => DocMermaidView(
    source: code,
    fallback: _codeBlock(t, code),
    dark: t.dark,
    renderer: mermaidRenderer,
  );

  /// Een ```chart-blok als gerenderde grafiek (statische SVG, dezelfde renderlaag
  /// als de HTML-export). Draagt het blok geen inline cijfers (bv. een
  /// `source:`-verwijzing die nog niet gehydrateerd is), dan valt het terug op
  /// het codeblok — dan zie je tenminste de bron in plaats van een leeg vlak.
  Widget _chart(_Theme t, String block, int chartOrdinal) {
    final spec = ChartSpec.parse(block);
    if (!spec.hasInlineData) return _codeBlock(t, block);
    final chart = Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.codeBg,
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AspectRatio(
        aspectRatio: 800 / 450,
        child: SvgPicture.string(
          MarpHtmlService.chartSpecSvg(
            spec,
            chartTheme ?? themeProfile,
            background: t.chartCardHex,
          ),
          fit: BoxFit.contain,
        ),
      ),
    );
    final onEdit = onEditChart;
    if (onEdit == null) return chart;
    // In de editor: dubbelklik óf het potlood-knopje opent de grafiek-editor.
    return _EditableEmbed(
      onEdit: () => onEdit(chartOrdinal, block),
      child: chart,
    );
  }

  Widget _rule(_Theme t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Divider(height: 1, thickness: 1, color: t.border),
  );

  Widget _inline(
    String text,
    TextStyle style,
    _Theme t, {
    TextAlign textAlign = TextAlign.start,
  }) => InlineMarkdownText(
    text,
    style: style,
    linkColor: t.link,
    onTapLink: onTapLink,
    textAlign: textAlign,
  );
}
