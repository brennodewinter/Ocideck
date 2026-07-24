/// What the import does when a source slide cannot be converted perfectly (i.e.
/// it has at least one non-salvaged `ConversionIssue` — real loss).
///
/// Lives in `models/` (rather than `pipeline/`) so the import settings can hold
/// it without a models -> pipeline dependency.
enum SlideFailurePolicy {
  /// Keep the best-effort conversion and append a "not converted" note slide.
  /// This is the lossless default: everything that could be read is on the
  /// slide, everything that could not is named on the note beside it.
  bestEffort,

  /// Drop the slide's body entirely and leave a "slide skipped" note, so the
  /// loss is visible but no partial or misleading content is emitted. For a
  /// slide whose layout carried the meaning, half a conversion can be worse
  /// than none.
  skip,

  /// Keep only the slide's pictures, as an image slide, and drop its text.
  ///
  /// Named for what it does. The project this was ported from called this
  /// `rasterize` and leaned on an external LibreOffice process to render the
  /// source slide to a bitmap; that is deliberately unavailable here — the
  /// import starts no subprocess and adds no external dependency (#772). What
  /// that code actually did whenever a picture was present is exactly this:
  /// keep the pictures, drop the rest. A slide without a picture falls back to
  /// [skip], because an image slide without an image is nothing at all.
  imageOnly,
}
