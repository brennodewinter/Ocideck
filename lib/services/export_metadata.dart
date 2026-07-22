import '../models/deck.dart';
import '../models/document_signature.dart';
import 'privacy/privacy_projection.dart';

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

  /// De zichtbare handtekening op dekniveau, en het moment van verzegelen.
  ///
  /// Ze reizen sinds 0.1.0 niet meer mee in de front matter van de `.md` (ze
  /// wonen in `<naam>.seal.json`), en de HTML-export las ze daar tot dan uit
  /// terug. Zonder deze twee velden zou de akkoordpagina in het document dat de
  /// klant krijgt een kop met wit eronder worden — precies de pagina waar de
  /// verklaring hoort te staan.
  final DocumentSignature? signature;
  final String sealedAt;

  const ExportDocumentMetadata({
    this.title = '',
    this.author = '',
    this.organization = '',
    this.description = '',
    this.keywords = '',
    this.tlp = TlpLevel.none,
    this.signature,
    this.sealedAt = '',
  });

  /// De documentmetadata van een geprojecteerd deck.
  ///
  /// Bewust een [AudienceDeck] en geen rauwe [Deck]. Deze velden belanden
  /// leesbaar in de PDF-info, de PPTX-docProps en de HTML-kop — ook al staat er
  /// op geen enkele dia iets van te zien. Nam deze fabriek een `Deck`, dan was
  /// "vergeten te projecteren" hier een stille lek van precies de velden
  /// (`title`, `author`, `organization`, `description`, `keywords`) die de
  /// scanner deckbreed naloopt. Nu weigert de compiler het: een `AudienceDeck`
  /// is alleen door [PrivacyProjection] te maken.
  ///
  /// **De ondertekening is een uitzondering, en die moet u kennen.** Anders dan
  /// de vijf velden hierboven wordt [DocumentSignature] niet door de projectie
  /// geredigeerd: hij ís de akkoordverklaring en hoort zichtbaar te zijn op de
  /// ondertekeningsdia die de ontvanger krijgt. Het `AudienceDeck`-type
  /// garandeert dus dat het *deck* door de projectie is gegaan, niet dat dít
  /// veld is nagelopen. Dat was vóór 0.1.0 niet anders — de handtekening reisde
  /// toen als `ocideck_sig_*` mee in de front matter van dezelfde geprojecteerde
  /// markdown — maar daar was het een bijverschijnsel en hier is het een keuze,
  /// en een keuze hoort opgeschreven te staan.
  factory ExportDocumentMetadata.fromDeck(AudienceDeck audience) {
    final deck = audience.deck;
    return ExportDocumentMetadata(
      title: deck.title,
      author: deck.author,
      organization: deck.organization,
      description: deck.description,
      keywords: deck.keywords,
      tlp: deck.tlp,
      signature: deck.signature,
      sealedAt: deck.finalized ? deck.sealAt : '',
    );
  }

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
