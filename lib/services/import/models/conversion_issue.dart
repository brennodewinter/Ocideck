/// A feature from a source slide that the import could not map to OciDeck.
///
/// The pipeline collects these per slide and, after the converted slide,
/// emits a free-Markdown "not converted" slide listing them — so the user
/// always knows what was dropped and nothing disappears silently.
class ConversionIssue {
  const ConversionIssue({
    required this.slideIndex,
    required this.feature,
    required this.description,
    this.salvagedAs,
  });

  /// 0-based index of the source slide this issue belongs to.
  final int slideIndex;

  /// Short label of the source feature, e.g. `SmartArt`, `merged cells`.
  final String feature;

  /// Human-readable explanation of what was not converted and why.
  final String description;

  /// If part of the feature was salvaged (e.g. SmartArt text → bullets),
  /// a short note of where it went. Null means nothing was salvaged.
  final String? salvagedAs;

  /// Whether any part of the feature was salvaged.
  bool get isSalvaged => salvagedAs != null && salvagedAs!.isNotEmpty;
}
