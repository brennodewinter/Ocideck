// Het lokaal herkennen van een uitnodiging (`COLLABORATION.md` §7.1.3, §12.1).
//
// Eén regel bepaalt de vorm van dit hele bestand: **er gaat hier niets het
// netwerk op.** Herkennen is ontleden, toetsen en vergelijken met een lijst die
// in de app zit. Een onbekende link wordt niet "even geprobeerd" bij elke
// ingestelde adapter — dat zou de link precies rondsturen langs partijen die
// hem niet horen te zien, en een vergaderlink is een sleutel: wie hem heeft,
// doet mee.
//
// Wat de resolver doet, in deze volgorde:
//
//   1. weigeren wat geen bruikbare uitnodiging is (schema, inloggegevens in de
//      URL, stuurtekens, onredelijke lengte, een ingebakken instelling);
//   2. schoonvegen wat niemand nodig heeft (fragment, bekende volgparameters),
//      zonder ook maar één teken aan het ondoorzichtige pad te veranderen;
//   3. hoogstens één adapter kiezen op een achtervoegselveilige hostvergelijking;
//   4. en anders eerlijk `onbekend` zeggen.
//
// Stap 3 is de plek waar het mis kan gaan en daarom expliciet
// achtervoegselveilig: `teams.microsoft.com.aanvaller.example` eindigt op
// `.example` en niet op `.microsoft.com`, hoe erg het er ook op lijkt. De
// vergelijking gebeurt op labelgrens (`host == h || host.endsWith('.$h')`), niet
// met `contains`.
import 'meeting_failure.dart';
import 'meeting_models.dart';

/// Wat de resolver van een adapter nodig heeft.
///
/// Bewust smaller dan `MeetingProvider`: zo hangt dit bestand niet aan het
/// sessiecontract, en kan een test een kandidaat van drie regels meegeven in
/// plaats van een halve adapter na te bouwen. `MeetingProvider` voldoet hieraan.
abstract interface class MeetingLinkCandidate {
  MeetingProviderId get id;

  /// De hostnamen die deze adapter herkent, in kleine letters en zonder punt
  /// ervoor. Een lege verzameling betekent: herkent niets op hostnaam.
  Set<String> get trustedHosts;

  /// Puur lokale herkenning. Mag geen netwerkverzoek doen en geen toestand
  /// aanraken; geeft `null` wanneer deze uitnodiging niet van deze adapter is.
  MeetingLinkMatch? match(Uri invitation);
}

/// Een herkende uitnodiging: van wie hij is, en de opgeschoonde link.
class MeetingLinkMatch {
  MeetingLinkMatch({
    required this.provider,
    required this.invitation,
    String? meetingKind,
  }) : meetingKind = sanitizeDiagnosticCode(meetingKind);

  /// Welke adapter hem herkende.
  final MeetingProviderId provider;

  /// De uitnodiging zoals hij naar de adapter gaat: fragment en volgparameters
  /// eraf, pad ongemoeid. Dit is vertrouwelijke, sleutelachtige gegevens — hij
  /// blijft op het apparaat en gaat nooit naar een tokendienst (T5).
  final Uri invitation;

  /// Het soort vergadering, in de woorden van de adapter, gefilterd tot een
  /// korte code. Voor de diagnose; er hangt geen gedrag aan.
  final String? meetingKind;

  /// Alleen de herkomst — schema, host en zo nodig poort. Dít is wat de
  /// gebruiker vóór het meedoen te zien krijgt, en wat in een logboek mag: het
  /// zegt wie er contact krijgt zonder de sleutel prijs te geven.
  String get displayOrigin => invitation.hasPort
      ? '${invitation.scheme}://${invitation.host}:${invitation.port}'
      : '${invitation.scheme}://${invitation.host}';
}

/// De uitkomst van het herkennen. Drie gevallen en niet één meer — een link is
/// bruikbaar, onbekend, of afgewezen met een reden.
sealed class MeetingLinkResolution {
  const MeetingLinkResolution();
}

/// Precies één adapter herkent deze uitnodiging.
final class MeetingLinkRecognised extends MeetingLinkResolution {
  const MeetingLinkRecognised(this.match);

  final MeetingLinkMatch match;
}

