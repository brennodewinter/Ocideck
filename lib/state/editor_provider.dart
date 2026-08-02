import 'package:flutter_riverpod/legacy.dart';

import '../models/slide_quality.dart';

enum EditorMode { visual, markdown }

/// Welke omvang de markdown-modus toont: de hele presentatie of alleen de
/// actieve slide. Zo kan een gebruiker de markdown van één slide inzichtelijk
/// maken zonder de rest te zien.
enum MarkdownScope { deck, slide }

class EditorState {
  /// The active slide (shown in the editor/preview). Always part of [selection].
  final int selectedIndex;

  /// All currently selected slide indices (for bulk actions). Never empty.
  final Set<int> selection;
  final EditorMode mode;

  /// Of de markdown-modus de hele presentatie of alleen de actieve slide toont.
  final MarkdownScope markdownScope;
  final String markdownBuffer;
  final String markdownBaseline;
  final bool parseError;

  /// When set, the active slide editor should focus this field once (see
  /// [EditorNotifier.selectWithQualityField]).
  final String? focusQualityField;

  /// Welk stuk tekst binnen [focusQualityField] geselecteerd moet worden zodra
  /// dat veld focus krijgt. Reist samen met [focusQualityField] en wordt in
  /// hetzelfde gebaar gewist.
  ///
  /// Selecteren in plaats van een eigen markering: een `TextSelection` is de
  /// accentuering die de gebruiker al kent, werkt in elk tekstveld zonder extra
  /// schilderwerk, en laat zich meteen kopiëren of overtypen.
  final SlideQualitySpan? focusQualitySpan;

  /// Monotonic counter; [MarkdownDeckEditor] listens to open the find bar.
  final int markdownFindRequestId;

  /// When a find request is fired, whether to show the replace row.
  final bool markdownFindShowReplace;

  const EditorState({
    this.selectedIndex = 0,
    this.selection = const {0},
    this.mode = EditorMode.visual,
    this.markdownScope = MarkdownScope.deck,
    this.markdownBuffer = '',
    this.markdownBaseline = '',
    this.parseError = false,
    this.focusQualityField,
    this.focusQualitySpan,
    this.markdownFindRequestId = 0,
    this.markdownFindShowReplace = false,
  });

  bool get hasMultiSelection => selection.length > 1;
  bool get hasMarkdownDraft =>
      mode == EditorMode.markdown && markdownBuffer != markdownBaseline;

  EditorState copyWith({
    int? selectedIndex,
    Set<int>? selection,
    EditorMode? mode,
    MarkdownScope? markdownScope,
    String? markdownBuffer,
    String? markdownBaseline,
    bool? parseError,
    String? focusQualityField,
    SlideQualitySpan? focusQualitySpan,
    bool clearFocusQualityField = false,
    int? markdownFindRequestId,
    bool? markdownFindShowReplace,
  }) {
    return EditorState(
      selectedIndex: selectedIndex ?? this.selectedIndex,
      selection: selection ?? this.selection,
      mode: mode ?? this.mode,
      markdownScope: markdownScope ?? this.markdownScope,
      markdownBuffer: markdownBuffer ?? this.markdownBuffer,
      markdownBaseline: markdownBaseline ?? this.markdownBaseline,
      parseError: parseError ?? this.parseError,
      focusQualityField: clearFocusQualityField
          ? null
          : (focusQualityField ?? this.focusQualityField),
      focusQualitySpan: clearFocusQualityField
          ? null
          : (focusQualitySpan ?? this.focusQualitySpan),
      markdownFindRequestId:
          markdownFindRequestId ?? this.markdownFindRequestId,
      markdownFindShowReplace:
          markdownFindShowReplace ?? this.markdownFindShowReplace,
    );
  }
}

class EditorNotifier extends StateNotifier<EditorState> {
  EditorNotifier() : super(const EditorState());

  EditorState get currentState => state;

  /// Single-select [index] (clears any multi-selection).
  void select(int index) {
    if (index == state.selectedIndex &&
        state.selection.length == 1 &&
        state.focusQualityField == null) {
      return;
    }
    state = state.copyWith(
      selectedIndex: index,
      selection: {index},
      parseError: false,
      clearFocusQualityField: true,
    );
  }

