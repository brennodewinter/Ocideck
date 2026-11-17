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
      final anchors = HeadingAnchorIndex(outline.map((e) => e.title));
      final ordinal = outline.indexOf(selected.first);
      final block = DocumentMarkdownView.headingBlockIndex(
        widget.markdown,
        anchors.entries[ordinal].id,
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
    return _jumpToPage(page, y - _pageOffsets[page]);
  }

  bool _jumpToPage(int page, double withinPage) {
    if (!_searchScroll.hasClients ||
        _pageStride <= 0 ||
        !_searchScroll.position.hasContentDimensions)
      return false;
    final position = _searchScroll.position;
    // Een doel hoeft niet gemonteerd te zijn: de vaste velmaat en de gedeelde
    // blokmeting bepalen zijn scrollpositie rechtstreeks.
    final target =
        16 +
        page * _pageStride +
        (_contentTopPx + widget.margins.bleedMm * kPxPerMm + withinPage) *
            _pageScale -
        position.viewportDimension * 0.08;
    _searchScroll.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    return true;
  }
}

/// De vaste itemmaat omvat ook het bijschrift op de actieve tekstschaal.
double _pageCaptionHeight(BuildContext context) {
  final painter = TextPainter(
    text: TextSpan(
      text: context.l10n.d('Pagina {n} van {m}'),
      style: Theme.of(context).textTheme.labelSmall,
    ),
    locale: Localizations.localeOf(context),
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final height = painter.height;
  painter.dispose();
  return height;
}

/// Het paginanummer onder het vel; de bovenliggende Semantics draagt het al.
Widget _pageCaption(ThemeData theme, String label) => ExcludeSemantics(
  child: Text(
    label,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    ),
  ),
);
