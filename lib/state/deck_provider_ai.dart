part of 'deck_provider.dart';

/// AI image alt-text provenance/safety actions (AI_ASSIST §6.4), split into a
/// `part of` extension to keep the main notifier under the line limit; as an
/// extension in the same library it keeps access to `_mutate` and `state`.
extension DeckNotifierAiAlt on DeckNotifier {
  /// How many image alt-texts are still marked AI-generated and not yet reviewed
  /// (see [deckAiGeneratedAltTextCount]). Powers the "clear AI alt-texts" safety
  /// action's count/enabled state.
  int get aiGeneratedAltTextCount {
    final deck = currentState.deck;
    return deck == null ? 0 : deckAiGeneratedAltTextCount(deck);
  }

  /// Safety net for a bad bulk AI run (AI_ASSIST §6.4): clear every AI-generated,
  /// unreviewed alt-text (and its marker), leaving human-written and reviewed
  /// alt-text untouched. One undoable [_mutate]; returns how many were cleared.
  int clearAiGeneratedAltTexts() {
    final deck = currentState.deck;
    if (deck == null) return 0;
    final (slides, cleared) = computeClearedAiAltTexts(deck);
    if (cleared > 0) _mutate(deck.copyWith(slides: slides));
    return cleared;
  }
}
