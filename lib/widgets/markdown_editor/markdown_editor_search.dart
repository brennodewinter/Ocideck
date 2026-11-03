part of 'markdown_editor.dart';

extension _MarkdownSearchField on _MarkdownNotesEditorState {
  Widget _buildVisualField() {
    final quill = _quillController;
    final scroll = _scrollController;
    if (quill == null || scroll == null) {
      return const SizedBox.shrink();
    }
    final target = DeckSearchTarget.of(context);
    final sourceController = widget.controller;
    final deckMatch =
        sourceController is EditorTextController &&
            target?.matches(sourceController.searchFieldId) == true
        ? target!.match
        : null;
    var query = widget.findQuery;
    var matchIndex = widget.findMatchIndex;
    var signal = widget.findSelectionSignal;
    if (deckMatch != null) {
      final projection = VisibleMarkdownText(sourceController.text);
      query = projection.text.substring(
        projection.visibleOffsetOf(deckMatch.range.start),
        projection.visibleOffsetOf(deckMatch.range.end),
      );
      matchIndex = findVisibleMarkdownMatches(
        sourceController.text,
        query,
      ).indexWhere((range) => range.start == deckMatch.range.start);
      signal = target!.signal;
    }
    return DocumentSearchOverlay(
      query: query,
      activeIndex: matchIndex,
      caseSensitive: widget.findCaseSensitive,
      revealSignal: signal,
      onActiveRect: (rect) {
        if (rect == null ||
            signal == _visualFindRevealedSignal ||
            !scroll.hasClients) {
          return;
        }
        _visualFindRevealedSignal = signal;
        final target =
            (scroll.offset + rect.top - scroll.position.viewportDimension / 2)
                .clamp(0.0, scroll.position.maxScrollExtent);
        scroll.jumpTo(target);
      },
      child: WysiwygNotesField(
        controller: quill,
        scrollController: scroll,
        focusNode: _focusNode,
        editorTheme: widget.editorTheme,
        hintText: widget.hintText,
        expand: widget.expand,
        contentPadding: widget.contentPadding,
        bordered: _fieldBordered,
        tryConsumePaste: widget.tryConsumePaste,
        editorKey: widget.editorKey,
        onDiscreteVisualEdit: widget.onDiscreteVisualEdit,
        onTapLink: widget.onTapLink,
      ),
    );
  }
}
