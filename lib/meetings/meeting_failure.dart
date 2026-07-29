// De faaltaxonomie van een onlinevergadering (TEAMS_GUEST_CLIENT.md T11, §8.4).
//
// De regel die dit bestand afdwingt: **geen ruwe uitzondering bereikt ooit de
// gebruiker, en geen enkele mislukking wordt een eeuwige draaiende schijf.**
// Elke terminale afloop landt op één [MeetingFailureKind] — een gesloten,
// stabiele lijst — en de uitleg eromheen is de taak van de schil, niet van de
// adapter. Daarom staat er in dit bestand geen zichtbare tekst: een adapter die
// een zin zou mogen meesturen, stuurt vroeg of laat een servermelding mee.
//
// De tweede helft van diezelfde belofte is [MeetingFailure.code]. Een
// aanbiedercode helpt echt bij het uitzoeken van een storing, maar precies daar
// glipt de inhoud naar binnen: een SDK zet zijn foutmelding, en daarmee soms de
// vergaderlink, in hetzelfde veld. De code wordt daarom bij het bouwen
// gefilterd tot een korte, tekenbeperkte waarde (zie [_safeCode]) — dat is geen
// nette opmaak maar de poort zelf, en `meeting_log_redaction_test.dart` bewaakt
// hem.
//
// Waarom conservatief afbeelden. `anonymousJoinDisabled` zegt iets over het
// beleid van een andere organisatie. Een adapter mag die waarde alleen kiezen
// als een dienstcode het bewíjst; bij twijfel hoort een bredere, ware categorie
// met de code in de diagnose. Liever "het lukte niet, hier is de code" dan een
// zelfverzonnen verklaring waar de gebruiker zijn beheerder mee lastigvalt.
import 'meeting_models.dart';

/// Waarom een vergadering niet doorging.
///
/// De basis is §8.4 van het Teams-ontwerp; de aanbieder-neutrale namen uit
/// `COLLABORATION.md` §7.1.1 vallen hierop terug in plaats van ernaast te gaan
/// staan: `guestDisabled` is [anonymousJoinDisabled], `meetingTypeUnsupported`
/// is [unsupportedMeetingType] en `providerUnavailable` is [serviceUnavailable].
/// Eén naam per begrip — twee synoniemen in één taxonomie is hoe een `switch`
/// stil een geval mist.
enum MeetingFailureKind {
  /// De link is geen bruikbare uitnodiging: verkeerd schema, inloggegevens
  /// erin, stuurtekens, of onredelijk lang (§12.1).
  invalidLink,

  /// De link is herkend, maar dit soort vergadering ondersteunt de adapter
  /// niet (webinar, town hall, persoonlijke variant).
  unsupportedMeetingType,

  /// Geen enkele adapter herkent deze link. OciDeck beweert dan níet dat
  /// openen veilig een vergadering start (`COLLABORATION.md` §7.1.3).
  unknownProvider,

  /// Dit platform heeft geen ondersteunde route (bijvoorbeeld: de adapter
  /// bestaat alleen op web).
  unsupportedPlatform,

  /// De browser haalt de mogelijkhedenlat van de adapter niet.
  unsupportedBrowser,

  /// De organisatie staat gasten zonder account niet toe.
  anonymousJoinDisabled,

  /// Meedoen kan alleen met een account bij de aanbieder.
  accountRequired,

  /// De aanbieder eist eerst goedkeuring van OciDeck als toepassing.
  appApprovalRequired,

  /// De organisator heeft de deelnemer uit de wachtruimte geweigerd.
  lobbyDenied,

  /// De vergadering is op slot; er komt niemand meer bij.
  meetingLocked,

  /// De vergadering is eind-tot-eind versleuteld en laat externe deelnemers
  /// daarom niet toe (T9).
  e2eeMeetingUnsupported,

  /// De gebruiker of het systeem weigerde toegang tot microfoon/camera.
  permissionDenied,

  /// Geen bruikbare microfoon gevonden.
  noMicrophone,

  /// Geen bruikbare camera gevonden.
  noCamera,

  /// De tokendienst van de adapter is onbereikbaar.
  tokenBrokerUnavailable,

  /// De tokendienst weigert wegens quota of kostenrem (§11.4).
  tokenBrokerQuotaExceeded,

  /// Het toegangsbewijs verliep en vernieuwen lukte niet meer (§13.5).
  credentialExpired,

  /// Het netwerk laat de vergadering niet toe (geblokkeerde poorten, proxy).
  networkBlocked,

  /// De vergadering was al afgelopen.
  meetingEnded,

  /// De dienst van de aanbieder is zelf niet beschikbaar.
  serviceUnavailable,

  /// Onbekend. De eerlijke uitkomst wanneer niets anders bewezen is — geen
  /// gok die als verklaring leest.
  unknown,
}

/// Eén mislukking: het soort, en hoogstens een korte diagnosecode.
///
/// Wat hier bewust *niet* in zit: een melding, een uitzondering, de link, een
/// naam of een token. De vertaalde uitleg hoort bij de schil (§18), die per
/// [kind] een `l10n.d('…')` kiest; zo kan een adapter geen Engelse dienstnaam
/// of servertekst op het scherm krijgen.
class MeetingFailure {
  MeetingFailure(this.kind, {this.provider, String? code, String? subcode})
    : code = sanitizeDiagnosticCode(code),
      subcode = sanitizeDiagnosticCode(subcode);

  /// Waarom het misging.
  final MeetingFailureKind kind;

  /// Welke adapter het meldde, als er al één gekozen was.
  final MeetingProviderId? provider;

  /// De stabiele foutcode van de aanbieder, gefilterd. Alleen voor de
  /// diagnose-uitklap; nooit de uitleg zelf.
  final String? code;

  /// De verfijning daarvan (ACS noemt dit subcode), eveneens gefilterd.
  final String? subcode;

  /// Of deze afloop het einde is. Vandaag is elke [MeetingFailureKind] dat —
  /// de getter staat er zodat een latere herstelbare fout (een mislukte
  /// tokenvernieuwing die het oude token nog laat werken, §13.5) hier zijn
  /// plek krijgt in plaats van als uitzondering ergens langs de rand.
  bool get isTerminal => true;

  /// Eén regel voor het lokale logboek: het soort en de codes, verder niets
  /// (§16.4). Bewust géén `toString`-override — een `toString` wordt overal
  /// per ongeluk geïnterpoleerd, en dan is de rem die dit veld bedoelt te zijn
  /// juist de plek waar het lek ontstaat.
  String get diagnosticLabel {
    final buffer = StringBuffer('failure(${kind.name}');
    if (provider != null) buffer.write(' provider=${provider!.value}');
    if (code != null) buffer.write(' code=$code');
    if (subcode != null) buffer.write(' sub=$subcode');
    buffer.write(')');
    return buffer.toString();
  }
}
