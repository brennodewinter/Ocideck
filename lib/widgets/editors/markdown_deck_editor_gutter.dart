part of 'markdown_deck_editor.dart';

/// De kantlijn en de bevindingsbanden van de markdown-editor.
///
/// Een `part` en geen los widget-bestand: deze klassen leunen op de private
/// regelhoogte `_MarkdownDeckEditorState._lineHeight`, zodat de nummers, de
/// gekleurde banden en de tekst tot op de pixel gelijk lopen. Ze uit de
/// bibliotheek trekken zou die maat publiek moeten maken voor niets. Ze staan
/// hier apart omdat het hoofdbestand tegen de regellimiet aan zat en dit een
/// samenhangend, op zichzelf staand blok is: de linkerkolom van de editor.

/// Paints a full-width coloured band (plus a stronger left accent bar) behind
/// every line that carries a validation issue, so findings are visible in the
/// code itself — red for errors, amber for warnings — not only in the gutter.
/// It scrolls in lock-step with the text via [scrollController].
class _IssueHighlightLayer extends StatelessWidget {
  final ScrollController scrollController;
  final Map<int, MarkdownValidationSeverity> issueLines;
  final double topPadding;

  const _IssueHighlightLayer({
    required this.scrollController,
    required this.issueLines,
    required this.topPadding,
  });

  @override
  Widget build(BuildContext context) {
    if (issueLines.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: ClipRect(
        child: AnimatedBuilder(
          animation: scrollController,
          builder: (context, _) {
            final offset = scrollController.hasClients
                ? scrollController.offset
                : 0.0;
            return CustomPaint(
              painter: _IssueHighlightPainter(
                issueLines: issueLines,
                lineHeight: _MarkdownDeckEditorState._lineHeight,
                topPadding: topPadding,
                scrollOffset: offset,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _IssueHighlightPainter extends CustomPainter {
  final Map<int, MarkdownValidationSeverity> issueLines;
  final double lineHeight;
  final double topPadding;
  final double scrollOffset;

  _IssueHighlightPainter({
    required this.issueLines,
    required this.lineHeight,
    required this.topPadding,
    required this.scrollOffset,
  });

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in issueLines.entries) {
      final (band, accent) = switch (entry.value) {
        MarkdownValidationSeverity.error => (
          AppTheme.dangerBgSoft,
          AppTheme.dangerFg,
        ),
        MarkdownValidationSeverity.warning => (
          AppTheme.warningBgSoft,
          AppTheme.warningFg,
        ),
        MarkdownValidationSeverity.informational => (
          AppTheme.slate200,
          AppTheme.slate400,
        ),
      };
      final top = topPadding + (entry.key - 1) * lineHeight - scrollOffset;
      if (top + lineHeight < 0 || top > size.height) continue;
      canvas.drawRect(
        Rect.fromLTWH(0, top, size.width, lineHeight),
        Paint()..color = band,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, top, 3, lineHeight),
        Paint()..color = accent,
      );
    }
  }

  @override
  bool shouldRepaint(_IssueHighlightPainter old) =>
      old.scrollOffset != scrollOffset ||
      old.topPadding != topPadding ||
      old.lineHeight != lineHeight ||
      !mapEquals(old.issueLines, issueLines);
}

class _LineNumberGutter extends StatelessWidget {
  final ScrollController scrollController;
  final int lineCount;
  final Map<int, MarkdownValidationSeverity> issueLines;
  final ValueChanged<int> onLineTap;

  const _LineNumberGutter({
    required this.scrollController,
    required this.lineCount,
    required this.issueLines,
    required this.onLineTap,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppTheme.iceBlue2,
      child: SizedBox(
        width: 44,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: scrollController,
            builder: (context, child) {
              final offset = scrollController.hasClients
                  ? scrollController.offset
                  : 0.0;
              return Transform.translate(
                offset: Offset(0, 16 - offset),
                child: child,
              );
            },
            child: OverflowBox(
              alignment: Alignment.topCenter,
              maxWidth: 44,
              minWidth: 44,
              maxHeight: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var index = 0; index < lineCount; index++)
                    _LineNumberCell(
                      line: index + 1,
                      severity: issueLines[index + 1],
                      onTap: onLineTap,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LineNumberCell extends StatelessWidget {
  final int line;
  final MarkdownValidationSeverity? severity;
  final ValueChanged<int> onTap;

  const _LineNumberCell({
    required this.line,
    required this.severity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bg = switch (severity) {
      MarkdownValidationSeverity.error => AppTheme.dangerBgSoft,
      MarkdownValidationSeverity.warning => AppTheme.warningBgSoft,
      MarkdownValidationSeverity.informational => AppTheme.slate200,
      null => Colors.transparent,
    };
    return GestureDetector(
      onTap: () => onTap(line),
      child: Container(
        height: _MarkdownDeckEditorState._lineHeight,
        color: bg,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 8),
        child: Text(
          '$line',
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.5,
            color: severity == MarkdownValidationSeverity.error
                ? AppTheme.dangerFg
                : severity == MarkdownValidationSeverity.warning
                ? AppTheme.warningFg
                : AppTheme.slate400,
          ),
        ),
      ),
    );
  }
}
