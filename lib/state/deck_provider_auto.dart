part of 'deck_provider.dart';

/// `part of` extension for the automation actions (P2-AUTO §10), keeping the
/// main notifier under the line limit; as an extension in the same library it
/// keeps access to `_mutate` and the deck state.
extension DeckNotifierAuto on DeckNotifier {
  /// Renumber every finding (`F-01`, `F-02`, … in deck order) in one undoable
  /// step, rewriting each group's shared id and its heading prefix
  /// (PENTEST_MIAUW §10.1). No-op on a finalised (sealed) deck. Returns how many
  /// findings were numbered.
  int autoRenumberFindings() {
    final deck = currentState.deck;
    if (deck == null) return 0;
    final renumbered = renumberFindings(deck);
    final count = deckFindingList(renumbered).length;
    if (count > 0) _mutate(renumbered, bumpRevision: true);
    return count;
  }
}
