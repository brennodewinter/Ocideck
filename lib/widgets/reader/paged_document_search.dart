part of 'paged_document_view.dart';

extension _PagedDocumentSearch on _PagedDocumentViewState {
  void _revealSearch(List<double> offsets, double fit) {
    final rect = _searchRect;
    if (widget.searchRevealSignal == 0 ||
        rect == null ||
        !_searchScroll.hasClients ||
        _revealedSignal == widget.searchRevealSignal) {
      return;
    }
    _revealedSignal = widget.searchRevealSignal;
    final page = _PagedDocumentViewState._pageOf(rect.top, offsets);
    final scale = widget.scale * fit;
    final (_, sheetHeight) = _sheetPx;
    final top =
        16 +
        page * (sheetHeight * scale + 34) +
        (_contentTopPx + rect.top - offsets[page]) * scale;
    final target = (top - _searchScroll.position.viewportDimension / 2).clamp(
      0.0,
      _searchScroll.position.maxScrollExtent,
    );
    _searchScroll.jumpTo(target);
  }
}
