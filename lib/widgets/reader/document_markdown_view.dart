import 'package:flutter/material.dart';

import '../slides/inline_markdown.dart';

/// Renders a full Markdown document as widgets — headings, paragraphs, bullet
/// and numbered lists, block quotes, fenced code, horizontal rules and GFM pipe
/// tables. Inline formatting (bold/italic/code/links) reuses the slide
/// renderer's [InlineMarkdownText], which manages its own link recognisers.
///
/// This is a pragmatic reader, not a full CommonMark engine: it covers what the
/// bundled documentation uses. Anything it doesn't recognise falls back to a
/// paragraph, so unknown syntax is shown as readable text rather than dropped.
///
/// Typography is theme-driven (so it follows light/dark mode) and uses logical
/// font sizes, which Flutter scales with the OS text-size setting for
/// accessibility. The caller is expected to bound the line length (see
/// DocumentReaderScreen) — long measure hurts readability.
class DocumentMarkdownView extends StatelessWidget {
  const DocumentMarkdownView(this.markdown, {super.key, this.onTapLink});

  final String markdown;
  final void Function(String url)? onTapLink;

  @override
  Widget build(BuildContext context) {
    final t = _Theme(Theme.of(context));
    final lines = markdown.replaceAll('\r\n', '\n').split('\n');
    final blocks = <Widget>[];

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.isEmpty) {
        i++;
        continue;
      }

      // Fenced code block: ``` … ``` (or ~~~).
      final fence = _fenceMarker(trimmed);
      if (fence != null) {
        final start = i + 1;
        var end = start;
        while (end < lines.length && lines[end].trim() != fence) {
          end++;
        }
        blocks.add(_codeBlock(t, lines.sublist(start, end).join('\n')));
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
        blocks.add(_table(t, rows));
        i = j;
        continue;
      }

      // Horizontal rule: ---, *** or ___ (three or more).
      if (_isHorizontalRule(trimmed)) {
        blocks.add(_rule(t));
        i++;
        continue;
      }

      // ATX heading: # … ######.
      final heading = _headingLevel(trimmed);
      if (heading > 0) {
        blocks.add(_heading(t, heading, trimmed.substring(heading).trim()));
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
        blocks.add(_blockQuote(t, quote.join('\n')));
        continue;
      }

      // List (bulleted or numbered): consecutive item lines, indent = nesting.
      if (_listItem(line) != null) {
        final items = <_ListLine>[];
        while (i < lines.length && _listItem(lines[i]) != null) {
          items.add(_listItem(lines[i])!);
          i++;
        }
        blocks.add(_list(t, items));
        continue;
      }

      // Paragraph: gather consecutive lines until a blank line or a block start.
      final para = <String>[];
      while (i < lines.length && _isParagraphLine(lines[i])) {
        para.add(lines[i].trim());
        i++;
      }
      blocks.add(_paragraph(t, para.join(' ')));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks,
    );
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
    final marker = it.ordered ? '${it.number}.' : '•';
    return Padding(
      padding: EdgeInsets.only(left: 4 + it.depth * 20.0, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: it.ordered ? 24 : 18,
            child: Text(
              marker,
              style: t.body.copyWith(
                fontWeight: it.ordered ? FontWeight.w600 : FontWeight.w400,
                color: it.ordered ? t.body.color : t.marker,
              ),
            ),
          ),
          Expanded(child: _inline(it.text, t.body, t)),
        ],
      ),
    );
  }

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
    return _ListLine(
      text: m.group(3)!,
      ordered: ordered,
      number: ordered
          ? int.tryParse(bullet.substring(0, bullet.length - 1)) ?? 1
          : 0,
      depth: indent ~/ 2,
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

/// One parsed list line with its nesting depth and (for ordered lists) number.
class _ListLine {
  const _ListLine({
    required this.text,
    required this.ordered,
    required this.number,
    required this.depth,
  });

  final String text;
  final bool ordered;
  final int number;
  final int depth;
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
      marker = theme.colorScheme.primary,
      link = theme.colorScheme.primary,
      border = theme.colorScheme.outlineVariant,
      quoteBg = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.5,
      ),
      quoteBar = theme.colorScheme.primary,
      quoteText = theme.colorScheme.onSurfaceVariant,
      codeBg = theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
      codeText = theme.colorScheme.onSurface,
      tableHeaderBg = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.7,
      );

  final TextStyle body;
  final Color heading;
  final Color marker;
  final Color link;
  final Color border;
  final Color quoteBg;
  final Color quoteBar;
  final Color quoteText;
  final Color codeBg;
  final Color codeText;
  final Color tableHeaderBg;
}
