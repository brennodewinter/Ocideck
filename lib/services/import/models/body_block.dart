/// The kind of a [BodyBlock].
enum BodyBlockKind { heading, paragraph, bullet, quote }

/// A single block of body text on a source slide.
///
/// The classifier reads these in [order] (the source's reading order:
/// top-to-bottom, left-to-right) to decide whether the slide is bullets,
/// a quote, free Markdown, etc. [level] encodes bullet/heading nesting; 0 is
/// top-level.
class BodyBlock {
  const BodyBlock({
    required this.kind,
    required this.text,
    this.level = 0,
    this.order = 0,
  });

  final BodyBlockKind kind;
  final String text;
  final int level;
  final int order;
}
