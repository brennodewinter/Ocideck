// Het contract tussen OciDeck en een vergaderdienst (`COLLABORATION.md` §7.1.1).
//
// Twee typen, en het onderscheid daartussen is de hele architectuur:
// [MeetingProvider] weet dingen (welke links hij kent, wat er mogelijk is, wie
// er contact krijgt) en [MeetingSession] dóét dingen (een lopend gesprek). Een
// adapter levert feiten; hij levert nooit schermen (T14). Verschijnt er een
// adapter die een eigen scherm nodig lijkt te hebben, dan ontbreekt hier een
// begrip — dat is de plek om het toe te voegen, niet daar.
//
// Bewust géén `CollabTransport`. Een externe vergadering en een OciDeck-
// samenwerkingsruimte lijken op elkaar en zijn het niet: de eerste draait op
// andermans dienst, met andermans identiteiten, toelating en opnamebeleid. De
// E2EE-belofte van de samenwerkingskant geldt hier niet en mag hier niet
// overheen gelegd worden (T9).
//
// Afwijking van het ontwerp, hardop: §7.1/§8.2 van `TEAMS_GUEST_CLIENT.md`
// beschrijft een `MeetingClient` met `probe`/`requestPermissions`/`join`. Dat
// is de Teams-specifieke naad naar de JavaScript-brug toe, één laag dieper dan
// dit. De schil praat met `MeetingProvider`, precies zoals T14 en
// `COLLABORATION.md` §7.1.5 stap 1 voorschrijven; de ACS-adapter mag daar
// straks een `MeetingClient` achter zetten.
import 'meeting_event.dart';
import 'meeting_failure.dart';
import 'meeting_link.dart';
import 'meeting_models.dart';

/// Eén vergaderdienst waar OciDeck aan kan deelnemen.
abstract interface class MeetingProvider implements MeetingLinkCandidate {
  /// De stabiele sleutel van deze adapter.
  @override
  MeetingProviderId get id;

  /// Hoe ver deze adapter is (§7.1.4). De schil biedt `research` en `spike`
  /// niet als deelnamemogelijkheid aan.
  MeetingProviderRelease get release;

  /// De hostnamen die deze adapter herkent.
  @override
  Set<String> get trustedHosts;

  /// Puur lokale herkenning; geen netwerkverzoek (§7.1.3 stap 1–3).
  @override
  MeetingLinkMatch? match(Uri invitation);

  /// Zoekt uit wat er met déze uitnodiging mogelijk is.
  ///
  /// Mag pas gebeuren ná een uitdrukkelijke handeling van de gebruiker (§7.1.3
  /// stap 5, T8): dit is de eerste stap die de dienst van de aanbieder mag
  /// aanraken, en tot dan is OciDeck stil.
  Future<MeetingPreflight> preflight(MeetingLinkMatch link);

  /// Begint één sessie. Wortelgeschikt en niet per deck of tabblad (T6): een
  /// gesprek overleeft het wisselen van presentatie.
  Future<MeetingSession> join(MeetingJoinRequest request);
}

/// Een lopend gesprek.
///
/// Alle opdrachten zijn `Future`s omdat elke dienst ze op afstand uitvoert. Ze
/// zeggen niets over de uitkomst: de bevestiging komt langs [events], en de
/// schil toont pas iets als de gebeurtenis binnen is. Zo blijft een knop die
/// door beleid geweigerd wordt niet ten onrechte omstaan.
abstract interface class MeetingSession {
  MeetingProviderId get provider;

  /// De gebeurtenissen van deze sessie. Eén abonnee (de schil) volstaat; een
  /// adapter hoeft geen broadcast te bieden.
  Stream<MeetingEvent> get events;

  /// De laatst gemelde rechten en rol. Live toestand — vraag ze niet één keer
  /// op en onthoud ze niet.
  MeetingCapabilities get capabilities;
  MeetingRole get role;

  Future<void> setMicrophone(bool enabled);
  Future<void> setCamera(bool enabled);
  Future<void> startScreenShare();
  Future<void> stopScreenShare();

  /// Antwoord op een gevraagde uitdrukkelijke toestemming (§15). Alleen aan te
  /// roepen na een directe handeling van de gebruiker.
  Future<void> submitRecordingConsent(bool consent);

  /// Weggaan. Moet idempotent zijn: het sluiten van het venster, een klik en
  /// een verbroken verbinding kunnen elkaar kruisen (§6.5).
  Future<void> leave();

  /// Ruim alles op wat deze sessie vasthoudt. Ook idempotent, en ook veilig
  /// aan te roepen zonder voorafgaande [leave].
  Future<void> dispose();
}

