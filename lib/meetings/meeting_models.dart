// De aanbieder-neutrale bouwstenen van een onlinevergadering: wie je bent, wat
// je mag, wie er nog meer zijn en in welke fase het gesprek verkeert.
//
// Dit bestand is met opzet vrij van Flutter, van `dart:io` en van elke SDK. Het
// is de woordenschat die de schil (T14) en elke adapter delen, en dat werkt
// alleen als hij van geen van beide iets weet.
//
// Twee dingen die hier gebeuren zijn geen opmaak maar een grens:
//
//   * **Weergavenamen worden gesnoeid.** Een naam komt van een vreemde die je
//     niet kent, via een dienst die hem niet verifieert (T2). Nieuwe regels,
//     stuurtekens en een naam van vier kilobyte zijn geen randgeval maar de
//     eerste dingen die iemand probeert. Ze worden hier afgevangen, niet in de
//     widget die ze toevallig als laatste aanraakt.
//   * **Rechten volgen nooit uit een rol.** [MeetingCapabilities] komt van de
//     adapter en van niets anders. `COLLABORATION.md` §7.1.1 zegt het scherp:
//     leid geen bevoegdheid af uit het feit dat een knop zichtbaar is — en dus
//     ook niet uit het feit dat iemand "presenter" heet.

/// De stabiele sleutel van een adapter, als eigen type.
///
/// `COLLABORATION.md` schrijft op de ene plek `String get id` en op de andere
/// `MeetingProviderId get provider`; dat is één begrip met twee spellingen.
/// Hier wint het getypeerde: een kale `String` verwisselt net zo makkelijk met
/// een sessie-id, een rolnaam of een hostnaam, en dat merk je pas als er een
/// verkeerde adapter gekozen wordt.
class MeetingProviderId {
  const MeetingProviderId(this.value);

  /// De sleutel zelf: kort, kleine letters, stabiel over versies heen. Hij
  /// staat in logboeken en in het adapterhandvest (§7.1.6), dus hernoemen is
  /// een breuk.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is MeetingProviderId && other.value == value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

/// De vier vrijgavetoestanden uit `COLLABORATION.md` §7.1.4.
///
/// Machineleesbaar en niet decoratief: de schil mag een adapter onder
/// [research] of [spike] niet als deelnamemogelijkheid aanbieden, en een
/// verlopen handvest zet een adapter terug in plaats van de belofte stil te
/// laten staan.
enum MeetingProviderRelease { research, spike, experimental, supported }

/// Waar het gesprek in zijn leven staat (§8.1).
///
/// Overgenomen uit het ontwerp, met [lobby] als wat het daar sinds T15 is: een
/// toestand van de omlijsting, geen scherm. De naam blijft `lobby` omdat de
/// diensten die term gebruiken; wat de gebruiker ziet is "wachten op toelating".
enum MeetingPhase {
  /// Er loopt niets.
  idle,

  /// De link wordt lokaal getoetst.
  validating,

  /// De browser vraagt toestemming voor microfoon/camera.
  permissionPrompt,

  /// Apparaten gekozen, eigen beeld zichtbaar, nog niet verbonden.
  preview,

  /// Er wordt een toegangsbewijs opgehaald.
  provisioning,

  /// De verbinding wordt opgezet.
  connecting,

  /// Wachten tot een organisator toelaat.
  lobby,

  /// Meedoen.
  connected,

  /// De verbinding viel weg en wordt hersteld.
  reconnecting,

  /// De gebruiker stapt eruit.
  leaving,

  /// Afgelopen.
  ended,

