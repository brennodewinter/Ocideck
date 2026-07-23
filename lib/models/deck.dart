import '../services/front_matter_merge.dart';
import 'privacy_disposition.dart';
import 'annotation.dart';
import 'document_signature.dart';
import 'seal_record.dart';
import 'slide.dart';
import 'used_tool.dart';
import 'settings.dart';
import '../services/miauw_codec.dart';
import '../services/privacy/dismissal_codec.dart';

/// Traffic Light Protocol-classificatie (FIRST TLP 2.0) van een presentatie.
///
/// De volgorde loopt van minst naar meest beperkend; [TlpLevel.index] is dus
/// bruikbaar om niveaus te vergelijken.
enum TlpLevel { none, clear, green, amber, amberStrict, red }

/// Of [slide] getoond mag worden wanneer de presentatie op [presentationTlp]
/// wordt gedeeld. Een slide wordt achtergehouden zodra zijn eigen TLP-niveau
/// strenger (hoger) is dan het voor de presentatie gekozen niveau.
bool slideVisibleAtTlp(Slide slide, TlpLevel presentationTlp) =>
    slide.tlp.index <= presentationTlp.index;

/// Of [slide] wordt *achtergehouden*: zijn eigen classificatie is strenger dan
/// die van de presentatie, dus hij haalt het publiek niet.
///
/// Bewust een eigen naam naast [Slide.skipped]. Achterhouden en overslaan zien
/// er in de uitvoer hetzelfde uit — de dia is er niet — maar het zijn twee
/// verschillende beslissingen: overslaan doet de auteur bewust per dia,
/// achterhouden volgt uit een classificatiebeleid dat hij misschien niet eens
/// heeft ingesteld (beide standaardwaarden zijn [TlpLevel.none], dus één dia op
/// AMBER verdwijnt uit een deck zonder deckniveau). Ze in de interface op één
/// hoop gooien laat de gebruiker de verkeerde knop zoeken.
bool slideWithheldByTlp(Slide slide, TlpLevel presentationTlp) =>
    !slideVisibleAtTlp(slide, presentationTlp);

/// Hoeveel dia's van [deck] worden achtergehouden door hun TLP-classificatie.
int withheldSlideCount(Deck deck) =>
    deck.slides.where((s) => slideWithheldByTlp(s, deck.tlp)).length;

/// Of [slide] het publiek bereikt bij presenteren of exporteren.
///
/// Drie onafhankelijke poorten, en een slide moet ze alle drie passeren: de
/// auteur sloeg hem over, zijn TLP-classificatie is strenger dan het niveau
/// waarop dit deck gedeeld wordt, of het is een verdiepingsslide terwijl de
/// beknopte versie wordt gemaakt. De assen staan bewust los van elkaar — TLP
/// vraagt *wie dit mag zien*, redactie vraagt *welke gegevens eruit mogen*, en
/// verdieping vraagt *hoeveel detail deze lezer wil*.
///
/// Dit is de énige plek waar die drie samenkomen. Ze stonden eerder tweemaal
/// uitgeschreven — in de slidelijst én in de indexvertaling van de
/// startselectie — en dat is precies hoe een vierde poort er straks op één van
/// beide plekken niet in belandt.
bool slideReachesAudience(
  Slide slide, {
  required TlpLevel presentationTlp,
  required bool includeDetail,
}) =>
    !slide.skipped &&
    slideVisibleAtTlp(slide, presentationTlp) &&
    (includeDetail || !slide.isDetail);

/// Strengste classificatie voor markering op een slide: het hoogste van het
/// deck-niveau en het per-slide niveau.
TlpLevel effectiveTlp({
  required TlpLevel deckTlp,
  required TlpLevel slideTlp,
}) => deckTlp.index >= slideTlp.index ? deckTlp : slideTlp;

