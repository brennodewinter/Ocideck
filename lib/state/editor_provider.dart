import 'package:flutter_riverpod/legacy.dart';

enum EditorMode { visual, markdown }

class EditorState {
  /// The active slide (shown in the editor/preview). Always part of [selection].
  final int selectedIndex;

  /// All currently selected slide indices (for bulk actions). Never empty.
  final Set<int> selection;
  final EditorMode mode;
  final String markdownBuffer;
  final bool parseError;

  /// When set, the active slide editor should focus this field once (see
  /// [EditorNotifier.selectWithQualityField]).
  final String? focusQualityField;

  const EditorState({
    this.selectedIndex = 0,
    this.selection = const {0},
    this.mode = EditorMode.visual,
    this.markdownBuffer = '',
    this.parseError = false,
    this.focusQualityField,
  });

  bool get hasMultiSelection => selection.length > 1;

  EditorState copyWith({
    int? selectedIndex,
    Set<int>? selection,
    EditorMode? mode,
    String? markdownBuffer,
    bool? parseError,
    String? focusQualityField,
    bool clearFocusQualityField = false,
  }) {
    return EditorState(
      selectedIndex: selectedIndex ?? this.selectedIndex,
      selection: selection ?? this.selection,
      mode: mode ?? this.mode,
      markdownBuffer: markdownBuffer ?? this.markdownBuffer,
      parseError: parseError ?? this.parseError,
      focusQualityField: clearFocusQualityField
          ? null
          : (focusQualityField ?? this.focusQualityField),
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
  void selectWithQualityField(int index, String? field) {
    state = state.copyWith(
      selectedIndex: index,
      selection: {index},
      focusQualityField: field,
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
      parseError: false,
    );
  }

  void updateMarkdown(String content) {
    state = state.copyWith(markdownBuffer: content);
  }

  void setParseError(bool value) {
    state = state.copyWith(parseError: value);
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