  /// Jump to [index] and request focus on [field] in the slide editor (once).
  ///
  /// Is [span] gezet, dan wordt dat stuk tekst ook geselecteerd zodra het veld
  /// focus krijgt — zo ziet de auteur meteen wélk fragment de melding bedoelt.
  void selectWithQualityField(
    int index,
    String? field, {
    SlideQualitySpan? span,
  }) {
    state = state.copyWith(
      selectedIndex: index,
      selection: {index},
      focusQualityField: field,
      focusQualitySpan: span,
      parseError: false,
    );
  }

  void clearFocusQualityField() {
    if (state.focusQualityField == null) return;
    state = state.copyWith(clearFocusQualityField: true);
  }

  /// Ctrl/Cmd-click: voeg [index] toe of haal 'm uit de selectie.
  void toggleSelect(int index) {
    final next = Set<int>.from(state.selection);
    if (next.contains(index) && next.length > 1) {
      next.remove(index);
      final active = index == state.selectedIndex
          ? next.reduce((a, b) => a < b ? a : b)
          : state.selectedIndex;
      state = state.copyWith(selection: next, selectedIndex: active);
    } else {
      next.add(index);
      state = state.copyWith(selection: next, selectedIndex: index);
    }
  }

  /// Selecteer een aaneengesloten reeks van [count] slides vanaf [start], met
  /// [primary] als actieve slide. Gebruikt nadat een multiselectie als blok is
  /// verplaatst, zodat de selectie het blok blijft volgen.
  void selectBlock(int start, int count, {int? primary}) {
    if (count <= 0) return;
    state = state.copyWith(
      selection: {for (var i = start; i < start + count; i++) i},
      selectedIndex: (primary ?? start).clamp(start, start + count - 1),
    );
  }

  /// Selecteer alle [count] slides (Ctrl/Cmd+A).
  void selectAll(int count) {
    if (count <= 0) return;
    state = state.copyWith(
      selection: {for (var i = 0; i < count; i++) i},
      selectedIndex: state.selectedIndex.clamp(0, count - 1),
    );
  }

  /// Shift-click: selecteer het bereik van de actieve slide tot [index].
  void selectRange(int index) {
    final anchor = state.selectedIndex;
    final lo = anchor < index ? anchor : index;
    final hi = anchor < index ? index : anchor;
    state = state.copyWith(
      selection: {for (var i = lo; i <= hi; i++) i},
      selectedIndex: index,
    );
  }

  void setMode(EditorMode mode, {String? initialMarkdown}) {
    state = state.copyWith(
      mode: mode,
      markdownBuffer: initialMarkdown ?? state.markdownBuffer,
      markdownBaseline: initialMarkdown ?? state.markdownBaseline,
      parseError: false,
    );
  }

  void loadMarkdownSource(String content) {
    state = state.copyWith(
      markdownBuffer: content,
      markdownBaseline: content,
      parseError: false,
    );
  }

  void updateMarkdown(String content) {
    state = state.copyWith(markdownBuffer: content);
  }

  /// Wissel de markdown-modus tussen de hele presentatie en de actieve slide.
  void setMarkdownScope(MarkdownScope scope) {
    if (state.markdownScope == scope) return;
    state = state.copyWith(markdownScope: scope, parseError: false);
  }

  void setParseError(bool value) {
    state = state.copyWith(parseError: value);
  }

  /// Opens the in-editor find bar in markdown mode (Ctrl/Cmd+F or H).
  void requestMarkdownFind({required bool showReplace}) {
    state = state.copyWith(
      markdownFindRequestId: state.markdownFindRequestId + 1,
      markdownFindShowReplace: showReplace,
    );
  }

  /// Clamp/normaliseer de selectie nadat slides zijn verwijderd.
  void clampIndex(int maxIndex) {
    final max = maxIndex < 0 ? 0 : maxIndex;
    final pruned = state.selection.where((i) => i <= max).toSet();
    final index = state.selectedIndex > max ? max : state.selectedIndex;
    state = state.copyWith(
      selectedIndex: index,
      selection: pruned.isEmpty ? {index} : pruned,
    );
  }
}

final editorProvider = StateNotifierProvider<EditorNotifier, EditorState>(
  (_) => EditorNotifier(),
);
