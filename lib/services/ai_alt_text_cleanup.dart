import '../models/deck.dart';
import '../models/slide.dart';

/// Deck-level helpers for the AI image alt-text provenance/safety net
/// (AI_ASSIST §6.4). An alt-text is "AI-generated & unreviewed" when the slide
/// still carries its provenance marker (`imageAltText` / `imageAltText2` in
/// [Slide.aiAssistedFields]); a human-written or reviewed alt-text carries no
/// marker. Kept out of the notifier so it stays small and is unit-testable.

/// How many image alt-texts in [deck] are still AI-generated and unreviewed.
int deckAiGeneratedAltTextCount(Deck deck) {
  var n = 0;
  for (final s in deck.slides) {
    if (s.imageAltText.isNotEmpty &&
        s.aiAssistedFields.contains('imageAltText')) {
      n++;
    }
    if (s.imageAltText2.isNotEmpty &&
        s.aiAssistedFields.contains('imageAltText2')) {
      n++;
    }
  }
  return n;
}

/// Compute [deck]'s slides with every still-marked AI alt-text cleared (and its
/// marker dropped), leaving human-written and reviewed alt-text untouched.
/// Returns the new slide list and how many alt-texts were cleared.
(List<Slide>, int) computeClearedAiAltTexts(Deck deck) {
  var cleared = 0;
  final slides = <Slide>[];
  for (final s in deck.slides) {
    var out = s;
    if (s.imageAltText.isNotEmpty &&
        s.aiAssistedFields.contains('imageAltText')) {
      out = out
          .copyWith(imageAltText: '')
          .withAiAssistedField('imageAltText', present: false);
      cleared++;
    }
    if (s.imageAltText2.isNotEmpty &&
        s.aiAssistedFields.contains('imageAltText2')) {
      out = out
          .copyWith(imageAltText2: '')
          .withAiAssistedField('imageAltText2', present: false);
      cleared++;
    }
    slides.add(out);
  }
  return (slides, cleared);
}
