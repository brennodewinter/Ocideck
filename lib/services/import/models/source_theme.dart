/// Colours and font extracted from a source theme/master.
///
/// Salvaged into OciDeck's `ocideck_style_profile` (FILE_FORMAT §3.2): the
/// accent becomes bullet markers and table borders, the title background
/// becomes the title-slide background, etc. Any null field falls back to
/// OciDeck's defaults, so a partial theme never breaks the profile.
class SourceTheme {
  const SourceTheme({
    this.accentColor,
    this.textColor,
    this.titleBackgroundColor,
    this.sectionBackgroundColor,
    this.slideBackgroundColor,
    this.fontFamily,
    this.footerText,
    this.showPageNumbers,
  });

  /// Hex (`#RRGGBB`) accent colour, e.g. a theme's primary fill.
  final String? accentColor;
  final String? textColor;
  final String? titleBackgroundColor;
  final String? sectionBackgroundColor;
  final String? slideBackgroundColor;

  /// Font family name from the theme's font scheme, when available.
  final String? fontFamily;

  /// Footer text from a slide master, when available.
  final String? footerText;

  /// Whether the master shows page numbers.
  final bool? showPageNumbers;
}
