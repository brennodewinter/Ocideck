/// What the import does when a source slide cannot be converted perfectly (i.e. it
/// has at least one non-salvaged [ConversionIssue] — real loss).
///
/// Lives in `models/` (rather than `pipeline/`) so the import settings can hold
/// it without a models -> pipeline dependency.
enum SlideFailurePolicy {
  /// Keep the best-effort conversion and append a "not converted" note slide.
  /// This is the lossless default and matches earlier behaviour.
  bestEffort,

  /// Drop the slide's body entirely and leave a "slide skipped" note so the
  /// loss is visible but no partial/incorrect content is emitted.
  skip,

  /// Replace the slide with a single large image (the slide's first picture)
  /// when one is available, dropping its text; otherwise behave like [skip].
  /// A "slide rasterised" note is appended. True rasterisation of arbitrary
  /// source slides is out of scope (no source-app renderer); this is the
  /// image-only salvage equivalent.
  rasterize,
}
