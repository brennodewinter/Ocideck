part of '../app_shell.dart';

/// Het doorgeefluik van de werkruimte naar de menubalk.
///
/// Apart bestand omdat `app_shell_main_layout.dart` tegen de regelratchet aan
/// zit. Als extensie in dezelfde library houdt het toegang tot de private
/// handelingen van [_MainLayoutState] — precies wat de menubalk nodig heeft en
/// van buiten de shell niet te bereiken is.
extension _MainLayoutMenuCommands on _MainLayoutState {
  /// Geef de menubalk toegang tot de handelingen van de werkruimte.
  ///
  /// De balk hangt boven de hele app — ook boven het openscherm, want een
  /// menubalk die verschijnt en verdwijnt is er geen — terwijl presenteren,
  /// exporteren en het commandopalet hier privé wonen.
  ///
  /// Alleen doorgeven als een aan/uit-stand verandert. De closures hieronder
  /// zijn elke frame nieuw, maar sluiten om deze langlevende `State` heen; ze
  /// elke frame publiceren zou de menubalk elke frame opnieuw naar het platform
  /// laten schrijven.
  void _publishMenuCommands(DeckState deckState, bool canExport) {
    // De tabbladen leven in een IndexedStack, dus élk geopend tabblad bouwt
    // elke frame mee. Alleen het zichtbare tabblad mag de menubalk vullen —
    // anders bedient "Presenteren" een presentatie die niet in beeld staat.
    final notifier = ref.read(deckProvider.notifier);
    if (!identical(ref.watch(tabsProvider).current?.deckNotifier, notifier)) {
      return;
    }
    final next = ShellDeckCommands(
      present: _presentDeck,
      export: _exportDeck,
      save: _saveDeck,
      find: _openFind,
      findReplace: _openFindReplace,
      properties: _openProperties,
      commandPalette: _openCommandPalette,
      fullDeckPreview: _openFullDeckPreview,
      undo: () => _undo(ref.read(deckProvider.notifier)),
      redo: () => _redo(ref.read(deckProvider.notifier)),
      canExport: canExport,
      canUndo: deckState.canUndo,
      canRedo: deckState.canRedo,
    );
    final current = ref.read(shellDeckCommandsProvider);
    if (current != null &&
        identical(_publishedFor, notifier) &&
        current.sameEnablement(next)) {
      return;
    }
    _publishedFor = notifier;
    _published = next;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(shellDeckCommandsProvider.notifier).state = next;
    });
  }
}
