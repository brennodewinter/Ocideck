part of 'deck_provider.dart';

/// `part of` extension for the MIAUW compliance waivers (P2-COMP §9), keeping
/// the main notifier under the line limit; as an extension in the same library
/// it keeps access to `_mutate` and the deck state.
extension DeckNotifierMiauw on DeckNotifier {
  /// Exclude EIS [eisId] from the compliance overview with a mandatory [reason].
  /// An empty reason is ignored — a waiver must always be justified.
  void setMiauwWaiver(String eisId, String reason) {
    final deck = currentState.deck;
    if (deck == null || reason.trim().isEmpty) return;
    final waivers = Map<String, String>.from(deck.miauwWaivers)
      ..[eisId] = reason.trim();
    _mutate(deck.copyWith(miauwWaivers: waivers));
  }

  /// Lift the exclusion on EIS [eisId], returning it to its automatic/manual
  /// status.
  void removeMiauwWaiver(String eisId) {
    final deck = currentState.deck;
    if (deck == null || !deck.miauwWaivers.containsKey(eisId)) return;
    final waivers = Map<String, String>.from(deck.miauwWaivers)..remove(eisId);
    _mutate(deck.copyWith(miauwWaivers: waivers));
  }

  /// Manually confirm EIS [eisId] with a mandatory [note] (the human
  /// attestation). An empty note is ignored — a confirmation must be justified,
  /// just like a waiver. The requirement then reads as voldaan (handmatig).
  void setMiauwConfirmation(String eisId, String note) {
    final deck = currentState.deck;
    if (deck == null || note.trim().isEmpty) return;
    final confirmations = Map<String, String>.from(deck.miauwConfirmations)
      ..[eisId] = note.trim();
    _mutate(deck.copyWith(miauwConfirmations: confirmations));
  }

  /// Withdraw the manual confirmation on EIS [eisId], returning it to open.
  void removeMiauwConfirmation(String eisId) {
    final deck = currentState.deck;
    if (deck == null || !deck.miauwConfirmations.containsKey(eisId)) return;
    final confirmations = Map<String, String>.from(deck.miauwConfirmations)
      ..remove(eisId);
    _mutate(deck.copyWith(miauwConfirmations: confirmations));
  }
}