  /// Mislukt; de reden staat in de bijbehorende `MeetingFailure`.
  failed,
}

/// De toegestane overgangen, precies het diagram uit §8.1 — plus twee
/// toevoegingen die het diagram nodig heeft om te kloppen met de rest van het
/// ontwerp, en die daarom hier hardop staan:
///
///   1. **Vanuit élke levende fase mag je weg.** §17 eist dat `Verlaten` in
///      iedere fase met het toetsenbord bereikbaar is; een tabel die dat niet
///      toestaat maakt die eis onwaar. Ook [validating] en [preview] mogen dus
///      naar [leaving].
///   2. **Vanuit een terminale fase mag je opnieuw beginnen.** [ended] en
///      [failed] gaan terug naar [idle] — dat is de reset, niet een tweede
///      poging vanuit een oude sessie.
///
/// Wat er níet bij staat is net zo belangrijk: er is geen weg van [lobby] naar
/// [preview] terug, en geen van [connected] naar [connecting]. Een adapter die
/// dat meldt, meldt iets wat niet gebeurd kan zijn.
const Map<MeetingPhase, Set<MeetingPhase>> meetingPhaseTransitions = {
  MeetingPhase.idle: {MeetingPhase.validating},
  MeetingPhase.validating: {
    MeetingPhase.permissionPrompt,
    MeetingPhase.leaving,
    MeetingPhase.failed,
  },
  MeetingPhase.permissionPrompt: {
    MeetingPhase.preview,
    MeetingPhase.leaving,
    MeetingPhase.failed,
  },
  MeetingPhase.preview: {
    MeetingPhase.provisioning,
    MeetingPhase.leaving,
    MeetingPhase.failed,
  },
  MeetingPhase.provisioning: {
    MeetingPhase.connecting,
    MeetingPhase.leaving,
    MeetingPhase.failed,
  },
  MeetingPhase.connecting: {
    MeetingPhase.lobby,
    MeetingPhase.connected,
    MeetingPhase.leaving,
    MeetingPhase.ended,
    MeetingPhase.failed,
  },
  MeetingPhase.lobby: {
    MeetingPhase.connected,
    MeetingPhase.leaving,
    MeetingPhase.ended,
    MeetingPhase.failed,
  },
  MeetingPhase.connected: {
    MeetingPhase.reconnecting,
    MeetingPhase.leaving,
    MeetingPhase.ended,
    MeetingPhase.failed,
  },
  MeetingPhase.reconnecting: {
    MeetingPhase.connected,
    MeetingPhase.leaving,
    MeetingPhase.ended,
    MeetingPhase.failed,
  },
  MeetingPhase.leaving: {MeetingPhase.ended, MeetingPhase.failed},
  MeetingPhase.ended: {MeetingPhase.idle},
  MeetingPhase.failed: {MeetingPhase.idle},
};

extension MeetingPhaseX on MeetingPhase {
  /// Of [next] een geldige volgende fase is. Naar zichzelf blijven staan mag
  /// altijd: een adapter die tweemaal hetzelfde meldt is vervelend, niet fout.
  bool canTransitionTo(MeetingPhase next) =>
      next == this || (meetingPhaseTransitions[this]?.contains(next) ?? false);

  /// Of er een sessie loopt waar de gebruiker nog iets mee moet kunnen.
  ///
  /// Alles behalve [idle] telt mee, inclusief [ended] en [failed]. Dat is een
  /// keuze: de poort van T13 hangt hieraan, en wie de module uitzet terwijl een
  /// gesprek net misliep, hoort de reden nog te kunnen lezen en wegklikken.
  /// Pas de reset naar [idle] laat de module echt verdwijnen.
  bool get isSessionActive => this != MeetingPhase.idle;

  /// Of er nog iets van of naar de aanbieder loopt. De schil hangt hier zijn
  /// knipperende statuslampje aan (T15).
  bool get isConnecting =>
      this == MeetingPhase.provisioning ||
      this == MeetingPhase.connecting ||
      this == MeetingPhase.lobby ||
      this == MeetingPhase.reconnecting;
}

/// De aanbieder-neutrale rolwoordenschat uit `COLLABORATION.md` §7.1.1.
///
/// Zes woorden voor een landschap waarin elke dienst zijn eigen begrippen
/// heeft. De oorspronkelijke naam van de aanbieder gaat niet verloren maar
/// reist mee als losse label (zie `MeetingState.providerRoleLabel`) — voor de
/// diagnose, niet om er rechten uit af te leiden.
enum MeetingRole { guest, attendee, presenter, moderator, organiser, unknown }

/// De knoppen die de schil kán tonen. [MeetingCapabilities] zegt per stuk of
/// dat vandaag mag (T12: mogelijkheid vóór knop).
enum MeetingControl { microphone, camera, screenShare, roster, leave }

/// Wat er in déze sessie, op dít moment, mogelijk is.
///
/// Live toestand, geen eigenschap van de sessie: een organisator kan een
/// deelnemer bevorderen, degraderen of het delen van het scherm intrekken
/// terwijl het gesprek loopt. De schil haalt een verdwenen knop meteen weg en
/// beëindigt de sessie níet.
class MeetingCapabilities {
  const MeetingCapabilities({
    this.canUseMicrophone = false,
    this.canUseCamera = false,
    this.canShareScreen = false,
    this.canSeeRoster = false,
  });

  /// Of de microfoon aan mag. Uit betekent hier "het beleid staat het niet
  /// toe", niet "de gebruiker heeft gedempt".
  final bool canUseMicrophone;

  /// Of er beeld verzonden mag worden.
  final bool canUseCamera;

  /// Of het scherm gedeeld mag worden.
  final bool canShareScreen;

  /// Of de deelnemerslijst opgevraagd mag worden.
  final bool canSeeRoster;

