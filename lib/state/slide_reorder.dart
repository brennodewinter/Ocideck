import 'deck_provider.dart';
import 'editor_provider.dart';

/// Verplaatst één dia of een geselecteerd blok en laat de selectie meereizen.
///
/// `onReorderItem`-vorm van [applySlideInsertion]: [newIndex] telt in de lijst
/// zónder de gesleepte dia (Flutter corrigeert die zelf voor) en wordt hier
/// naar het invoegslot vertaald.
void applySlideReorder(
  int oldIndex,
  int newIndex, {
  required EditorState editor,
  required DeckNotifier notifier,
  required EditorNotifier editorNotifier,
  required int slideCount,
}) => applySlideInsertion(
  oldIndex,
  newIndex >= oldIndex ? newIndex + 1 : newIndex,
  editor: editor,
  notifier: notifier,
  editorNotifier: editorNotifier,
  slideCount: slideCount,
);

/// Zet [draggedIndex] — of het geselecteerde blok als die dia meeselecteerd
/// is — neer op invoegslot [slot]: 0 = vóór de eerste dia, N = achter de
/// laatste. Het slot telt in de lijst vóór de verplaatsing (#2362). Deze ene
/// rekenplek dient het slide-overzicht én de strook.
void applySlideInsertion(
  int draggedIndex,
  int slot, {
  required EditorState editor,
  required DeckNotifier notifier,
  required EditorNotifier editorNotifier,
  required int slideCount,
}) {
  final dragged =
      editor.hasMultiSelection && editor.selection.contains(draggedIndex)
      ? editor.selection
      : {draggedIndex};
  final start = notifier.moveSlidesToSlot(dragged, slot);
  if (start < 0) return;
  if (dragged.length > 1) {
    final count = editor.selection.length;
    final primaryOffset = editor.selection
        .where((index) => index < editor.selectedIndex)
        .length;
    editorNotifier.selectBlock(start, count, primary: start + primaryOffset);
    return;
  }
  final selectedIndex = editor.selectedIndex;
  var nextSelection = selectedIndex;
  if (draggedIndex == selectedIndex) {
    nextSelection = start;
  } else if (draggedIndex < selectedIndex && start >= selectedIndex) {
    nextSelection = selectedIndex - 1;
  } else if (draggedIndex > selectedIndex && start <= selectedIndex) {
    nextSelection = selectedIndex + 1;
  }
  editorNotifier.select(nextSelection.clamp(0, slideCount - 1));
}

/// Levert [slot] geen verplaatsing op voor het gesleepte [dragged]-blok?
/// De UI gebruikt dit om de invoegmarkering te verbergen op plekken waar
/// droppen toch niets doet; [DeckNotifier.moveSlidesToSlot] blijft de eind-
/// controle.
bool isNoOpInsertSlot(Set<int> dragged, int slot, int slideCount) {
  final sel = dragged.where((i) => i >= 0 && i < slideCount);
  if (sel.isEmpty || slot < 0 || slot > slideCount) return false;
  if (slot < slideCount && sel.contains(slot)) return true;
  // Een aaneengesloten blok: elk slot van vóór t/m ná het blok houdt de
  // volgorde gelijk.
  final first = sel.reduce((a, b) => a < b ? a : b);
  final last = sel.reduce((a, b) => a > b ? a : b);
  return last - first + 1 == sel.length && slot >= first && slot <= last + 1;
}
