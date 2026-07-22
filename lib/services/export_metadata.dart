import '../models/deck.dart';
import 'document_integrity.dart';
import 'privacy/privacy_projection.dart';

/// Application name embedded in PDF Creator / XMP CreatorTool.
const kOciDeckCreator = 'OciDeck';

/// Producer string embedded in PDF/PPTX metadata.
const kOciDeckProducer = 'OciDeck 0.2.0';

/// De machineleesbare markering voor inhoud die een AI heeft opgesteld en die
/// nog geen mens heeft nagekeken.
///
/// Bewust niet vertaald, net als [kOciDeckCreator] en de TLP-labels: dit is een
/// veld dat een gereedschap uitleest, geen zin die iemand op het scherm leest.
/// Vertalen zou de markering per taal een andere waarde geven en daarmee
/// onvindbaar maken voor precies degene die ernaar zoekt.
const kAiDraftKeyword = 'AI-generated (unreviewed)';

/// Dezelfde markering, maar dan als zin — voor de velden die een mens leest
/// (PDF/PPTX Subject, de eigenschappenkaart van een lezer).
const kAiDraftSubjectNote =
    'contains AI-drafted text that no human has checked';

/// Het achtervoegsel in de bestandsnaam van een export met ongecontroleerde
/// AI-tekst.
///
/// Om dezelfde reden als `PrivacyExportProfile.fileSuffix`: de duurste fout is
/// hier niet de export zelf maar de verwisseling — een concept dat als afgerond
/// rapport verder reist. Dat moet je aan de naam kunnen zien, zonder het bestand
/// te openen en zonder het te hoeven onthouden.
const kAiDraftFileSuffix = '-ai-concept';

/// Document metadata stamped into PDF, PPTX and HTML exports.
class ExportDocumentMetadata {
  final String title;
  final String author;
  final String organization;
  final String description;
  final String keywords;
  final TlpLevel tlp;

  /// Hoeveel dia's een AI-opgesteld veld dragen dat nog niet is nagekeken
  /// (`Slide.aiAssistedFields`, AI_ASSIST §16.3).
  ///
  /// Nul is het normale geval, en het blijft nul zodra de reviewpoort haar werk
  /// heeft gedaan: de markering is er om te verdwijnen. Een export van
  /// nagekeken inhoud meldt dus niets — dat is geen omissie maar precies waar
  /// de menselijke controle voor staat (AI-verordening art. 50, de uitzondering
  /// voor inhoud waar een mens redactionele verantwoordelijkheid voor neemt).
  final int unreviewedAiSlideCount;

  const ExportDocumentMetadata({
    this.title = '',
    this.author = '',
    this.organization = '',
    this.description = '',
    this.keywords = '',
    this.tlp = TlpLevel.none,
    this.unreviewedAiSlideCount = 0,
  });

  /// De documentmetadata van een geprojecteerd deck.
  ///
  /// Bewust een [AudienceDeck] en geen rauwe [Deck]. De zes auteursvelden
  /// belanden leesbaar in de PDF-info, de PPTX-docProps en de HTML-kop — ook al
  /// staat er op geen enkele dia iets van te zien. Nam deze fabriek een `Deck`,
  /// dan was "vergeten te projecteren" hier een stille lek van precies de velden
  /// (`title`, `author`, `organization`, `description`, `keywords`) die de
  /// scanner deckbreed naloopt. Nu weigert de compiler het: een `AudienceDeck`
  /// is alleen door [PrivacyProjection] te maken.
  ///
  /// [unreviewedAiSlideCount] hoort niet in dat rijtje. Het is geen veld dat de
  /// auteur invult maar een feit dat híér uit het deck wordt geteld, en dat is
  /// het verschil dat telt: een melding die je moet dóórgeven, kun je vergeten
  /// door te geven. Dezelfde redenering als hierboven, één laag dieper.
  factory ExportDocumentMetadata.fromDeck(AudienceDeck audience) {
    final deck = audience.deck;
    return ExportDocumentMetadata(
      title: deck.title,
      author: deck.author,
      organization: deck.organization,
      description: deck.description,
      keywords: deck.keywords,
      tlp: deck.tlp,
      unreviewedAiSlideCount: slidesWithUnreviewedAiMarkers(deck).length,
    );
  }

  /// Of deze export ongecontroleerde AI-tekst bevat en dat dus moet melden.
  bool get hasUnreviewedAi => unreviewedAiSlideCount > 0;

  /// Fallback title when [title] is empty.
  String displayTitle(String fallback) =>
      title.trim().isNotEmpty ? title.trim() : fallback;

  /// PDF/PPTX Subject — classificatie vooraan wanneer gezet, de AI-melding
  /// achteraan wanneer er ongecontroleerde AI-tekst in zit.
  ///
  /// De volgorde is niet willekeurig. TLP bepaalt of de ontvanger dit stuk
  /// überhaupt mag doorgeven en staat daarom vooraan; de AI-melding zegt iets
  /// over de betrouwbaarheid van de inhoud en hoort bij de inhoud.
  String subject(String fallbackTitle) {
    final name = displayTitle(fallbackTitle);
    final head = tlp == TlpLevel.none ? name : '${tlp.label} — $name';
    return hasUnreviewedAi ? '$head — $kAiDraftSubjectNote' : head;
  }

  /// Comma-separated keywords for PDF Info dict and PPTX core props.
  String exportKeywords() {
    final parts = <String>[];
    final deckKeywords = keywords.trim();
    if (deckKeywords.isNotEmpty) parts.add(deckKeywords);
    if (tlp != TlpLevel.none) {
      parts.addAll(['TLP', tlp.label, tlp.key]);
    }
    if (hasUnreviewedAi) parts.add(kAiDraftKeyword);
    parts.add('OciDeck');
    return parts.join(', ');
  }

  /// Het achtervoegsel dat de bestandsnaam van deze export moet dragen — leeg
  /// zodra de AI-tekst is nagekeken.
  String get fileSuffix => hasUnreviewedAi ? kAiDraftFileSuffix : '';

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

  /// De waarde van de `ai-generated`-meta in de HTML-export, of `null` wanneer
  /// er niets te melden valt. De tegenhanger van [htmlClassification].
  String? get htmlAiMarking => hasUnreviewedAi ? kAiDraftKeyword : null;
}
