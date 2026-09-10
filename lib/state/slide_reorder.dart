import 'deck_provider.dart';
import 'editor_provider.dart';

/// Verplaatst één dia of een geselecteerd blok en laat de selectie meereizen.
void applySlideReorder(
  int oldIndex,
  int newIndex, {
  required EditorState editor,
  required DeckNotifier notifier,
  required EditorNotifier editorNotifier,
  required int slideCount,
}) {
  if (editor.hasMultiSelection && editor.selection.contains(oldIndex)) {
    final start = notifier.moveSlides(editor.selection, oldIndex, newIndex);
    if (start >= 0) {
      final count = editor.selection.length;
      final primaryOffset = editor.selection
          .where((index) => index < editor.selectedIndex)
          .length;
      editorNotifier.selectBlock(start, count, primary: start + primaryOffset);
    }
    return;
  }
  notifier.reorderSlides(oldIndex, newIndex);
  final selectedIndex = editor.selectedIndex;
  var nextSelection = selectedIndex;
  if (oldIndex == selectedIndex) {
    nextSelection = newIndex;
  } else if (oldIndex < selectedIndex && newIndex >= selectedIndex) {
    nextSelection = selectedIndex - 1;
  } else if (oldIndex > selectedIndex && newIndex <= selectedIndex) {
    nextSelection = selectedIndex + 1;
  }
  editorNotifier.select(nextSelection.clamp(0, slideCount - 1));
}
