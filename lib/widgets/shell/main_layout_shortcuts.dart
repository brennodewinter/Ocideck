part of '../app_shell.dart';

// De sneltoetsbindingen van het hoofdscherm, als top-level helper zodat ze
// niet meetellen voor _MainLayoutState. Alle imports staan in ../app_shell.dart.

/// Sneltoetsen van het hoofdscherm (opslaan, undo/redo, zoeken).
Map<ShortcutActivator, VoidCallback> _shortcutBindings(
  _MainLayoutState state,
  DeckNotifier deckNotifier,
) {
  return {
    const SingleActivator(LogicalKeyboardKey.keyS, control: true):
        state._saveDeck,
    const SingleActivator(LogicalKeyboardKey.keyS, meta: true): state._saveDeck,
    // Ongedaan maken / opnieuw. Vuren alleen wanneer de focus niet in een
    // tekstveld zit (dat handelt z'n eigen undo af), dus geen conflict.
    const SingleActivator(LogicalKeyboardKey.keyZ, control: true): () =>
        state._undo(deckNotifier),
    const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): () =>
        state._undo(deckNotifier),
    const SingleActivator(
      LogicalKeyboardKey.keyZ,
      control: true,
      shift: true,
    ): () =>
        state._redo(deckNotifier),
    const SingleActivator(
      LogicalKeyboardKey.keyZ,
      meta: true,
      shift: true,
    ): () =>
        state._redo(deckNotifier),
    const SingleActivator(LogicalKeyboardKey.keyY, control: true): () =>
        state._redo(deckNotifier),
    const SingleActivator(LogicalKeyboardKey.keyF, control: true):
        state._openFind,
    const SingleActivator(LogicalKeyboardKey.keyF, meta: true): state._openFind,
    const SingleActivator(LogicalKeyboardKey.keyH, control: true):
        state._openFindReplace,
    const SingleActivator(LogicalKeyboardKey.keyH, meta: true):
        state._openFindReplace,
    // Commandopalet: doorzoekbare lijst van alle acties.
    const SingleActivator(LogicalKeyboardKey.keyK, control: true):
        state._openCommandPalette,
    const SingleActivator(LogicalKeyboardKey.keyK, meta: true):
        state._openCommandPalette,
  };
}
