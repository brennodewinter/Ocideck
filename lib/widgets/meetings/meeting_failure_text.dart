// Wat de schil toont als een vergadering niet doorgaat (§8.4, §18).
//
// Los van elk venster omdat het pure tekstkeuze is: geen toestand, geen
// widgets, en zo te toetsen zonder een dialoog te openen — dezelfde vorm als
// `export_failure_text.dart`.
//
// **Waarom de tekst hier staat en niet bij de adapter.** Een adapter mag geen
// zin meesturen; zou hij dat mogen, dan stuurt hij vroeg of laat een Engelse
// servermelding mee, en die staat dan onvertaald op het scherm van iemand die
// geen Engels leest. De adapter levert een [MeetingFailureKind] — een gesloten
// lijst — en dit bestand kiest er de vertaalde uitleg bij.
//
// **Elke tekst zegt twee dingen: wat er misging, en wat de gebruiker nu kan
// doen.** Een foutmelding praat tegen een mens die vastzit. "Toegang geweigerd"
// is waar en nutteloos; "de organisator heeft u niet toegelaten — vraag of hij
// u binnenlaat en probeer het opnieuw" is even waar en bruikbaar.
//
// **Wat er níet in staat: een schuldige.** Bij `anonymousJoinDisabled` gaat het
// om het beleid van een andere organisatie, en de eerlijke formulering is dat
// die organisatie gasten niet toelaat — niet dat OciDeck iets niet kan, en ook
// niet dat de gebruiker iets verkeerd deed.
import '../../l10n/app_localizations.dart';
import '../../meetings/meeting_failure.dart';
import '../../meetings/meeting_models.dart';

/// De uitleg bij [kind]: wat er misging en wat de gebruiker nu kan doen.
String meetingFailureText(
  AppLocalizations l10n,
  MeetingFailureKind kind,
) => switch (kind) {
  MeetingFailureKind.invalidLink => l10n.d(
    'Dit is geen bruikbare vergaderlink. Kopieer hem opnieuw uit de uitnodiging — een link die door een chatprogramma is afgekapt of aangepast, doet het vaak niet meer.',
  ),
  MeetingFailureKind.unsupportedMeetingType => l10n.d(
    'Deze dienst kennen we, maar dit soort vergadering niet. Webinars, uitzendingen en persoonlijke vergaderkamers werken anders dan een gewone vergadering; open deze link in de browser.',
  ),
  MeetingFailureKind.unknownProvider => l10n.d(
    'Deze vergaderdienst kennen we niet. OciDeck weet dus ook niet wat er achter deze link zit; u kunt hem in uw browser openen als u de afzender vertrouwt.',
  ),
  MeetingFailureKind.unsupportedPlatform => l10n.d(
    'Meedoen kan op deze uitvoering van OciDeck niet. Gebruik de webversie in uw browser.',
  ),
  MeetingFailureKind.unsupportedBrowser => l10n.d(
    'Deze browser mist iets wat voor meedoen nodig is. Een recente Chrome, Edge, Firefox of Safari lukt doorgaans wel.',
  ),
  MeetingFailureKind.anonymousJoinDisabled => l10n.d(
    'De organisatie van deze vergadering laat geen gasten zonder account toe. Vraag de organisator om u uit te nodigen op een manier die gasten toestaat.',
  ),
  MeetingFailureKind.accountRequired => l10n.d(
    'Meedoen aan deze vergadering vereist een account bij de aanbieder. Open de link in uw browser en meld u daar aan.',
  ),
  MeetingFailureKind.appApprovalRequired => l10n.d(
    'Deze aanbieder laat alleen goedgekeurde programma\'s meedoen, en die goedkeuring is er voor OciDeck nog niet. Open de vergadering in uw browser.',
  ),
  MeetingFailureKind.lobbyDenied => l10n.d(
    'De organisator heeft u niet toegelaten. Vraag of hij u binnenlaat en probeer het daarna opnieuw.',
  ),
  MeetingFailureKind.meetingLocked => l10n.d(
    'Deze vergadering is op slot; er komt niemand meer bij. Vraag de organisator om het slot eraf te halen.',
  ),
  MeetingFailureKind.e2eeMeetingUnsupported => l10n.d(
    'Deze vergadering is eind-tot-eind versleuteld en laat daarom geen externe deelnemers toe. Dat is een keuze van de organisator; vraag hem om een gewone vergadering als u erbij moet zijn.',
  ),
  MeetingFailureKind.permissionDenied => l10n.d(
    'OciDeck mag uw microfoon of camera niet gebruiken. Geef toestemming in uw browser of systeeminstellingen en probeer het opnieuw.',
  ),
  MeetingFailureKind.noMicrophone => l10n.d(
    'Er is geen werkende microfoon gevonden. Sluit er een aan of kies een ander apparaat.',
  ),
  MeetingFailureKind.noCamera => l10n.d(
    'Er is geen werkende camera gevonden. U kunt zonder beeld meedoen.',
  ),
  MeetingFailureKind.tokenBrokerUnavailable => l10n.d(
    'De dienst die het toegangsbewijs afgeeft is onbereikbaar. Probeer het later opnieuw; uw presentatie blijft ondertussen gewoon open.',
  ),
  MeetingFailureKind.tokenBrokerQuotaExceeded => l10n.d(
    'De dienst die het toegangsbewijs afgeeft heeft zijn grens voor nu bereikt. Probeer het later opnieuw.',
  ),
  MeetingFailureKind.credentialExpired => l10n.d(
    'Het toegangsbewijs voor deze vergadering is verlopen. Doe opnieuw mee met dezelfde link.',
  ),
  MeetingFailureKind.networkBlocked => l10n.d(
    'Het netwerk laat deze vergadering niet door. Op een bedrijfsnetwerk blokkeert een firewall of proxy dit soort verkeer vaak; een andere verbinding lukt meestal wel.',
  ),
  MeetingFailureKind.meetingEnded => l10n.d('Deze vergadering is voorbij.'),
  MeetingFailureKind.serviceUnavailable => l10n.d(
    'De vergaderdienst is zelf niet beschikbaar. Dit ligt niet aan uw verbinding; probeer het later opnieuw.',
  ),
  MeetingFailureKind.unknown => l10n.d(
    'Meedoen is niet gelukt, en de dienst zegt niet waarom. De technische code staat bij de details — probeer het opnieuw, en geef die code door als het blijft misgaan.',
  ),
};