/// Een geldige HTTPS-link die geen enkele adapter kent.
///
/// Draagt alleen de herkomst en niet de hele link: dit is de toestand waarin de
/// gebruiker gevraagd wordt of hij die vreemde plek in zijn browser wil openen,
/// en daarvoor is de herkomst wat telt (§7.1.3 stap 7). OciDeck beweert hier
/// níet dat openen een vergadering start.
final class MeetingLinkUnrecognised extends MeetingLinkResolution {
  const MeetingLinkUnrecognised(this.origin);

  final String origin;
}

/// De link is als uitnodiging onbruikbaar.
final class MeetingLinkRejected extends MeetingLinkResolution {
  const MeetingLinkRejected(this.failure);

  final MeetingFailure failure;
}

/// Hoe lang een uitnodiging hoogstens mag zijn.
///
/// Ruim boven elke echte vergaderlink (die van Teams zit rond de 400 tekens) en
/// ver onder de lengte waarop het ontleden zelf werk wordt. §12.1 vraagt om een
/// grens; dit is hem.
const int maxInvitationLength = 2048;

/// Parameternamen die een uitnodiging niet mag dragen.
///
/// Een link is invoer van buiten. Wie hem stuurt mag níet kunnen bepalen welke
/// tokendienst OciDeck aanroept of welke instelling er geldt — dat is een
/// instellingskeuze van de gebruiker of de beheerder (T10). Zo'n parameter is
/// geen ruis om weg te poetsen maar een poging; de link wordt daarom afgewezen
/// en niet stilzwijgend opgeschoond.
const Set<String> forbiddenInvitationParameters = {
  'broker',
  'brokerurl',
  'broker_url',
  'tokenbroker',
  'token_broker',
  'ocideck_broker',
  'ocideck_config',
  'config_url',
  'configurl',
};

/// Parameters die niets met de vergadering te maken hebben en er alleen aan
/// hangen om iemands klik te tellen. Ze gaan eraf vóór de link opgeslagen of
/// getoond wordt.
const Set<String> trackingParameters = {
  'fbclid',
  'gclid',
  'dclid',
  'msclkid',
  'yclid',
  'twclid',
  'ttclid',
  'igshid',
  'mc_cid',
  'mc_eid',
  '_hsenc',
  '_hsmi',
};

/// Volgparameters komen ook als familie voor (`utm_source`, `utm_campaign`, …).
const String _trackingPrefix = 'utm_';

/// Kiest hoogstens één adapter bij een uitnodiging (`COLLABORATION.md` §7.1.3).
///
/// De lijst met kandidaten komt van buiten in plaats van uit een globale
/// variabele: zo is de resolver los te toetsen, en kan een latere ingestelde
/// deployment (§7.1.6) er zonder omweg bij.
class MeetingLinkResolver {
  const MeetingLinkResolver(
    this.candidates, {
    this.allowLocalDevelopment = false,
  });

  final List<MeetingLinkCandidate> candidates;

  /// Laat `http://localhost` toe. Alleen voor een lokale ontwikkelopstelling;
  /// staat standaard uit, want buiten die opstelling is een uitnodiging zonder
  /// TLS een uitnodiging die onderweg meegelezen is.
  final bool allowLocalDevelopment;

  /// Herken [raw] — de tekst zoals de gebruiker hem plakte.
  MeetingLinkResolution resolve(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty || trimmed.length > maxInvitationLength) {
      return _rejected(MeetingFailureKind.invalidLink);
    }
    if (_hasControlCharacter(trimmed)) {
      return _rejected(MeetingFailureKind.invalidLink);
    }
    final Uri parsed;
    try {
      parsed = Uri.parse(trimmed);
    } on FormatException {
      return _rejected(MeetingFailureKind.invalidLink);
    }
    final rejection = _reject(parsed);
    if (rejection != null) return _rejected(rejection);

