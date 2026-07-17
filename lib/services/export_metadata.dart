import '../models/deck.dart';

/// Application name embedded in PDF Creator / XMP CreatorTool.
const kOciDeckCreator = 'OciDeck';

/// Producer string embedded in PDF/PPTX metadata.
const kOciDeckProducer = 'OciDeck 0.2.0';

/// Document metadata stamped into PDF, PPTX and HTML exports.
class ExportDocumentMetadata {
  final String title;
  final String author;
  final String organization;
  final String description;
  final String keywords;
  final TlpLevel tlp;

  const ExportDocumentMetadata({
    this.title = '',
    this.author = '',
    this.organization = '',
    this.description = '',
    this.keywords = '',
    this.tlp = TlpLevel.none,
  });

  factory ExportDocumentMetadata.fromDeck(Deck deck) => ExportDocumentMetadata(
    title: deck.title,
    author: deck.author,
    organization: deck.organization,
    description: deck.description,
    keywords: deck.keywords,
    tlp: deck.tlp,
  );

  /// Fallback title when [title] is empty.
  String displayTitle(String fallback) =>
      title.trim().isNotEmpty ? title.trim() : fallback;

  /// PDF/PPTX Subject — classificatie vooraan wanneer gezet.
  String subject(String fallbackTitle) {
    final name = displayTitle(fallbackTitle);
    if (tlp == TlpLevel.none) return name;
    return '${tlp.label} — $name';
  }

  /// Comma-separated keywords for PDF Info dict and PPTX core props.
  String exportKeywords() {
    final parts = <String>[];
    final deckKeywords = keywords.trim();
    if (deckKeywords.isNotEmpty) parts.add(deckKeywords);
    if (tlp != TlpLevel.none) {
      parts.addAll(['TLP', tlp.label, tlp.key]);
    }
    parts.add('OciDeck');
    return parts.join(', ');
  }

  /// dc:creator / PDF Author — auteur, anders organisatie.
  String get documentAuthor {
    if (author.trim().isNotEmpty) return author.trim();
    if (organization.trim().isNotEmpty) return organization.trim();
    return 'OciDeck';
  }

  /// PDF Creator — de toepassing die het document heeft gemaakt.
  String get creator => kOciDeckCreator;

  String get producer => kOciDeckProducer;

  String? get htmlDescription =>
      description.trim().isNotEmpty ? description.trim() : null;

  String? get htmlClassification => tlp == TlpLevel.none ? null : tlp.label;
}
