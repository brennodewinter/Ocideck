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
