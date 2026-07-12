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

  /// Store the imported RFC 3161 timestamp token (base64url of the `.tsr`) on the
  /// sealed deck (PENTEST_MIAUW §8-A2). Allowed on a finalised deck because the
  /// token lives outside the hashed content. Ignored when the deck is unsealed.
  void setSealTimestampToken(String base64Token) {
    final deck = currentState.deck;
    if (deck == null || deck.sealHash.isEmpty) return;
    _mutate(
      deck.copyWith(sealTimestampToken: base64Token),
      allowFinalized: true,
    );
  }
}