  /// Niets mag. De veilige beginwaarde: een adapter die nog niets gemeld heeft,
  /// heeft geen enkel recht toegezegd.
  static const MeetingCapabilities none = MeetingCapabilities();

  /// Of [control] getoond mag worden.
  ///
  /// [MeetingControl.leave] staat er los in en is altijd waar. Weggaan is geen
  /// gunst van de aanbieder: §17 eist dat `Verlaten` in elke fase bereikbaar
  /// blijft, en een adapter die het zou willen intrekken hoort dat niet te
  /// kunnen.
  bool allows(MeetingControl control) => switch (control) {
    MeetingControl.microphone => canUseMicrophone,
    MeetingControl.camera => canUseCamera,
    MeetingControl.screenShare => canShareScreen,
    MeetingControl.roster => canSeeRoster,
    MeetingControl.leave => true,
  };

  MeetingCapabilities copyWith({
    bool? canUseMicrophone,
    bool? canUseCamera,
    bool? canShareScreen,
    bool? canSeeRoster,
  }) => MeetingCapabilities(
    canUseMicrophone: canUseMicrophone ?? this.canUseMicrophone,
    canUseCamera: canUseCamera ?? this.canUseCamera,
    canShareScreen: canShareScreen ?? this.canShareScreen,
    canSeeRoster: canSeeRoster ?? this.canSeeRoster,
  );

  @override
  bool operator ==(Object other) =>
      other is MeetingCapabilities &&
      other.canUseMicrophone == canUseMicrophone &&
      other.canUseCamera == canUseCamera &&
      other.canShareScreen == canShareScreen &&
      other.canSeeRoster == canSeeRoster;

  @override
  int get hashCode =>
      Object.hash(canUseMicrophone, canUseCamera, canShareScreen, canSeeRoster);
}

/// Hoe de gebruiker zich bij deze aanbieder aandient (`COLLABORATION.md`
/// §7.1.6, "Identity, roles and dual-session consent").
///
/// "Geen account nodig" betekent per dienst iets anders, en dat verschil hoort
/// vóór het meedoen op het scherm te staan — niet als geruststelling achteraf.
enum MeetingIdentityKind {
  /// Alleen een zelfgekozen weergavenaam; niemand heeft die geverifieerd.
  anonymousDisplayName,

  /// Een tijdelijke gastidentiteit van de aanbieder, weg na afloop.
  ephemeralGuest,

  /// Een blijvende gastidentiteit uit een dienstaccount van een organisatie.
  serviceAppGuest,

  /// Een identiteit die de organisator voor deze deelnemer heeft klaargezet.
  hostSponsored,

  /// Een echt account bij de aanbieder.
  account,
}

/// Wat er over versleuteling te zeggen valt — met [unknown] als volwaardig
/// antwoord (T9).
///
/// De verleiding is om "versleuteld" te melden zodra er TLS onder zit. Dat is
/// waar en misleidend tegelijk: het zegt niets over wie er onderweg mee kan
/// kijken. Vandaar drie afzonderlijke woorden en een expliciet "we weten het
/// niet".
enum MeetingEncryptionClaim {
  /// Versleuteld naar de dienst toe; de dienst zelf kan meeluisteren.
  transportOnly,

  /// De aanbieder beheert de sleutels en beschrijft het zo.
  providerManaged,

  /// Werkelijk eind-tot-eind, sleutels bij de deelnemers.
  endToEnd,

  /// Niet vastgesteld. Zeg dat dan ook.
  unknown,
}

/// Hoever een adapter met deze uitnodiging kan komen (`COLLABORATION.md`
/// §7.1.1).
enum MeetingSupportLevel {
  /// OciDeck doet zelf mee, met zijn eigen schil.
  nativeClient,

  /// Meedoen kan, maar via de ingesloten officiële client van de aanbieder.
  embeddedOfficialClient,

  /// Alleen doorverwijzen naar de officiële webpagina van de aanbieder.
  redirectOnly,

