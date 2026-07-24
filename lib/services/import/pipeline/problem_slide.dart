import '../models/slide_failure_policy.dart';

/// A source slide that could not be converted perfectly, surfaced to the UI
/// for a per-slide decision when auto-continue is off.
///
/// Carries the 1-based, user-facing slide number, the human-readable issue
/// descriptions, and whether the slide has an image (so the UI can offer the
/// rasterize option meaningfully).
class ProblemSlide {
  const ProblemSlide({
    required this.sourceSlideNumber,
    this.title,
    required this.issueDescriptions,
    required this.hadImage,
    this.suggestedPolicy = SlideFailurePolicy.bestEffort,
  });

  /// 1-based source slide number shown to the user.
  final int sourceSlideNumber;

  /// Optional slide title to make the review dialog more recognisable.
  final String? title;

  /// Dutch descriptions of the conversion issues (from [ConversionIssue]).
  final List<String> issueDescriptions;

  /// Whether the source slide carried at least one image.
  final bool hadImage;

  /// Policy the import recommends for this slide based on its issues and image.
  final SlideFailurePolicy suggestedPolicy;
}
