import 'body_block.dart';
import 'source_chart.dart';
import 'source_image.dart';
import 'source_table.dart';
import 'source_theme.dart';
import 'source_video.dart';

/// A positioned text box on a source slide, kept for free-form salvage.
///
/// OciDeck has no free positioning: when a source slide places several text
/// boxes independently, the classifier merges them into bullets or free
/// Markdown in reading order and records the lost positioning as an issue.
/// This struct carries the raw geometry so the classifier can compute a
/// sensible top-to-bottom, left-to-right order.
class PositionedText {
  const PositionedText({
    required this.text,
    required this.left,
    required this.top,
    required this.width,
    required this.height,
  });

  final String text;

  /// Normalised coordinates (0..1) on the source slide canvas.
  final double left;
  final double top;
  final double width;
  final double height;
}

/// The format-neutral, intermediate representation of one source slide.
///
/// Each importer (PPTX/ODP/KEY) parses its native model into this shape; the
/// classifier then maps it onto an OciDeck slide type and the writer emits
/// Marp Markdown. Everything that might be salvaged — chart, table, video,
/// audio, theme, hyperlinks, notes — has a field here so the lossless
/// "not converted" note slide can be produced accurately.
class SourceSlide {
  const SourceSlide({
    required this.index,
    this.title = '',
    this.subtitle = '',
    this.bodyBlocks = const [],
    this.images = const [],
    this.chart,
    this.table,
    this.video,
    this.audioFileName,
    this.hyperlinks = const [],
    this.notes = '',
    this.comments = const [],
    this.theme,
    this.isHidden = false,
    this.isSection = false,
    this.positionedTexts = const [],
  });

  /// 0-based slide index in the source deck.
  final int index;

  final String title;
  final String subtitle;
  final List<BodyBlock> bodyBlocks;
  final List<SourceImage> images;
  final SourceChart? chart;
  final SourceTable? table;
  final SourceVideo? video;

  /// Local audio file name inside the archive, when the slide has audio.
  final String? audioFileName;

  /// Inline hyperlinks found in the slide text.
  final List<({String text, String url})> hyperlinks;

  /// Speaker notes.
  final String notes;

  /// Review comments (salvaged into user notes).
  final List<String> comments;

  /// Per-slide theme override; usually the deck-wide theme is applied, but a
  /// slide may carry its own colours.
  final SourceTheme? theme;

  /// Hidden slides become OciDeck `<!-- skip -->` slides.
  final bool isHidden;

  /// Section-divider slides become OciDeck `section` slides.
  final bool isSection;

  /// Raw positioned text boxes for free-form salvage.
  final List<PositionedText> positionedTexts;
}
