import 'conversion_issue.dart';
import 'source_slide.dart';
import 'source_theme.dart';

/// A parsed source presentation: deck-level metadata plus its [slides].
///
/// Each importer produces one of these; the pipeline then classifies the
/// slides and hands the deck-level [theme]/[author]/[title] to the writer for
/// the front matter and style profile. [issues] holds deck-wide losses (not
/// tied to a single slide) that become a trailing "not converted" note slide.
class SourceDeck {
  const SourceDeck({
    required this.slides,
    this.title = '',
    this.author = '',
    this.theme,
    this.issues = const [],
  });

  /// Slides in source order; indices match each slide's `index` field.
  final List<SourceSlide> slides;

  /// Deck title, from the source's core properties when available.
  final String title;

  /// Author, from the source's core properties (`dc:creator`) when available.
  final String author;

  /// Deck-wide theme salvaged from the source master/theme part.
  final SourceTheme? theme;

  /// Deck-wide conversion issues — losses not attributable to a single slide
  /// (e.g. a whole format whose internals the import cannot parse yet). The deck builder
  /// appends one trailing "not converted" note slide listing these.
  final List<ConversionIssue> issues;
}
