part of 'deck_provider.dart';

void _updateMeta(
  DeckNotifier notifier,
  String? title,
  String? theme,
  bool? paginate,
) {
  final deck = notifier.currentState.deck;
  if (deck == null) return;
  notifier._mutate(
    deck.copyWith(title: title, theme: theme, paginate: paginate),
    coalesceKey: 'meta',
  );
}

extension DeckNotifierInfo on DeckNotifier {
  void updateInfo({
    String? title,
    String? author,
    String? organization,
    String? version,
    String? date,
    String? description,
    String? keywords,
    String? footer,
    String? language,
    List<String>? standardsUsed,
    List<UsedTool>? toolsUsed,
    TlpLevel? tlp,
    int? presentationTargetSeconds,
    PresentationTimingConfig? presentationTiming,
    PageSizeSpec? slideSize,
    bool clearSlideSize = false,
    bool? showRehearsalSummary,
    bool? playOnly,
  }) {
    final deck = currentState.deck;
    if (deck == null) return;
    _mutate(
      deck.copyWith(
        title: title,
        author: author,
        organization: organization,
        version: version,
        date: date,
        description: description,
        keywords: keywords,
        marpStyle: _marpStyleWithFooter(deck, footer),
        language: language,
        standardsUsed: standardsUsed,
        toolsUsed: toolsUsed,
        tlp: tlp,
        presentationTargetSeconds: presentationTargetSeconds,
        presentationTiming: presentationTiming,
        slideSize: slideSize,
        clearSlideSize: clearSlideSize,
        showRehearsalSummary: showRehearsalSummary,
        playOnly: playOnly,
      ),
      coalesceKey: 'info',
    );
  }
}

/// Zet [tlp] en, wanneer [explanation] er is en het deck niet verzegeld is,
/// die dia vooraan. Eén ongedaan-stap (#2396).
void applyPresentationTlpLevel(
  DeckNotifier notifier,
  TlpLevel tlp, {
  Slide? explanation,
}) {
  final deck = notifier.currentState.deck;
  if (deck == null) return;
  final slides = explanation == null || deck.finalized
      ? deck.slides
      : [explanation, ...deck.slides];
  notifier._mutate(deck.copyWith(tlp: tlp, slides: slides), coalesceKey: null);
}

MarpStyle _marpStyleWithFooter(Deck deck, String? footer) {
  if (footer == null) return deck.marpStyle;
  final value = footer.trim();
  return value.isEmpty
      ? deck.marpStyle.copyWith(clearFooter: true)
      : deck.marpStyle.copyWith(footer: value);
}
