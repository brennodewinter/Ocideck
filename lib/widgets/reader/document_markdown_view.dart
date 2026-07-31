import 'package:flutter/material.dart';

import '../../theme/app_theme.dart';
import '../slides/inline_markdown.dart';
import '../slides/mermaid_diagram.dart' show MermaidRenderer;
import 'doc_mermaid_view.dart';

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
    this.searchTerm,
    this.activeMatchBlockIndex = -1,
    this.activeMatchKey,
  });

  final String markdown;
  final void Function(String url)? onTapLink;

  /// Maximum measure for prose blocks; tables and code ignore it. `null` leaves
  /// prose unbounded too (the whole document then fills the available width).
  final double? maxTextWidth;

  /// Injectable Mermaid renderer for ```mermaid fences; defaults (via
  /// [DocMermaidView]) to the shared render service. Tests pass a fake so the
  /// diagram path can be exercised without a WebView.
  final MermaidRenderer? mermaidRenderer;

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

  @override
  Widget build(BuildContext context) {
    final t = _Theme(Theme.of(context));
    final blocks = _parse(markdown);
    final term = (searchTerm ?? '').trim().toLowerCase();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++)
          _decorated(t, blocks[i], i, term),
      ],
    );
  }

  /// Wraps a block in a search tint when it matches [term]; the active match
  /// also carries [activeMatchKey] so the reader can scroll to it. With no term
  /// the block is returned untouched, so a non-searching reader gets exactly the
  /// old tree.
  Widget _decorated(_Theme t, _Block b, int index, String term) {
    final widget = _buildWidget(t, b);
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

  Widget _buildWidget(_Theme t, _Block b) => switch (b.kind) {
    _Kind.heading => _bounded(_heading(t, b.level, b.text)),
    _Kind.paragraph => _bounded(_paragraph(t, b.text)),
    _Kind.list => _bounded(_list(t, b.items)),
    _Kind.quote => _bounded(_blockQuote(t, b.text)),
    _Kind.code => _codeBlock(t, b.text),
    _Kind.mermaid => _mermaid(t, b.text),
    _Kind.table => _table(t, b.rows),
    _Kind.rule => _bounded(_rule(t)),
  };

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
          _Block(lang == 'mermaid' ? _Kind.mermaid : _Kind.code, text: code),
        );
        i = end < lines.length ? end + 1 : end;
        continue;
      }

      // GFM pipe table: a header row followed by a |---|:--:| delimiter row.
      if (_looksLikeTableRow(line) &&
          i + 1 < lines.length &&
          _isTableDelimiter(lines[i + 1])) {
        final rows = <String>[line];
        var j = i + 2;
        while (j < lines.length && _looksLikeTableRow(lines[j])) {
          rows.add(lines[j]);
          j++;
        }
        blocks.add(_Block(_Kind.table, rows: rows));
        i = j;
        continue;
      }

      // Horizontal rule: ---, *** or ___ (three or more).
      if (_isHorizontalRule(trimmed)) {
        blocks.add(const _Block(_Kind.rule));
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
        while (i < lines.length && _listItem(lines[i]) != null) {
          items.add(_listItem(lines[i])!);
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
    final size = switch (level) {
      1 => 27.0,
      2 => 22.0,
      3 => 18.5,
      4 => 16.0,
      _ => 14.5,
    };
    return Padding(
      padding: EdgeInsets.only(top: level <= 2 ? 26 : 18, bottom: 8),
      child: _inline(
        text,
        t.body.copyWith(
          fontSize: size,
          fontWeight: level <= 2 ? FontWeight.w800 : FontWeight.w700,
          height: 1.25,
          color: t.heading,
        ),
        t,
      ),
    );
  }

  Widget _paragraph(_Theme t, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
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
        color: checked ? t.marker : t.checkboxEmpty,
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
    renderer: mermaidRenderer,
  );

  Widget _rule(_Theme t) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Divider(height: 1, thickness: 1, color: t.border),
  );

  Widget _table(_Theme t, List<String> rows) {
    final cells = rows.map(_splitTableRow).toList();
    final columns = cells.isEmpty
        ? 0
        : cells.map((r) => r.length).reduce((a, b) => a > b ? a : b);
    if (columns == 0) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: t.border),
            borderRadius: BorderRadius.circular(8),
          ),
          clipBehavior: Clip.antiAlias,
          child: Table(
            defaultColumnWidth: const IntrinsicColumnWidth(),
            border: TableBorder.symmetric(inside: BorderSide(color: t.border)),
            children: [
              for (var r = 0; r < cells.length; r++)
                TableRow(
                  decoration: BoxDecoration(
                    color: r == 0 ? t.tableHeaderBg : null,
                  ),
                  children: [
                    for (var c = 0; c < columns; c++)
                      _tableCell(
                        t,
                        c < cells[r].length ? cells[r][c] : '',
                        header: r == 0,
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tableCell(_Theme t, String text, {required bool header}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: _inline(
      text,
      header ? t.body.copyWith(fontWeight: FontWeight.w700) : t.body,
      t,
    ),
  );

  Widget _inline(String text, TextStyle style, _Theme t) => InlineMarkdownText(
    text,
    style: style,
    linkColor: t.link,
    onTapLink: onTapLink,
  );

  // ── Line classification helpers ───────────────────────────────────────────

  static String? _fenceMarker(String trimmed) {
    if (trimmed.startsWith('```')) return '```';
    if (trimmed.startsWith('~~~')) return '~~~';
    return null;
  }

  static int _headingLevel(String trimmed) {
    var n = 0;
    while (n < trimmed.length && trimmed[n] == '#') {
      n++;
    }
    // A real ATX heading needs a space after the hashes and at most six.
    if (n >= 1 && n <= 6 && n < trimmed.length && trimmed[n] == ' ') return n;
    return 0;
  }

  static bool _isHorizontalRule(String trimmed) {
    return RegExp(
      r'^(-{3,}|\*{3,}|_{3,})$',
    ).hasMatch(trimmed.replaceAll(' ', ''));
  }

  static bool _looksLikeTableRow(String line) {
    final t = line.trim();
    return t.contains('|') && t.startsWith('|');
  }

  static bool _isTableDelimiter(String line) {
    final t = line.trim();
    if (!t.contains('-') || !t.contains('|')) return false;
    return RegExp(r'^\|?[\s:|-]+\|?$').hasMatch(t) && t.contains('-');
  }

  static List<String> _splitTableRow(String row) {
    var t = row.trim();
    if (t.startsWith('|')) t = t.substring(1);
    if (t.endsWith('|')) t = t.substring(0, t.length - 1);
    // Split on unescaped pipes.
    final cells = <String>[];
    final buf = StringBuffer();
    for (var i = 0; i < t.length; i++) {
      final c = t[i];
      if (c == r'\' && i + 1 < t.length) {
        buf.write(c);
        buf.write(t[i + 1]);
        i++;
        continue;
      }
      if (c == '|') {
        cells.add(buf.toString().trim());
        buf.clear();
      } else {
        buf.write(c);
      }
    }
    cells.add(buf.toString().trim());
    return cells;
  }

  static _ListLine? _listItem(String line) {
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

  static bool _isParagraphLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return false;
    if (_headingLevel(trimmed) > 0) return false;
    if (_fenceMarker(trimmed) != null) return false;
    if (_isHorizontalRule(trimmed)) return false;
    if (trimmed.startsWith('>')) return false;
    if (_listItem(line) != null) return false;
    if (_looksLikeTableRow(line)) return false;
    return true;
  }
}

/// The kind of a parsed Markdown block.
enum _Kind { heading, paragraph, list, quote, code, mermaid, table, rule }

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
  });

  final _Kind kind;

  /// heading / paragraph / quote / code / mermaid content.
  final String text;

  /// Heading level 1–6 (0 otherwise).
  final int level;

  /// List item lines (for [_Kind.list]).
  final List<_ListLine> items;

  /// Raw table rows including the delimiter row (for [_Kind.table]).
  final List<String> rows;

  /// The plain text a find-in-page query matches against. Rules never match;
  /// tables and lists flatten their cells/items into one searchable string.
  String get searchText => switch (kind) {
    _Kind.table => rows.join(' '),
    _Kind.list => items.map((e) => e.text).join(' '),
    _Kind.rule => '',
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
class _Theme {
  _Theme(ThemeData theme)
    : body = TextStyle(
        fontSize: 15.5,
        height: 1.55,
        color: theme.colorScheme.onSurface,
      ),
      heading = theme.colorScheme.onSurface,
      marker = AppPalette.of(theme).accentInk,
      // Dimmer than the ticked box: an empty box is the absence of a fact, and
      // should not pull the eye harder than the items that are done.
      checkboxEmpty = theme.colorScheme.onSurfaceVariant,
      link = AppPalette.of(theme).accentInk,
      border = theme.colorScheme.outlineVariant,
      quoteBg = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.5,
      ),
      quoteBar = AppPalette.of(theme).accentInk,
      quoteText = theme.colorScheme.onSurfaceVariant,
      codeBg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      codeText = theme.colorScheme.onSurface,
      tableHeaderBg = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.7,
      ),
      // Find-in-page tints. A warm amber, alpha-blended so it reads on both a
      // light and a dark surface; the active hit is stronger than the rest.
      findMatch = const Color(0xFFFFC107).withValues(alpha: 0.22),
      findActive = const Color(0xFFFF9800).withValues(alpha: 0.45);

  final TextStyle body;
  final Color heading;
  final Color marker;
  final Color checkboxEmpty;
  final Color link;
  final Color border;
  final Color quoteBg;
  final Color quoteBar;
  final Color quoteText;
  final Color codeBg;
  final Color codeText;
  final Color tableHeaderBg;
  final Color findMatch;
  final Color findActive;
}