  /// Deze uitnodiging gaat hier niet lukken.
  unsupported,
}

/// De verbindingskwaliteit, zoals de adapter hem meldt. Vier grove treden en
/// geen getallen: een percentage suggereert een precisie die geen enkele SDK
/// waarmaakt, en de gebruiker heeft aan "hapert" genoeg.
enum MeetingNetworkQuality { unknown, good, degraded, bad }

/// Hoeveel tekens een weergavenaam hoogstens mag zijn.
///
/// Ruim voor een echte naam, krap genoeg dat niemand er een alinea, een link of
/// een script in kwijt kan. §16.2: een kwaadaardige weergavenaam mag de
/// interface niet raken.
const int maxDisplayNameLength = 64;

/// Stuurtekens, regelscheiders en onzichtbare opmaaktekens — alles wat een naam
/// over meerdere regels, door de opmaak heen of van schrijfrichting zou laten
/// wisselen. Ze staan hier als code-punt en niet als teken: een letterlijke
/// U+202E in de bron is precies de verrassing die deze regel moet vangen, en de
/// conventiepoort verbiedt hem terecht.
final RegExp _controlCharacters = RegExp(
  '[\\u0000-\\u001F\\u007F-\\u009F\\u00AD\\u061C'
  '\\u200B-\\u200F\\u2028\\u2029\\u202A-\\u202E'
  '\\u2060-\\u2064\\u2066-\\u2069\\uFEFF\\uFFF9-\\uFFFB]',
);

/// Maak een weergavenaam veilig om te tonen: stuurtekens eruit, witruimte
/// samengetrokken, en afgekapt op [maxDisplayNameLength].
///
/// Dit gebeurt bij het bouwen van een [MeetingParticipant] en van een
/// `MeetingJoinRequest`, dus aan beide kanten van de grens: een naam die
/// binnenkomt en een naam die de deur uitgaat krijgen dezelfde behandeling.
String sanitizeDisplayName(String raw) {
  final flattened = raw
      .replaceAll(_controlCharacters, ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return flattened.length <= maxDisplayNameLength
      ? flattened
      : flattened.substring(0, maxDisplayNameLength).trimRight();
}

/// Eén deelnemer, zoals de adapter hem meldt.
///
/// De sleutel is [id] en nooit [displayName]: namen zijn niet uniek, niet
/// geverifieerd en veranderen tijdens het gesprek. Een lijst die op naam
/// indexeert, wisselt bij twee gelijknamige deelnemers stilletjes de tegels om.
class MeetingParticipant {
  MeetingParticipant({
    required this.id,
    required String displayName,
    this.role = MeetingRole.unknown,
    this.isMuted = true,
    this.isSpeaking = false,
    this.hasVideo = false,
    this.isSelf = false,
  }) : displayName = sanitizeDisplayName(displayName);

  /// De ondoorzichtige sleutel van de aanbieder. Hoort niet in een logboek
  /// (§16.4): tellen mag, benoemen niet.
  final String id;

  /// De naam die de deelnemer zelf opgaf — gesnoeid, en te tonen als platte
  /// tekst. Geen HTML, geen Markdown, geen link.
  final String displayName;

  final MeetingRole role;
  final bool isMuted;
  final bool isSpeaking;
  final bool hasVideo;

  /// Of dit de gebruiker zelf is.
  final bool isSelf;

  MeetingParticipant copyWith({
    String? displayName,
    MeetingRole? role,
    bool? isMuted,
    bool? isSpeaking,
    bool? hasVideo,
  }) => MeetingParticipant(
    id: id,
    displayName: displayName ?? this.displayName,
    role: role ?? this.role,
    isMuted: isMuted ?? this.isMuted,
    isSpeaking: isSpeaking ?? this.isSpeaking,
    hasVideo: hasVideo ?? this.hasVideo,
    isSelf: isSelf,
  );
}

/// Hoeveel tekens een diagnosecode hoogstens mag zijn.
///
/// Ruim genoeg voor elke echte code (`403`, `5854`, `CALL_FAILED`) en veel te
/// krap voor een zin, een URL of een stacktrace.
const int maxDiagnosticCodeLength = 32;

/// Alles wat geen code kán zijn. De spatie valt hier ook onder: die scheidt
/// woorden, en woorden zijn precies wat hier niet hoort.
final RegExp _unsafeInCode = RegExp(r'[^A-Za-z0-9._:-]');

/// Filter een aanbiedercode tot iets wat gegarandeerd geen inhoud draagt.
///
/// Dit is geen nette opmaak maar de poort zelf. Een SDK zet zijn foutmelding —
/// en daarmee soms de vergaderlink — in hetzelfde veld als zijn foutcode; wat
/// hier doorheen komt is een handvol tekens waar geen zin, adres of naam in
/// past. De volgorde is met opzet zo: éérst de verboden tekens eruit, dán
/// afkappen. Andersom zou een afgekapte melding er nog steeds als tekst uit
/// komen, alleen korter.
String? sanitizeDiagnosticCode(String? raw) {
  if (raw == null) return null;
  final filtered = raw.replaceAll(_unsafeInCode, '');
  if (filtered.isEmpty) return null;
  return filtered.length <= maxDiagnosticCodeLength
      ? filtered
      : filtered.substring(0, maxDiagnosticCodeLength);
}