/// De strengste classificatie in een héél deck: het hoogste van het deck-niveau
/// en elk slide-niveau. Waar [effectiveTlp] één slide markeert, is dit wat een
/// duurzame vrijgave (een review-PR of een release-tag, §9.4) moet toetsen —
/// één TLP:RED-slide in een TLP:none-deck telt dan mee. Dat is strenger dan de
/// export-gate, die alleen naar `deck.tlp` kijkt, en dus fail-safe.
TlpLevel deckReleaseTlp(Deck deck) => deck.slides.fold(
  deck.tlp,
  (strengste, slide) => effectiveTlp(deckTlp: strengste, slideTlp: slide.tlp),
);

extension TlpLevelX on TlpLevel {
  /// De officiële markering die op de slides verschijnt ('' bij [none]).
  String get label {
    switch (this) {
      case TlpLevel.none:
        return '';
      case TlpLevel.clear:
        return 'TLP:CLEAR';
      case TlpLevel.green:
        return 'TLP:GREEN';
      case TlpLevel.amber:
        return 'TLP:AMBER';
      case TlpLevel.amberStrict:
        return 'TLP:AMBER+STRICT';
      case TlpLevel.red:
        return 'TLP:RED';
    }
  }

  /// Tekst voor de keuzelijst.
  String get menuLabel => this == TlpLevel.none ? 'Geen' : label;

  /// Stabiele sleutel voor opslag in de front matter.
  String get key {
    switch (this) {
      case TlpLevel.none:
        return 'none';
      case TlpLevel.clear:
        return 'clear';
      case TlpLevel.green:
        return 'green';
      case TlpLevel.amber:
        return 'amber';
      case TlpLevel.amberStrict:
        return 'amber+strict';
      case TlpLevel.red:
        return 'red';
    }
  }

  /// Officiële TLP 2.0-voorgrondkleur (ARGB). Achtergrond is altijd zwart.
  int get foreground {
    switch (this) {
      case TlpLevel.none:
        return 0x00000000;
      case TlpLevel.clear:
        return 0xFFFFFFFF;
      case TlpLevel.green:
        return 0xFF33FF00;
      case TlpLevel.amber:
      case TlpLevel.amberStrict:
        return 0xFFFFC000;
      case TlpLevel.red:
        return 0xFFFF2B2B;
    }
  }

  static TlpLevel fromKey(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'clear':
        return TlpLevel.clear;
      case 'green':
        return TlpLevel.green;
      case 'amber':
        return TlpLevel.amber;
      case 'amber+strict':
      case 'amberstrict':
        return TlpLevel.amberStrict;
      case 'red':
        return TlpLevel.red;
      default:
        return TlpLevel.none;
    }
  }
}

class Deck {
  final String title;
  final String theme;
  final bool paginate;
  final List<Slide> slides;
  final String? projectPath;
  final ThemeProfile themeProfile;

  // ── General presentation metadata (stored in the markdown front matter) ──
  final String author;
  final String organization;
  final String version;
  final String date;
  final String description;
  final String keywords;

  /// The language the report is written in, as a language code (e.g. `nl`,
  /// `en`), or empty when not recorded. This is the **report's** language, not
  /// the interface language: a Dutch tester writing for an international client
  /// produces an English report from a Dutch UI. MIAUW EIS 2.3 requires it to be
  /// agreed and recorded up front, and it drives the localisation of rendered
  /// finding sections (PENTEST_MIAUW §12.3).
  final String language;

