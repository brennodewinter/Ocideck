part of 'paged_document_view.dart';

extension _PagedDocumentSearch on _PagedDocumentViewState {
  /// Rendert het document één keer buiten beeld op de tekstbreedte van de
  /// pagina, met een meter om elk blok. Offstage blijft zijn kind uitmeten,
  /// maar houdt de warme kopie uit beeld, toegankelijkheidsboom en gewone
  /// gebruikersgerichte finders.
  Widget _measure() {
    final blockCount = _blockTexts.length;
    // De noten meten in dezelfde ronde mee, elk apart: alleen zo weet de
    // paginaverdeling hoeveel ruimte er onder een blad weg moet. Ze krijgen
    // indexen áchter de blokken, zodat één teller volstaat.
    final notes = _notesOnPage ? _notes : const <Footnote>[];
    // Eindnoten (achterin het document) meten als één extra blok: de
    // DocumentMarkdownView tekent ze buiten de blockWrapper, dus de gewone
    // blokmeting ziet ze niet. Zonder deze extra meting vallen lange eindnoten
    // voorbij de laatste berekende pagina en worden ze afgeknipt (#1653).
    final endnotes = !_notesOnPage && _notes.isNotEmpty
        ? _notes
        : const <Footnote>[];
    final total = blockCount + notes.length + (endnotes.isNotEmpty ? 1 : 0);
    return Offstage(
      child: ClipRect(
        child: Stack(
          children: [
            const SizedBox.expand(),
            Positioned(
              left: -1e5,
              top: 0,
              width: _contentWidthPx,
              child: IgnorePointer(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _measuredSearchDocument(
                      _measureBody ??= DocumentMarkdownView(
                        widget.markdown,
                        maxTextWidth: null,
                        themeProfile: widget.profile,
                        chartTheme: widget.profile,
                        hideRules: true,
                        footnotesAtEnd: !_notesOnPage,
                        scaleMermaidToFit: true,
                        blockWrapper: (index, block) => _MeasuredBlock(
                          index: index,
                          onMeasured: (i, height) =>
                              _onMeasured(i, height, blockCount, total),
                          child: block,
                        ),
                      ),
                    ),
                    for (var n = 0; n < notes.length; n++)
                      _MeasuredBlock(
                        index: blockCount + n,
                        onMeasured: (i, height) =>
                            _onMeasured(i, height, blockCount, total),
                        // Eén noot per meting: de scheidingslijn en de tussenruimte
                        // horen bij het vel, niet bij de noot, en die zitten in
                        // [_noteGapPx].
                        child: _measuredSearchNote(notes[n]),
                      ),
                    if (endnotes.isNotEmpty)
                      _MeasuredBlock(
                        index: blockCount + notes.length,
                        onMeasured: (i, height) =>
                            _onMeasured(i, height, blockCount, total),
                        child: ExcludeDocumentSearch(
                          child: DocumentFootnotesView(
                            notes: endnotes,
                            themeProfile: widget.profile,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _measuredSearchDocument(Widget child) => DocumentSearchOverlay(
    query: widget.searchQuery,
    activeIndex: _searchSelection.mainIndex,
    caseSensitive: widget.searchCaseSensitive,
    geometry: _searchGeometry,
    revealSignal: widget.searchRevealSignal,
    child: child,
  );

  Widget _measuredSearchNote(Footnote note) => DocumentFootnotesView(
    notes: [note],
    themeProfile: widget.profile,
    noteWrapper: (note, child) => DocumentSearchOverlay(
      query: note.label == _searchSelection.noteLabel ? widget.searchQuery : '',
      activeIndex: _searchSelection.noteIndex,
      caseSensitive: widget.searchCaseSensitive,
      revealSignal: widget.searchRevealSignal,
      geometry: _noteGeometry.putIfAbsent(
        note.label,
        DocumentSearchGeometry.new,
      ),
      child: child,
    ),
  );

  Widget _paintSearchDocument(Widget child, double offset, double height) =>
      DocumentSearchOverlay(
        query: widget.searchQuery,
        activeIndex: _searchSelection.mainIndex,
        geometry: _searchGeometry,
        measure: false,
        revealIntoView: true,
        paintBounds: Rect.fromLTWH(0, offset, _contentWidthPx, height),
        child: child,
      );

  Widget _searchFootnotePane(List<Footnote> notes) => _FootnotePane(
    notes: notes,
    searchLabel: _searchSelection.noteLabel,
    searchGeometry: _noteGeometry[_searchSelection.noteLabel],
    searchSignal: widget.searchRevealSignal,
    themeProfile: widget.profile,
    overflowing: _footnoteOverflow(notes),
    maxHeight: _contentHeightPx,
  );
}

/// Brondefinities mogen in een andere volgorde staan dan de genummerde noten.
/// De bronrang wordt daarom één keer vertaald naar de echte renderlocatie.
class _PagedSearchSelection {
  const _PagedSearchSelection({
    this.mainIndex = -1,
    this.noteLabel,
    this.noteIndex = -1,
  });
  final int mainIndex;
  final String? noteLabel;
  final int noteIndex;
}

_PagedSearchSelection _pagedSearchSelection(
  PagedDocumentView widget,
  _PagedSearchText index,
) {
  final hits = index.matches(widget.searchQuery, widget.searchCaseSensitive);
  final selected = widget.searchMatchIndex;
  if (selected < 0 || selected >= hits.length) {
    return const _PagedSearchSelection();
  }
  final ranges = index.ranges;
  String? labelOf(TextMatchRange hit) {
    for (final entry in ranges.entries) {
      if (hit.start >= entry.value.start && hit.start < entry.value.end) {
        return entry.key;
      }
    }
    return null;
  }

  final label = labelOf(hits[selected]);
  if (label == null) {
    return _PagedSearchSelection(
      mainIndex: hits
          .take(selected)
          .where((hit) => labelOf(hit) == null)
          .length,
    );
  }
  final local = hits
      .take(selected)
      .where((hit) => labelOf(hit) == label)
      .length;
  if (widget.footnotePlacement == FootnotePlacement.page) {
    return _PagedSearchSelection(noteLabel: label, noteIndex: local);
  }
  final notes = index.notes;
  final prior = notes
      .takeWhile((note) => note.label != label)
      .map((note) => note.label)
      .toSet();
  return _PagedSearchSelection(
    mainIndex:
        hits
            .where(
              (hit) => labelOf(hit) == null || prior.contains(labelOf(hit)),
            )
            .length +
        local,
  );
}

Map<String, TextMatchRange> _noteSourceRanges(String source) {
  final result = <String, TextMatchRange>{};
  final lines = source.split('\n');
  final definition = RegExp(r'^ {0,3}\[\^([^\]\s]+)\]:[ \t]*(.*)$');
  MarkdownFence? fence;
  var offset = 0;
  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (fence != null) {
      if (fence.closes(line.trim())) fence = null;
    } else if (markdownFenceOpen(line.trim()) case final opening?) {
      fence = opening;
    } else if (definition.firstMatch(line) case final match?) {
      var end = offset + line.length;
      while (i + 1 < lines.length &&
          lines[i + 1].trim().isNotEmpty &&
          (lines[i + 1].startsWith('    ') || lines[i + 1].startsWith('\t'))) {
        end += 1 + lines[++i].length;
      }
      result.putIfAbsent(match[1]!, () => TextMatchRange(offset, end));
      offset = end + 1;
      continue;
    }
    offset += line.length + 1;
  }
  return result;
}

/// Een klik op Volgende verandert geen bron: projectie en treffers blijven geldig.
class _PagedSearchText {
  _PagedSearchText(String source)
    : projection = VisibleMarkdownText(
        source,
        includeUnreferencedFootnotes: false,
      ),
      ranges = _noteSourceRanges(source),
      notes = documentFootnotes(source);
  final VisibleMarkdownText projection;
  final Map<String, TextMatchRange> ranges;
  final List<Footnote> notes;
  String? _query;
  bool _caseSensitive = false;
  List<TextMatchRange> _hits = const [];

  List<TextMatchRange> matches(String query, bool caseSensitive) {
    if (_query != query || _caseSensitive != caseSensitive) {
      _query = query;
      _caseSensitive = caseSensitive;
      _hits = projection.matches(query, caseSensitive: caseSensitive);
    }
    return _hits;
  }
}