/// Wat er met déze uitnodiging mogelijk is, uitgezocht vóór het meedoen.
///
/// Geen `bool`: "kan ik meedoen" heeft te veel verschillende antwoorden om er
/// één van te maken. Wie een account nodig heeft, wie in een wachtruimte
/// terechtkomt en wie alleen in de browser van de aanbieder terechtkan, horen
/// dat vóóraf te lezen — niet nadat het misging.
class MeetingPreflight {
  MeetingPreflight({
    required this.provider,
    required this.support,
    required this.identity,
    required this.encryption,
    this.capabilities = MeetingCapabilities.none,
    this.requiresAccount = false,
    this.requiresPassword = false,
    this.requiresRegistration = false,
    this.lobbyExpected = false,
    List<Uri> egressOrigins = const [],
    this.failure,
  }) : egressOrigins = [for (final uri in egressOrigins) _originOnly(uri)];

  final MeetingProviderId provider;

  /// Hoe ver deze adapter met deze uitnodiging komt.
  final MeetingSupportLevel support;

  /// Als wie de gebruiker zich aandient, en dus wat de anderen zien.
  final MeetingIdentityKind identity;

  /// Wat er over versleuteling te zeggen valt, met `unknown` als eerlijk
  /// antwoord (T9).
  final MeetingEncryptionClaim encryption;

  /// De rechten die de adapter vóóraf verwacht. Ze kunnen na toelating alsnog
  /// veranderen (§13.6) — dit is een verwachting, geen toezegging.
  final MeetingCapabilities capabilities;

  final bool requiresAccount;
  final bool requiresPassword;
  final bool requiresRegistration;

  /// Of er een wachtruimte te verwachten is. De schil kondigt dat vóóraf aan,
  /// zodat wachten geen storing lijkt (T15).
  final bool lobbyExpected;

  /// Wie er contact krijgt zodra de gebruiker meedoet — alleen de herkomsten,
  /// nooit hele adressen. Dit is de bekendmaking uit §6.2 stap 4, en die moet
  /// kloppen met wat er daadwerkelijk gebeurt.
  final List<Uri> egressOrigins;

  /// De stabiele reden waarom het níet gaat lukken, als dat zo is.
  final MeetingFailure? failure;

  /// Of OciDeck zelf mee kan doen.
  bool get canJoin =>
      failure == null && support == MeetingSupportLevel.nativeClient;

  /// Eén regel voor het logboek: de uitkomst, geen link en geen naam (§16.4).
  String get diagnosticLabel =>
      'preflight(${provider.value} support=${support.name} '
      'identity=${identity.name} e2ee=${encryption.name} '
      'lobby=$lobbyExpected origins=${egressOrigins.length}'
      '${failure == null ? '' : ' ${failure!.diagnosticLabel}'})';
}

/// De opdracht om mee te doen.
///
/// De weergavenaam wordt hier gesnoeid, aan de kant waar hij de deur uitgaat.
/// Dat is geen dubbelop met [MeetingParticipant]: wat OciDeck verstuurt en wat
/// OciDeck ontvangt zijn twee grenzen, en een naam met regelovergangen erin
/// hoort ook niet naar een andermans dienst te vertrekken.
class MeetingJoinRequest {
  MeetingJoinRequest({
    required this.link,
    required String displayName,
    this.startMuted = true,
    this.startWithVideo = false,
  }) : displayName = sanitizeDisplayName(displayName);

  /// De herkende uitnodiging. Blijft op het apparaat (T5).
  final MeetingLinkMatch link;

  /// De naam die de anderen zien. Zelf gekozen en door niemand geverifieerd —
  /// de schil zegt dat er ook bij (T2).
  final String displayName;

  /// Gedempt beginnen. De standaard, en geen instelling die stilletjes anders
  /// kan staan (§6.2 stap 7, §13.2).
  final bool startMuted;

  /// Met camera beginnen. Standaard niet.
  final bool startWithVideo;

  /// Of dit verzoek compleet genoeg is om te versturen. Een lege naam is het
  /// enige wat hier fout kan zijn — de link is al herkend.
  bool get isComplete => displayName.isNotEmpty;
}

/// Alleen schema, host en zo nodig poort. Een pad in een herkomstlijst is
/// bijna altijd per ongeluk, en zo'n pad kan een sleutel dragen.
Uri _originOnly(Uri uri) => Uri(
  scheme: uri.scheme,
  host: uri.host,
  port: uri.hasPort ? uri.port : null,
);
