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
}