    final sanitised = sanitizeInvitation(parsed);
    final candidate = _select(sanitised.host.toLowerCase());
    if (candidate == null) {
      return MeetingLinkUnrecognised(_originOf(sanitised));
    }
    final match = candidate.match(sanitised);
    // De adapter kent de host maar niet dít soort link: een gewone
    // navigatiepagina, een webinar, de persoonlijke variant. Dat is iets anders
    // dan "onbekend" en verdient een eigen uitleg (§12.1).
    if (match == null) {
      return _rejected(
        MeetingFailureKind.unsupportedMeetingType,
        provider: candidate.id,
      );
    }
    return MeetingLinkRecognised(match);
  }

  /// De harde weigeringen uit §12.1. Geeft `null` wanneer er niets mis is.
  MeetingFailureKind? _reject(Uri uri) {
    final scheme = uri.scheme.toLowerCase();
    final isLocalDevelopment =
        allowLocalDevelopment &&
        scheme == 'http' &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1');
    if (scheme != 'https' && !isLocalDevelopment) {
      return MeetingFailureKind.invalidLink;
    }
    if (uri.host.isEmpty) return MeetingFailureKind.invalidLink;
    // Inloggegevens in de URL: een klassieke vermomming
    // (`https://teams.microsoft.com@aanvaller.example`), en bovendien iets wat
    // per ongeluk in een logboek belandt.
    if (uri.userInfo.isNotEmpty) return MeetingFailureKind.invalidLink;
    for (final name in _parameterNames(uri)) {
      if (forbiddenInvitationParameters.contains(name)) {
        return MeetingFailureKind.invalidLink;
      }
    }
    return null;
  }

  /// De adapter met de langste passende host wint.
  ///
  /// Twee adapters die dezelfde host claimen is een fout in het register, geen
  /// keuze van de gebruiker; "de meest specifieke" is dan het enige antwoord
  /// dat niet van de volgorde in een lijst afhangt. Bij gelijke lengte wint de
  /// eerste — en dan is de volgorde van het register de beslissing, die
  /// tenminste ergens opgeschreven staat.
  MeetingLinkCandidate? _select(String host) {
    MeetingLinkCandidate? best;
    var bestLength = -1;
    for (final candidate in candidates) {
      for (final trusted in candidate.trustedHosts) {
        final normalised = trusted.toLowerCase();
        final matches = host == normalised || host.endsWith('.$normalised');
        if (matches && normalised.length > bestLength) {
          best = candidate;
          bestLength = normalised.length;
        }
      }
    }
    return best;
  }

  MeetingLinkResolution _rejected(
    MeetingFailureKind kind, {
    MeetingProviderId? provider,
  }) => MeetingLinkRejected(MeetingFailure(kind, provider: provider));
}

/// Schoon een uitnodiging op: fragment eraf, bekende volgparameters eruit.
///
/// Het pad blijft letterlijk staan. Dat is geen slordigheid maar de eis uit
/// §12.1: het is een ondoorzichtige waarde van de dienst, en wie hem decodeert
/// en opnieuw codeert krijgt een link terug die er hetzelfde uitziet en het niet
/// meer doet. Daarom wordt hier op de *tekst* geknipt en niet met
/// `Uri.replace` gewerkt, dat de query opnieuw zou coderen.
Uri sanitizeInvitation(Uri uri) {
  final text = uri.toString();
  final hashAt = text.indexOf('#');
  final withoutFragment = hashAt < 0 ? text : text.substring(0, hashAt);
  final queryAt = withoutFragment.indexOf('?');
  if (queryAt < 0) return Uri.parse(withoutFragment);
  final base = withoutFragment.substring(0, queryAt);
  final kept = [
    for (final pair in withoutFragment.substring(queryAt + 1).split('&'))
      if (pair.isNotEmpty && !_isTracking(_nameOf(pair))) pair,
  ];
  return Uri.parse(kept.isEmpty ? base : '$base?${kept.join('&')}');
}

/// De naam van een `naam=waarde`-paar, in kleine letters. Een paar zonder `=`
/// is helemaal naam.
String _nameOf(String pair) {
  final equals = pair.indexOf('=');
  return (equals < 0 ? pair : pair.substring(0, equals)).toLowerCase();
}

bool _isTracking(String name) =>
    trackingParameters.contains(name) || name.startsWith(_trackingPrefix);

/// De namen van alle queryparameters, in kleine letters — op de ruwe tekst,
/// zodat er niets gedecodeerd hoeft te worden om te kunnen weigeren.
Iterable<String> _parameterNames(Uri uri) sync* {
  final query = uri.query;
  if (query.isEmpty) return;
  for (final pair in query.split('&')) {
    if (pair.isNotEmpty) yield _nameOf(pair);
  }
}

String _originOf(Uri uri) => uri.hasPort
    ? '${uri.scheme}://${uri.host}:${uri.port}'
    : '${uri.scheme}://${uri.host}';

/// Stuurtekens in een geplakte link: onzichtbaar, en precies waarmee een host
/// er anders uit kan zien dan hij is.
bool _hasControlCharacter(String text) {
  for (final unit in text.codeUnits) {
    if (unit < 0x20 || unit == 0x7F) return true;
  }
  return false;
}
