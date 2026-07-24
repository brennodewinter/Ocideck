/// A source slide that could not be converted perfectly, surfaced to the UI so
/// the user can decide what happens to it (#812).
///
/// Carries the 1-based, user-facing slide number, the human-readable issue
/// descriptions, and whether the slide has an image — that last one decides
/// whether "keep only the image" is offered at all, because without a picture
/// it is a button that cannot do anything.
///
/// Deliberately no "suggested policy" field. It existed, and the dialog used it
/// as the pre-selection, which made the default action destructive for any
/// slide with an image. The default is now always best-effort; advice that
/// overrides the safe default is not advice.
class ProblemSlide {
  const ProblemSlide({
    required this.sourceSlideNumber,
    this.title,
    required this.issueDescriptions,
    required this.hadImage,
  });

  /// 1-based source slide number shown to the user.
  final int sourceSlideNumber;

  /// Optional slide title to make the review dialog more recognisable.
  final String? title;

  /// Dutch descriptions of the conversion issues (from [ConversionIssue]).
  final List<String> issueDescriptions;

  /// Whether the source slide carried at least one image.
  final bool hadImage;
}
