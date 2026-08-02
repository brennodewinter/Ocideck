// Part of the slide_list_panel library — see slide_list_panel.dart.
// Split out for navigability (the "add slide" flow) and to keep the main file
// under the size ratchet; all imports live in the main library file.
part of 'slide_list_panel.dart';

extension _SlideListPanelAddSlide on _SlideListPanelState {
  /// Handle the "Slide toevoegen" button: pick a type, and for a `finding` run
  /// the guided wizard (P2-WIZ), inserting the whole emitted group at once and
  /// selecting its header; every other type inserts a single blank slide.
  Future<void> _onAddSlide() async {
    final type = await AddSlideDialog.show(
      context,
      revealInfoSafety: ref.read(infoSafetyRevealProvider),
      revealProcesverbetering: ref.read(procesverbeteringRevealProvider),
      // The shared module contract: revealed when the switch is on, or the deck
      // already carries a controlStatus slide so switching off never strands it.
      revealManagementsysteem:
          ref.read(managementsysteemRevealProvider) ||
          (ref.read(deckProvider).deck?.hasManagementSystemSlides ?? false),
    );
    if (type == null) return;
    final notifier = ref.read(deckProvider.notifier);
    final editorNotifier = ref.read(editorProvider.notifier);
    final idx = ref.read(editorProvider).selectedIndex;
    if (type == SlideType.finding) {
      if (!mounted) return;
      final scopeRows = deckScopeRows(
        ref.read(deckProvider).deck?.slides ?? [],
      );
      final group = await FindingWizard.show(context, scopeRows: scopeRows);
      if (group == null || group.isEmpty) return;
      final at = notifier.insertSlides(group, afterIndex: idx);
      if (at >= 0) editorNotifier.select(at);
    } else {
      notifier.addSlide(type, afterIndex: idx);
      editorNotifier.select(idx + 1);
    }
  }
}

/// Verplaatst een dia (of een heel multiselectie-blok) na een sleepactie en laat
/// de selectie de nieuwe plek volgen. Losgetrokken uit [_SlideListPanelState]
/// omdat de State-klasse anders het regelplafond overschrijdt; het gedrag is
/// onveranderd.
void applySlideReorder(
  int old,
  int nw, {
  required EditorState editor,
  required DeckNotifier notifier,
  required EditorNotifier editorNotifier,
  required int slideCount,
}) {
  // Sleep je één slide uit een multiselectie, dan verhuist het hele blok in één
  // keer; de selectie volgt het blok naar de nieuwe plek.
  if (editor.hasMultiSelection && editor.selection.contains(old)) {
    final start = notifier.moveSlides(editor.selection, old, nw);
    if (start >= 0) {
      final count = editor.selection.length;
      final primaryOffset = editor.selection
          .where((i) => i < editor.selectedIndex)
          .length;
      editorNotifier.selectBlock(start, count, primary: start + primaryOffset);
    }
    return;
  }
  notifier.reorderSlides(old, nw);
  // Adjust selection when active slide moved.
  final selIdx = editor.selectedIndex;
  int newSel = selIdx;
  if (old == selIdx) {
    newSel = nw;
  } else if (old < selIdx && nw >= selIdx) {
    newSel = selIdx - 1;
  } else if (old > selIdx && nw <= selIdx) {
    newSel = selIdx + 1;
  }
  editorNotifier.select(newSel.clamp(0, slideCount - 1));
}
