import '../models/deck.dart';
import '../models/document_signature.dart';
import 'document_integrity.dart';
import 'privacy/privacy_projection.dart';

/// Application name embedded in PDF Creator / XMP CreatorTool.
const kOciDeckCreator = 'OciDeck';

/// De toepassingsversie (semver, zonder buildnummer): de ene plek waar hij
/// letterlijk staat.
///
/// `pubspec.yaml` blijft de bron van de waarheid — dit is een afgeleide
/// kopie, niet een tweede bron. Een Dart `const` kan `pubspec.yaml` niet op
/// compileertijd inlezen, dus de twee kunnen uiteenlopen als iemand alleen
/// hier of alleen daar de versie ophoogt. `test/version_consistency_test.dart`
/// vergelijkt ze bij elke testrun; die test faalt zodra ze niet meer gelijk
/// zijn.
const kOciDeckVersion = '0.4.10';

/// Producer string embedded in PDF/PPTX metadata.
const kOciDeckProducer = 'OciDeck $kOciDeckVersion';

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

  /// De taal waarin de inhoud van dit deck is geschreven, als BCP47-code
  /// (`nl`, `en`, `fi` …), of leeg wanneer niet vastgelegd. Dit is de
  /// **rapporttaal** (zie [Deck.language]), niet de interfacetaal: de
  /// HTML-export zet hier zijn `<html lang="…">` mee, zodat een schermlezer het
  /// deck in de taal van de inhoud voorleest in plaats van in het Nederlands
  /// (WCAG 2.1 SC 3.1.1). De chrome-strings van de export volgen deze taal
  /// waar OciDeck haar kent, en vallen anders terug op de interfacetaal.
  final String language;

  /// De zichtbare handtekening op dekniveau, en het moment van verzegelen.
  ///
  /// Ze reizen sinds 0.1.0 niet meer mee in de front matter van de `.md` (ze
  /// wonen in `<naam>.seal.json`), en de HTML-export las ze daar tot dan uit
  /// terug. Zonder deze twee velden zou de akkoordpagina in het document dat de
  /// klant krijgt een kop met wit eronder worden — precies de pagina waar de
  /// verklaring hoort te staan.
  final DocumentSignature? signature;
  final String sealedAt;

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
    this.language = '',
    this.signature,
    this.sealedAt = '',
    this.unreviewedAiSlideCount = 0,
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
      language: deck.language,
      signature: deck.signature,
      sealedAt: deck.finalized ? deck.sealAt : '',
      unreviewedAiSlideCount: slidesWithUnreviewedAiMarkers(deck).length,
    );
  }

  /// Of deze export ongecontroleerde AI-tekst bevat en dat dus moet melden.
  bool get hasUnreviewedAi => unreviewedAiSlideCount > 0;

  /// Dezelfde metadata, met de AI-markering opnieuw geteld uit [audience].
  ///
  /// Bedoeld voor het exportchokepoint, en daar is een reden voor. `metadata`
  /// is optioneel: een aanroeper die wél een `audience` meegeeft maar géén
  /// metadata, kreeg een terugvalexemplaar zonder markering — en dan gaat er
  /// ongecontroleerde AI-tekst de deur uit die zichzelf niet meldt. Erger nog:
  /// een aanroeper die zélf een `ExportDocumentMetadata` samenstelt, kon de
  /// telling op nul laten staan en zo de melding wegnemen zonder dat iets klaagt.
  ///
  /// Dit is precies waarom de andere velden hier al niet meer los reizen. De
  /// zes auteursvelden zijn keuzes van de auteur; het aantal dia's met
  /// ongecontroleerde AI-tekst is dat niet — dat is een feit over het deck.
  /// Feiten hoor je te tellen op de plek waar je ze kunt tellen, en dat is de
  /// ene poort waar PDF, PPTX en HTML alledrie langs komen.
  ExportDocumentMetadata withAiMarkingFrom(AudienceDeck audience) =>
      ExportDocumentMetadata(
        title: title,
        author: author,
        organization: organization,
        description: description,
        keywords: keywords,
        tlp: tlp,
        language: language,
        unreviewedAiSlideCount: slidesWithUnreviewedAiMarkers(
          audience.deck,
        ).length,
      );

  /// Houd alle documentmetadata gelijk en vervang alleen de classificatie.
  /// Documentexport dwingt hiermee de TLP uit de geprojecteerde bundel af,
  /// zodat een handmatig opgebouwd metadata-object de markering niet kan wissen.
  ExportDocumentMetadata withTlp(TlpLevel value) => ExportDocumentMetadata(
    title: title,
    author: author,
    organization: organization,
    description: description,
    keywords: keywords,
    tlp: value,
    language: language,
    signature: signature,
    sealedAt: sealedAt,
    unreviewedAiSlideCount: unreviewedAiSlideCount,
  );

  ExportDocumentMetadata withLanguage(String value) => ExportDocumentMetadata(
    title: title,
    author: author,
    organization: organization,
    description: description,
    keywords: keywords,
    tlp: tlp,
    language: value,
    signature: signature,
    sealedAt: sealedAt,
    unreviewedAiSlideCount: unreviewedAiSlideCount,
  );

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