  /// De standaarden waartegen dit onderzoek is uitgevoerd, elk als
  /// `naam@versie` — bijvoorbeeld `OWASP WSTG@4.2`. Leeg wanneer niet
  /// vastgelegd. MIAUW EIS 4.3.2 vraagt om dit overzicht.
  ///
  /// **De versie staat hier bevroren, en dat is het hele punt.** Het zou
  /// eenvoudiger zijn om alleen de naam op te slaan en de versie bij het
  /// renderen uit het register van gebundelde standaarden te halen. Dan zou een
  /// rapport uit 2026, geopend in een OciDeck die inmiddels WSTG 5.0 meedraagt,
  /// beweren dat er tegen 5.0 is getoetst. Een rapport is een verantwoording
  /// achteraf: wat er stond moet blijven staan, ook als de wereld doorloopt.
  ///
  /// Precies dat maakt veroudering zonder netwerk zichtbaar — wat het deck
  /// noemt naast wat deze build bundelt, zie `outdatedStandards`.
  final List<String> standardsUsed;

  /// De hulpmiddelen die bij het onderzoek zijn gebruikt (MIAUW EIS 4.8.2).
  ///
  /// Een andere lijst dan [standardsUsed]: dit zijn de *tools* van de tester —
  /// naam, versie, publieke referentie, beschrijving — niet de standaarden
  /// waartegen is getoetst. Die twee zijn eerder verward, en het verschil is
  /// precies wat 4.8.2 van 4.3.2 scheidt.
  ///
  /// Vastleggen is niet hetzelfde als voldoen: de eis vraagt om een bijlage
  /// ín het rapport. Deze lijst voedt die bijlage, maar de tester bevestigt
  /// zelf dat hij er staat.
  final List<UsedTool> toolsUsed;

  /// Traffic Light Protocol-classificatie van deze presentatie.
  final TlpLevel tlp;

  /// Wat er met privacybevindingen gebeurt in dit deck. Slides kunnen dit per
  /// stuk overschrijven. Round-trips als `privacy:` in de front matter.
  final PrivacyDisposition privacy;

  /// Doeltijd (in seconden) voor de aftelling in de presenter. 0 = geen
  /// aftelling. Live aanpasbaar tijdens presenteren (toets K).
  final int presentationTargetSeconds;

  /// Of het tijden-overzicht (oefenrun-samenvatting) ná deze presentatie
  /// verschijnt. De tijd wordt ALTIJD gemeten; dit bepaalt enkel of het
  /// eindscherm getoond wordt. Per presentatie ingesteld (presentatie-info).
  final bool showRehearsalSummary;

  /// 'Alleen afspelen'-modus: is deze vlag gezet, dan wordt het deck vergrendeld
  /// tot presenteren. De editor, toolbar, menu's en sneltoetsen worden niet
  /// opgebouwd; enkel de eerste slide met een afspeelknop is zichtbaar. Bewust
  /// in de markdown-front-matter opgeslagen (inhoud van het bestand), zodat het
  /// deck als vergrendeld gedeeld kan worden. Uitzetten kan alleen door de
  /// front-matter-sleutel `ocideck_play_only` uit het bestand te halen.
  final bool playOnly;

  /// Documentintegriteit (§8 A1): is dit deck 'afgerond en verzegeld'? Een
  /// afgerond deck is bewust alleen-lezen — bekijken en exporteren kan, maar de
  /// inhoud is niet meer te bewerken.
  ///
  /// Die vergrendeling is sinds 0.1.0 méér dan een gemak: het zegel gaat over
  /// de bytes van de `.md`, dus élke herschrijving breekt het. Alleen-lezen is
  /// dus de manier waarop "verzegeld is bevroren" wordt afgedwongen in plaats
  /// van gehoopt.
  ///
  /// Opgeslagen in `<naam>.seal.json` naast het bestand (voorheen als
  /// `ocideck_finalized` in de front matter); zie [SealRecord].
  final bool finalized;

  /// Het zegel: een SHA-512-hash over de **bytes van de `.md`** waarin dit deck
  /// staat. Leeg wanneer het deck niet verzegeld is, of wanneer het net is
  /// afgerond maar nog niet opgeslagen — de hash kan pas bestaan zodra het
  /// bestand bestaat. Woont met de rest van het zegel in `<naam>.seal.json`.
  ///
  /// Zie [sealForm] voor de oude vorm, die over de gecanonicaliseerde inhoud
  /// ging in plaats van over de bytes.
  final String sealHash;