/// De korte aanduiding van een fase, voor de statusindicator en de wachtstrip.
///
/// Bewust géén tekst voor `idle`: er is dan niets om te melden, en een label
/// zou de indicator laten bestaan terwijl er geen gesprek is.
String meetingPhaseLabel(AppLocalizations l10n, MeetingPhaseLabel label) =>
    switch (label) {
      MeetingPhaseLabel.preparing => l10n.d('Vergadering wordt voorbereid'),
      MeetingPhaseLabel.connecting => l10n.d('Verbinden met de vergadering'),
      MeetingPhaseLabel.waitingForAdmission => l10n.d(
        'Wachten op toelating door de organisator',
      ),
      MeetingPhaseLabel.connected => l10n.d('U doet mee aan de vergadering'),
      MeetingPhaseLabel.reconnecting => l10n.d(
        'De verbinding is weggevallen — opnieuw verbinden',
      ),
      MeetingPhaseLabel.leaving => l10n.d('De vergadering wordt verlaten'),
      MeetingPhaseLabel.ended => l10n.d('De vergadering is beëindigd'),
      MeetingPhaseLabel.failed => l10n.d('Meedoen is niet gelukt'),
    };

/// De fasen zoals de schil ze bénoemt — grover dan [MeetingPhase].
///
/// Vier voorbereidende fasen (`validating`, `permissionPrompt`, `preview`,
/// `provisioning`) heten voor de gebruiker allemaal "wordt voorbereid": het
/// verschil ertussen is techniek, en een indicator die vier keer van tekst
/// wisselt terwijl er niets gebeurt leest als onrust.
enum MeetingPhaseLabel {
  preparing,
  connecting,
  waitingForAdmission,
  connected,
  reconnecting,
  leaving,
  ended,
  failed,
}

/// Welk label bij [phase] hoort, of `null` wanneer er niets te melden is.
MeetingPhaseLabel? meetingPhaseLabelOf(MeetingPhase phase) => switch (phase) {
  MeetingPhase.idle => null,
  MeetingPhase.validating ||
  MeetingPhase.permissionPrompt ||
  MeetingPhase.preview ||
  MeetingPhase.provisioning => MeetingPhaseLabel.preparing,
  MeetingPhase.connecting => MeetingPhaseLabel.connecting,
  MeetingPhase.lobby => MeetingPhaseLabel.waitingForAdmission,
  MeetingPhase.connected => MeetingPhaseLabel.connected,
  MeetingPhase.reconnecting => MeetingPhaseLabel.reconnecting,
  MeetingPhase.leaving => MeetingPhaseLabel.leaving,
  MeetingPhase.ended => MeetingPhaseLabel.ended,
  MeetingPhase.failed => MeetingPhaseLabel.failed,
};
