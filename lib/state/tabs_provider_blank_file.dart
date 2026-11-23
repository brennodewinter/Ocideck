part of 'tabs_provider.dart';

/// Open direct een leeg bestand van het actieve type, met een presentatie
/// als standaard vanaf het openingsscherm.
void newBlankFile(TabsNotifier notifier) {
  final state = notifier.currentState;
  final current = state.current;
  if (current != null && !current.isOpen) {
    _loadBlankPresentation(current);
    notifier.refreshTabs();
    return;
  }
  if (current?.kind == MarkdownKind.document) {
    _placeDocumentTab(notifier, MarkdownDocument.parse(''));
    return;
  }
  final tab = notifier._createTab();
  _loadBlankPresentation(tab);
  notifier._replacementState = state.copyWith(
    tabs: [...state.tabs, tab],
    selectedIndex: state.tabs.length,
  );
}

/// Wissel van editor op dezelfde plek in de tabbalk.
void switchBlankFileKind(TabsNotifier notifier, int tabId) {
  final state = notifier.currentState;
  final tab = state.current;
  if (tab == null || tab.id != tabId) return;
  // De visuele editor kan nog tekst hebben die niet in de bron staat.
  tab.documentNotifier?.flushPendingVisualEdit();
  if (!tab.canSwitchBlankKind) return;
  final TabInfo replacement;
  if (tab.kind == MarkdownKind.document) {
    replacement = notifier._createTab();
    _loadBlankPresentation(replacement);
  } else {
    replacement = _createDocumentTab(notifier, MarkdownDocument.parse(''));
  }
  notifier._disposeTab(tab);
  notifier._recovery.discard(tab.recoveryId);
  notifier._replacementState = state.copyWith(
    tabs: List<TabInfo>.of(state.tabs)..[state.clampedIndex] = replacement,
  );
  notifier.sweepWebAssets();
}

void _loadBlankPresentation(TabInfo tab) {
  final notifier = tab.deckNotifier;
  notifier.loadDeck(
    Deck(
      title: '',
      slides: [Slide(id: _uuid.v4(), type: SlideType.title)],
    ),
  );
  tab._blankPresentation = notifier.currentState.deck;
}

extension BlankFileTab on TabInfo {
  bool get canSwitchBlankKind {
    if (!isOpen ||
        isDirty ||
        origin != null ||
        collabSession != null ||
        learningSession != null) {
      return false;
    }
    return switch (content) {
      DeckTabContent(:final deckNotifier) => _isBlankPresentation(
        deckNotifier,
        _blankPresentation,
      ),
      DocumentTabContent(:final documentNotifier) => _isBlankDocument(
        documentNotifier.currentState,
      ),
    };
  }
}

bool _isBlankPresentation(DeckNotifier notifier, Deck? starter) {
  final state = notifier.currentState;
  return identical(state.deck, starter) &&
      state.filePath == null &&
      state.downloadName == null &&
      state.remoteOrigin == null &&
      notifier.browserStorageId == null;
}

bool _isBlankDocument(DocumentState state) =>
    state.document?.isEmpty == true &&
    state.document?.hasUtf8Bom == false &&
    !state.canRedo &&
    state.filePath == null &&
    state.downloadName == null &&
    state.projectPath == null &&
    state.suggestedName == null &&
    state.pendingAudioPath == null;