  /// Het gebruikte hash-algoritme voor [sealHash] (`sha-512`). Meegeslagen zodat
  /// een later algoritme herkenbaar blijft.
  final String sealAlgo;

  /// Waar [sealHash] over gaat: de bytes van het bestand, of — bij een deck van
  /// vóór 0.1.0 — de uitvoer van OciDecks eigen serialisator.
  final SealForm sealForm;

  /// Tijdstip van verzegelen als ISO-8601-string. Leeg wanneer niet verzegeld.
  final String sealAt;

  /// Optionele RFC 3161-tijdstempeltoken (`.tsr`) over [sealHash], base64url-
  /// gecodeerd (PENTEST_MIAUW §8-A2). Een externe TSA/OpenKAT tijdstempelt de
  /// hash out-of-band; van de geïmporteerde token vergelijkt OciDeck de imprint
  /// met [sealHash] — niet meer dan dat, zie `rfc3161_timestamp.dart`. Leeg
  /// wanneer er geen tijdstempel is. Woont in `<naam>.seal.json`.
  final String sealTimestampToken;

  /// De nonce (hex) uit het laatst geëxporteerde tijdstempelverzoek, zolang het
  /// antwoord nog niet binnen is. Leeg zodra er niets uitstaat.
  ///
  /// **Waarom dit bewaard wordt.** RFC 3161 §2.4.2 verplicht de TSA de nonce
  /// terug te kaatsen, en dát is waar hij voor dient: hij bindt één token aan
  /// één verzoek. Zonder de nonce te onthouden viel er bij het importeren niets
  /// te vergelijken — het verzoek gaat buiten de app om naar de TSA, en na een
  /// herstart was de andere helft weg. Een imprint-vergelijking alleen ziet het
  /// verschil niet tussen dit antwoord en een ouder token voor dezelfde hash.
  ///
  /// Woont in `<naam>.seal.json`, naast het token zelf. Ondoorzichtig en over
  /// het document in plaats van erin, dus hij hoort in de sidecar en niet in de
  /// markdown.
  final String sealTimestampNonce;

  /// De SHA-512 van de bestandsbytes waaruit dit deck is gelezen, of die er bij
  /// de laatste opslag voor zijn geschreven. Leeg voor een deck dat nooit een
  /// bestand is geweest.
  ///
  /// Bewust vluchtig: dit wordt nergens bewaard. Het is de *waargenomen*
  /// toestand van het bestand, waar [sealHash] de *vastgelegde* toestand is; het
  /// verschil tussen die twee is precies wat [DocumentIntegrity.verify] meldt.
  /// Zou het meereizen in een bestand, dan zou het zichzelf bevestigen.
  final String fileHash;

  /// Optionele zichtbare handtekening die bij het verzegelen is vastgelegd.
  /// Herbruikbaar element (zie [DocumentSignature]); null wanneer niet gezet.
  /// Woont met het zegel in `<naam>.seal.json`.
  final DocumentSignature? signature;

  /// Annotatielaag: vrije-hand-tekeningen per slide, gekeyd op [Slide.id].
  /// Bewust géén onderdeel van de Marp-markdown — dit wordt los bewaard in een
  /// sidecar zodat het deck pure, uitwisselbare Marp blijft.
  final Map<String, List<InkStroke>> annotations;

  /// Gebruikersnotities per slide (ontvanger/cursist), gekeyd op [Slide.id].
  /// Gescheiden van [Slide.notes] (sprekersnotities); bewust géén onderdeel
  /// van de Marp-markdown — opgeslagen in een aparte sidecar.
  final Map<String, String> userNotes;

