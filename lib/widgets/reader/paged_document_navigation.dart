part of 'paged_document_view.dart';

/// Gebruik de bestaande blokmeting: een ankersprong hoeft het document niet
/// opnieuw op te bouwen, te meten of van een GlobalKey per kop te voorzien.
extension _PagedDocumentNavigation on _PagedDocumentViewState {
  void _followPageLink(String href) {
    final target = href.trim();
    if (target.isEmpty) return;
    if (!target.startsWith('#')) {
      openExternalUrl(target);
      return;
    }
    final String slug;
    try {
      slug = Uri.decodeComponent(target.substring(1));
    } on FormatException {
      return;
    } on ArgumentError {
      return;
    }
    final block = DocumentMarkdownView.headingBlockIndex(widget.markdown, slug);
    _revealPageBlock(block);
  }

  void _queueHeadingReveal() {
    final offset = widget.revealMarkdownOffset;
    final signal = widget.revealSignal;
    if (offset == null || signal == _handledRevealSignal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          widget.revealSignal != signal ||
          _handledRevealSignal == signal) {
        return;
      }
      if (_blockHeights == null || _pageOffsets.isEmpty) return;
      final outline = buildMarkdownOutline(widget.markdown);
      final selected = outline.where((entry) => entry.offset == offset);
      if (selected.isEmpty) {
        _handledRevealSignal = signal;
        return;
      }
      final slug = headingSlug(selected.first.title);
      final occurrence = outline
          .takeWhile((entry) => entry.offset < offset)
          .where((entry) => headingSlug(entry.title) == slug)
          .length;
      final block = DocumentMarkdownView.headingBlockIndex(
        widget.markdown,
        slug,
        occurrence: occurrence,
      );
      if (_revealPageBlock(block)) _handledRevealSignal = signal;
    });
  }

  bool _revealPageBlock(int block) {
    final heights = _blockHeights;
    if (heights == null || _pageOffsets.isEmpty) return false;
    if (block < 0 || block >= heights.length) return false;
    final y = heights.take(block).fold<double>(0, (sum, h) => sum + h);
    final page = _PagedDocumentViewState._pageOf(y, _pageOffsets);
    final pageContext = _pageKeys[page]?.currentContext;
    if (pageContext == null || !_searchScroll.hasClients) return false;
    final render = pageContext.findRenderObject();
    if (render is! RenderBox) return false;
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox) return false;
    final headingTop = render
        .localToGlobal(
          Offset(
            0,
            (_contentTopPx +
                    widget.margins.bleedMm * kPxPerMm +
                    y -
                    _pageOffsets[page]) *
                _pageScale,
          ),
        )
        .dy;
    final viewportTop = viewport.localToGlobal(Offset.zero).dy;
    final position = _searchScroll.position;
    // Direct springen voorkomt dat een verre hoofdstuksprong alle tussen-
    // liggende pagina's tijdens een animatie moet schilderen.
    _searchScroll.jumpTo(
      (position.pixels +
              headingTop -
              viewportTop -
              position.viewportDimension * 0.08)
          .clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    return true;
  }
}

/// Het paginanummer onder het vel; de bovenliggende Semantics draagt het al.
Widget _pageCaption(ThemeData theme, String label) => ExcludeSemantics(
  child: Text(
    label,
    style: theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  ),
);
