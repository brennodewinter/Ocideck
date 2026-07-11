import 'annotation.dart';
import 'document_signature.dart';
import 'slide.dart';
import 'settings.dart';

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

/// Strengste classificatie voor markering op een slide: het hoogste van het
/// deck-niveau en het per-slide niveau.
TlpLevel effectiveTlp({
  required TlpLevel deckTlp,
  required TlpLevel slideTlp,
}) => deckTlp.index >= slideTlp.index ? deckTlp : slideTlp;

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

  /// Traffic Light Protocol-classificatie van deze presentatie.
  final TlpLevel tlp;

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
  /// inhoud is niet meer te bewerken. Bewust in de markdown-front-matter
  /// (`ocideck_finalized`) opgeslagen, zodat de vergrendeling meereist met het
  /// bestand. Generaliseert dezelfde opslag-/parse-/gate-aanpak als [playOnly].
  final bool finalized;

  /// Het inhouds-zegel: een SHA-512-hash over de gecanonicaliseerde inhoud van
  /// het deck (exclusief de zegelvelden zelf, zodat de hash niet circulair is).
  /// Leeg wanneer het deck niet verzegeld is. Bij openen wordt de hash
  /// herberekend en vergeleken om wijziging-na-afronden zichtbaar te maken.
  final String sealHash;

  /// Het gebruikte hash-algoritme voor [sealHash] (`sha-512`). Meegeslagen zodat
  /// een later algoritme herkenbaar blijft.
  final String sealAlgo;

  /// Tijdstip van verzegelen als ISO-8601-string. Leeg wanneer niet verzegeld.
  final String sealAt;

  /// Optionele zichtbare handtekening die bij het verzegelen is vastgelegd.
  /// Herbruikbaar element (zie [DocumentSignature]); null wanneer niet gezet.
  final DocumentSignature? signature;

  /// Annotatielaag: vrije-hand-tekeningen per slide, gekeyd op [Slide.id].
  /// Bewust géén onderdeel van de Marp-markdown — dit wordt los bewaard in een
  /// sidecar zodat het deck pure, uitwisselbare Marp blijft.
  final Map<String, List<InkStroke>> annotations;

  /// Gebruikersnotities per slide (ontvanger/cursist), gekeyd op [Slide.id].
  /// Gescheiden van [Slide.notes] (sprekersnotities); bewust géén onderdeel
  /// van de Marp-markdown — opgeslagen in een aparte sidecar.
  final Map<String, String> userNotes;

  /// MIAUW-compliance-uitsluitingen (PENTEST_MIAUW §9), gekeyd op EIS-id
  /// (bijv. `1.6`) met de verplichte reden als waarde. Een uitgesloten
  /// requirement telt als "Uitgesloten door klant" in het compliance-overzicht.
  /// Reist mee in de front matter als `ocideck_miauw_waivers` (base64url-JSON).
  final Map<String, String> miauwWaivers;

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
    this.tlp = TlpLevel.none,
    this.presentationTargetSeconds = 0,
    this.showRehearsalSummary = true,
    this.playOnly = false,
    this.finalized = false,
    this.sealHash = '',
    this.sealAlgo = '',
    this.sealAt = '',
    this.signature,
    this.annotations = const {},
    this.userNotes = const {},
    this.miauwWaivers = const {},
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
    TlpLevel? tlp,
    int? presentationTargetSeconds,
    bool? showRehearsalSummary,
    bool? playOnly,
    bool? finalized,
    String? sealHash,
    String? sealAlgo,
    String? sealAt,
    DocumentSignature? signature,
    bool clearSignature = false,
    Map<String, List<InkStroke>>? annotations,
    Map<String, String>? userNotes,
    Map<String, String>? miauwWaivers,
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
      tlp: tlp ?? this.tlp,
      presentationTargetSeconds:
          presentationTargetSeconds ?? this.presentationTargetSeconds,
      showRehearsalSummary: showRehearsalSummary ?? this.showRehearsalSummary,
      playOnly: playOnly ?? this.playOnly,
      finalized: finalized ?? this.finalized,
      sealHash: sealHash ?? this.sealHash,
      sealAlgo: sealAlgo ?? this.sealAlgo,
      sealAt: sealAt ?? this.sealAt,
      signature: clearSignature ? null : (signature ?? this.signature),
      annotations: annotations ?? this.annotations,
      userNotes: userNotes ?? this.userNotes,
      miauwWaivers: miauwWaivers ?? this.miauwWaivers,
    );
  }
}