  /// Privacybevindingen die de auteur bewust terzijde heeft gelegd (#651).
  ///
  /// Een oordeel over dít deck — "die naam hóórt hier" — en dus geen
  /// gebruikersvoorkeur: het reist met het document mee naar een tweede
  /// reviewer. Opgeslagen in een sidecar (`<naam>.dismissals.json`,
  /// FILE_FORMAT §6.7), niet in de `.md`, en het bewaart geen waarden maar
  /// commitments — zie `dismissal_codec.dart` voor waarom.
  ///
  /// Verbergen is geen wegscannen: de ongefilterde scan blijft het volle aantal
  /// zien, alleen het paneel filtert.
  final DeckDismissals? dismissals;

  /// De MIAUW-dispositie (PENTEST_MIAUW §9): uitsluitingen mét verplichte
  /// reden en handmatige klantbevestigingen, gekeyd op EIS-id, plus de
  /// grafstenen van ingetrokken besluiten. Opgeslagen in een sidecar
  /// (`<naam>.miauw.json`, FILE_FORMAT §6.5) en sinds #756 reist die ook mee
  /// naar een git-repository; de tijdstempels en grafstenen bestaan voor de
  /// merge daar (GIT_STORAGE §9.7).
  final MiauwDisposition miauw;

  /// De platte weergaven van [miauw] waar de leeslaag op leunt: EIS-id →
  /// motivering. Een uitgesloten requirement telt als "Uitgesloten door
  /// klant" in het compliance-overzicht; een handmatige bevestiging telt als
  /// "Voldaan" met de tag "Handmatig".
  Map<String, String> get miauwWaivers => miauw.waiverTexts;
  Map<String, String> get miauwConfirmations => miauw.confirmationTexts;

  /// De front-matter-regels zoals ze in het geopende bestand stonden (zonder de
  /// `---`-hekken). Leeg voor een deck dat nog geen bestand heeft.
  ///
  /// Hier staat álles in, ook wat OciDeck niet kent: een Marp-optie die deze
  /// build niet implementeert, een sleutel van een nieuwere versie, of gewoon
  /// een aantekening van de auteur. Bij opslaan werkt [mergeFrontMatter] alleen
  /// de sleutels bij die OciDeck bezit en laat de rest exact staan — dat is wat
  /// "Marp-compatibel" ook de andere kant op waar maakt.
  final List<String> frontMatterSource;

  /// De formaatversie die het bestand declareerde (`ocideck_format`), of
  /// [kOldestFormatVersion] als de sleutel ontbrak of onleesbaar was — en dat
  /// laatste is de normale toestand van elk handgeschreven Marp-bestand, nooit
  /// een fout.
  ///
  /// Bewust "wat het bestand zei", niet "wat deze build kan": opwaarderen
  /// gebeurt bij opslaan, niet bij openen (zie [persistedFormatVersion] en
  /// `docs/MIGRATION_GUIDE.md`). Andermans bestand raak je niet aan door het te
  /// bekijken.
  final int formatVersion;

  const Deck({
    required this.title,
    this.theme = 'ocideck',
    this.paginate = true,
    this.slides = const [],
    this.projectPath,
    this.themeProfile = const ThemeProfile(),
    this.author = '',
    this.organization = '',
    this.version = '',
    this.date = '',
    this.description = '',
    this.keywords = '',
    this.language = '',
    this.standardsUsed = const [],
    this.toolsUsed = const [],
    this.tlp = TlpLevel.none,
    this.privacy = PrivacyDisposition.warn,
    this.presentationTargetSeconds = 0,
    this.showRehearsalSummary = false,
    this.playOnly = false,
    this.finalized = false,
    this.sealHash = '',
    this.sealAlgo = '',
    this.sealForm = SealForm.fileBytes,
    this.sealAt = '',
    this.sealTimestampToken = '',
    this.sealTimestampNonce = '',
    this.fileHash = '',
    this.signature,
    this.annotations = const {},
    this.userNotes = const {},
    this.dismissals,
    this.miauw = const MiauwDisposition(),
    this.frontMatterSource = const [],
    this.formatVersion = kOldestFormatVersion,
  });

