part of '../document_editor_screen.dart';

/// Zoeken blijft in de actieve weergave en bewerkt geen documentinhoud.
extension _DocumentEditorSearch on _DocumentEditorScreenState {
  Widget _findBar() => MarkdownFindBar(
    key: ValueKey('doc-find-${_find.showReplace}'),
    query: _find.query,
    replace: _find.replacement,
    caseSensitive: _find.caseSensitive,
    showReplace: _find.showReplace,
    matchCount: _find.matchCount,
    matchIndex: _find.matchIndex,
    onQueryChanged: _find.onQueryFieldChanged,
    onReplaceChanged: _find.setReplacement,
    onCaseSensitiveChanged: _find.setCaseSensitive,
    onNext: _find.next,
    onPrevious: _find.previous,
    onReplaceCurrent: _find.replaceCurrent,
    onReplaceAll: _find.replaceAll,
    onClose: () {
      _find.close();
      _editorFocus.requestFocus();
    },
    resultContexts: _searchIndex.contexts(_find),
    onSelectMatch: _find.selectMatch,
    wrapDirection: _find.wrapDirection,
  );

  void _openFind({required bool showReplace}) =>
      _searchIndex.open(showReplace: showReplace);

  /// Spring naar een treffer. In Bron staat de selectie direct op de controller
  /// (met zoekmarkering eromheen); in Visueel leeft de cursor in Quill en
  /// vragen we [MarkdownNotesEditor] via een signaal om hem erheen te verplaatsen.
  void _jumpToMatch(TextMatchRange match) {
    if (_viewMode == _DocViewMode.pages) {
      _rebuild(() => _findSelectionSignal++);
      return;
    }
    if (_viewMode == _DocViewMode.source) {
      _controller.selection = TextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
      // Dezelfde garantie als bij een standwissel: de trefferregel komt
      // echt in beeld, niet alleen de logische cursor (#2322).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _revealAnchor();
      });
      return;
    }
    _rebuild(() {
      _findSelectionStart = match.start;
      _findSelectionEnd = match.end;
      _findSelectionSignal++;
    });
  }

  /// Scroll / spring naar de aangeklikte kop uit de Overzicht-rail.
  ///
  /// Visueel: cursor in de notes-editor (markdown-offset of Quill-titel).
  /// Bron: cursor in de bron-editor + anker in de live weergave (docs-lezer-
  /// mechanisme).
  void _scrollToHeading(MarkdownOutlineEntry entry) {
    // Het overzicht leeft op de bódy — de tekst die de controller bewerkt.
    // Op de source (mét stijl-frontmatter) uitgerekende offsets landen een
    // frontmatter-lengte te ver (#2465).
    final body = _controller.text;
    final outline = buildMarkdownOutline(body);
    final outlineIndex = outline.indexWhere(
      (e) => e.offset == entry.offset && e.title == entry.title,
    );
    final offset = entry.offset.clamp(0, _controller.text.length);
    _controller.selection = TextSelection.collapsed(offset: offset);
    _editorFocus.requestFocus();
    _rebuild(() {
      _activeOutlineIndex = outlineIndex;
      _revealMarkdownOffset = entry.offset;
      _revealTitle = entry.title;
      _revealSignal++;
    });

    if (_viewMode != _DocViewMode.source) return;
    // headingBlockIndex op de body, niet op de source: de preview rendert de
    // body, en frontmatter-blokken (thematische ---, sleutelregels) tellen
    // anders mee en verschuiven het bloknummer (#1670).
    final index = DocumentMarkdownView.headingBlockIndex(
      body,
      headingSlug(entry.title),
    );
    if (index < 0) return;
    _rebuild(() => _anchorBlockIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchorKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.08,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  /// De Overzicht-rail. De rail zelf staat top-level in dezelfde library
  /// ([_documentOutlineRail]); het scherm levert alleen de stand en wat er bij
  /// een tik moet gebeuren.
  Widget _outlineRail(ThemeData theme, String source) => _documentOutlineRail(
    context,
    theme,
    source,
    collapsed: _outlineCollapsed,
    activeIndex: _activeOutlineIndex,
    onCollapsedChanged: (v) => _rebuild(() => _outlineCollapsed = v),
    onSelect: _scrollToHeading,
  );
}

/// Cachet dezelfde inhoudsprojectie als het actieve documentoppervlak.
class _DocumentSearchIndex {
  _DocumentSearchIndex(this.owner);
  final _DocumentEditorScreenState owner;
  String? _source;
  bool? _pages;
  VisibleMarkdownText? _projection;

  void open({required bool showReplace}) {
    owner.ref.read(documentProvider.notifier).flushPendingVisualEdit();
    if (showReplace && owner._viewMode == _DocViewMode.pages) {
      owner._changeViewMode(_DocViewMode.source);
    }
    owner._find.open(showReplace: showReplace);
  }

  VisibleMarkdownText get projection {
    final source = owner._controller.text;
    final pages = owner._viewMode == _DocViewMode.pages;
    if (_source != source || _pages != pages) {
      _source = source;
      _pages = pages;
      _projection = VisibleMarkdownText(
        source,
        includeUnreferencedFootnotes: !pages,
      );
    }
    return _projection!;
  }

  List<TextMatchRange> matches(
    String source,
    String query, {
    bool caseSensitive = false,
  }) => projection.matches(query, caseSensitive: caseSensitive);

  List<String> contexts(FindReplaceSession findSession) {
    if (findSession.matches.isEmpty) return const [];
    final projection = this.projection;
    final outline = buildMarkdownOutline(findSession.controller.text);
    return [
      for (final match in findSession.matches)
        () {
          final chapter = activeOutlineIndexForOffset(outline, match.start);
          final location = chapter < 0
              ? ''
              : '${visibleMarkdownText(outline[chapter].title)} · ';
          return '$location${projection.context(match)}';
        }(),
    ];
  }
}