  Deck copyWith({
    String? title,
    String? theme,
    bool? paginate,
    List<Slide>? slides,
    String? projectPath,
    ThemeProfile? themeProfile,
    bool clearProjectPath = false,
    String? author,
    String? organization,
    String? version,
    String? date,
    String? description,
    String? keywords,
    String? language,
    List<String>? standardsUsed,
    List<UsedTool>? toolsUsed,
    TlpLevel? tlp,
    PrivacyDisposition? privacy,
    int? presentationTargetSeconds,
    bool? showRehearsalSummary,
    bool? playOnly,
    bool? finalized,
    String? sealHash,
    String? sealAlgo,
    SealForm? sealForm,
    String? sealAt,
    String? sealTimestampToken,
    String? sealTimestampNonce,
    String? fileHash,
    DocumentSignature? signature,
    bool clearSignature = false,
    Map<String, List<InkStroke>>? annotations,
    Map<String, String>? userNotes,
    DeckDismissals? dismissals,
    MiauwDisposition? miauw,
    List<String>? frontMatterSource,
    int? formatVersion,
  }) {
    return Deck(
      title: title ?? this.title,
      theme: theme ?? this.theme,
      paginate: paginate ?? this.paginate,
      slides: slides ?? this.slides,
      projectPath: clearProjectPath ? null : (projectPath ?? this.projectPath),
      themeProfile: themeProfile ?? this.themeProfile,
      author: author ?? this.author,
      organization: organization ?? this.organization,
      version: version ?? this.version,
      date: date ?? this.date,
      description: description ?? this.description,
      keywords: keywords ?? this.keywords,
      language: language ?? this.language,
      standardsUsed: standardsUsed ?? this.standardsUsed,
      toolsUsed: toolsUsed ?? this.toolsUsed,
      tlp: tlp ?? this.tlp,
      privacy: privacy ?? this.privacy,
      presentationTargetSeconds:
          presentationTargetSeconds ?? this.presentationTargetSeconds,
      showRehearsalSummary: showRehearsalSummary ?? this.showRehearsalSummary,
      playOnly: playOnly ?? this.playOnly,
      finalized: finalized ?? this.finalized,
      sealHash: sealHash ?? this.sealHash,
      sealAlgo: sealAlgo ?? this.sealAlgo,
      sealForm: sealForm ?? this.sealForm,
      sealAt: sealAt ?? this.sealAt,
      sealTimestampToken: sealTimestampToken ?? this.sealTimestampToken,
      sealTimestampNonce: sealTimestampNonce ?? this.sealTimestampNonce,
      fileHash: fileHash ?? this.fileHash,
      signature: clearSignature ? null : (signature ?? this.signature),
      annotations: annotations ?? this.annotations,
      userNotes: userNotes ?? this.userNotes,
      dismissals: dismissals ?? this.dismissals,
      miauw: miauw ?? this.miauw,
      frontMatterSource: frontMatterSource ?? this.frontMatterSource,
      formatVersion: formatVersion ?? this.formatVersion,
    );
  }

  /// Index of the first Informatieveiligheid slide (assets, finding,
  /// findingsSummary, checklist, scopeMatrix, signOff — see
  /// [SlideCategory.informationSecurity]),
  /// or -1 when there is none. The discovery prompt carries this index so the
  /// user can jump straight to the slide the message is about and check for
  /// themselves before deciding to switch the module on.
  int get firstSecuritySlideIndex => slides.indexWhere(
    (s) => s.type.category == SlideCategory.informationSecurity,
  );

  /// True when this deck carries any Informatieveiligheid slide type. Drives the
  /// one-time "enable the module" discovery prompt when such a deck is opened
  /// while the module is off; the slides render regardless (MODUS-REGEL).
  bool get hasSecuritySlides => firstSecuritySlideIndex >= 0;
}
