// Kentekens en buitenlandse postcodes: de twee regiogebonden contactregels.
//
// Allebei hangen ze aan het landpakket (§3-D, kolom ◐), en allebei om dezelfde
// reden: hun vorm is per land anders én per land botsend met iets onschuldigs.
//
// ── Waarom een kenteken een contextwoord verdient ───────────────────────────
//
// `XX-99-99` is een Nederlandse sidecode. Het is óók een artikelcode, een
// versieaanduiding en een zaalindeling. De RDW gebruikt inmiddels zestien
// sidecodes en die dekken samen zo'n beetje elke combinatie van twee tot drie
// letter- en cijfergroepen met streepjes — waardoor het patroon op zichzelf
// bijna niets uitsluit. §3-D beveelt daarom een contextwoord aan; wij maken het
// verplicht, want zonder contextwoord meet dit patroon vooral artikelnummers.
//
// ── Waarom buitenlandse postcodes lager scoren dan de Nederlandse ───────────
//
// De Nederlandse postcode heeft vier cijfers plus twee letters, en dat is
// specifiek genoeg om samen met een huisnummer één woonadres aan te wijzen. Een
// Duitse of Franse postcode is vijf kale cijfers; die vorm is niet te
// onderscheiden van een bedrag, een artikelnummer of een jaartal-plus-iets. Ze
// blijven dus `possible` en eisen een plaatsnaam of een landaanduiding in de
// buurt — precies de structuur die een adres van een getal onderscheidt.

/// De letteruitsluitingen van de Nederlandse kentekenreeksen.
///
/// De RDW geeft geen combinaties uit die als woord te lezen zijn, en laat de
/// klinkers grotendeels weg om verwarring met cijfers en met bestaande woorden te
/// voorkomen.
const Set<String> _forbiddenPlateGroups = {
  'SS',
  'SD',
  'SA',
  'NSB',
  'KKK',
  'PVV',
  'SGP',
  'TBS',
  'PSV',
};

/// De Nederlandse sidecodes 1 tot en met 14.
///
/// Ze staan er allemaal, en dat is nodig gebleken: een eerdere versie liet er een
/// paar weg "omdat ze elkaars spiegelbeeld zijn", en miste daardoor `12-ABC-3` —
/// sidecode 7, en al jaren de gewoonste vorm op de weg. Spiegelbeelden zijn ze
/// niet: `99-XXX-9` en `9-XXX-99` verschillen in welke groep één teken heeft.
///
/// Dat het patroon zó veel vormen dekt, is precies waarom de contextwoordeis
/// hieronder verplicht is en niet aanbevolen.
final RegExp dutchPlatePattern = RegExp(
  r'\b(?:'
  r'[A-Z]{2}-\d{2}-\d{2}' // 1  XX-99-99
  r'|\d{2}-\d{2}-[A-Z]{2}' // 2  99-99-XX
  r'|\d{2}-[A-Z]{2}-\d{2}' // 3  99-XX-99
  r'|[A-Z]{2}-\d{2}-[A-Z]{2}' // 4  XX-99-XX
  r'|[A-Z]{2}-[A-Z]{2}-\d{2}' // 5  XX-XX-99
  r'|\d{2}-[A-Z]{2}-[A-Z]{2}' // 6  99-XX-XX
  r'|\d{2}-[A-Z]{3}-\d' // 7  99-XXX-9
  r'|\d-[A-Z]{3}-\d{2}' // 8  9-XXX-99
  r'|[A-Z]{2}-\d{3}-[A-Z]' // 9  XX-999-X
  r'|[A-Z]-\d{3}-[A-Z]{2}' // 10 X-999-XX
  r'|[A-Z]{3}-\d{2}-[A-Z]' // 11 XXX-99-X
  r'|[A-Z]-\d{2}-[A-Z]{3}' // 12 X-99-XXX
  r'|\d-[A-Z]{2}-\d{3}' // 13 9-XX-999
  r'|\d{3}-[A-Z]{2}-\d' // 14 999-XX-9
  r')\b',
);

/// Contextwoorden die van een lettercijfergroep een kenteken maken.
const List<String> plateContextWords = [
  'kenteken',
  'nummerbord',
  'kentekenplaat',
  'voertuig',
  'auto',
  'licence plate',
  'license plate',
  'number plate',
  'vehicle',
  'kennzeichen',
  'fahrzeug',
  'plaque',
  'immatriculation',
  'matrícula',
  'targa',
];

/// Bevat een kentekenkandidaat een uitgesloten lettergroep?
bool isForbiddenPlate(String plate) {
  for (final group in plate.split('-')) {
    if (_forbiddenPlateGroups.contains(group.toUpperCase())) return true;
  }
  return false;
}

// ── Buitenlandse postcodes ───────────────────────────────────────────────────

/// Eén postcodevorm, met het land waaraan hij hangt.
class IntlPostcodeRule {
  /// De landcode; stuurt het regiopakket via `privacy_regions.dart`.
  final String region;
  final RegExp pattern;

  /// Extra bereikcontrole, waar het formaat alleen te weinig zegt.
  final bool Function(String value)? validate;

  const IntlPostcodeRule(this.region, this.pattern, {this.validate});

  /// Het regel-id waaronder een treffer gemeld wordt.
  ///
  /// Draagt de landcode vooraan, zodat de regiopoort hem herkent zonder een
  /// tweede koppellijst.
  String get ruleId => '$region.postcode';
}

/// De postcodevormen per land (§3-D: DE/FR/BE/PL/UK/US/CA).
///
/// Bewust géén Nederlandse: die heeft een eigen regel (`contact.postcode_nl`)
/// met een nabijheidsescalatie naar een huisnummer, en dat werkt alleen omdat de
/// NL-vorm specifiek genoeg is.
final List<IntlPostcodeRule> intlPostcodeRules = [
  // Vijf kale cijfers. Zeer FP-gevoelig, vandaar de contextwoordeis hieronder.
  IntlPostcodeRule('de', RegExp(r'(?<!\d)\d{5}(?!\d)')),
  IntlPostcodeRule('fr', RegExp(r'(?<!\d)\d{5}(?!\d)')),
  IntlPostcodeRule('pl', RegExp(r'(?<!\d)\d{2}-\d{3}(?!\d)')),
  // Belgische postcodes lopen van 1000 tot 9999 — nooit met een nul ervoor.
  // Zonder die grens is elk postbusnummer en elk jaartal er een.
  IntlPostcodeRule(
    'be',
    RegExp(r'(?<!\d)\d{4}(?!\d)'),
    validate: (value) => int.parse(value) >= 1000,
  ),
  // Het Britse formaat is juist heel specifiek en botst met vrijwel niets.
  IntlPostcodeRule(
    'uk',
    RegExp(r'\b[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}\b', caseSensitive: false),
  ),
  IntlPostcodeRule('us', RegExp(r'(?<!\d)\d{5}(?:-\d{4})?(?!\d)')),
  IntlPostcodeRule(
    'ca',
    RegExp(r'\b[A-Z]\d[A-Z] ?\d[A-Z]\d\b', caseSensitive: false),
  ),
];

/// Landen waarvan de postcodevorm te generiek is om zonder context te melden.
///
/// Vijf kale cijfers zijn ook een bedrag, een artikelnummer of een postbus.
/// Voor deze landen is een plaatsnaam- of adreswoord in de buurt verplicht; het
/// Britse en Canadese formaat hebben dat niet nodig.
const Set<String> postcodeNeedsContext = {'de', 'fr', 'be', 'us'};

/// Woorden die een getal tot een postcode maken.
///
/// `postbus` staat er bewust **niet** in, hoe verleidelijk het ook is: een
/// postbusnummer is precies het getal dat géén postcode is, en het staat er
/// altijd vlak naast. Dat leverde meteen een vals-positieve op de bestaande
/// testregel "Postbus 0123 AB bestaat niet" op.
const List<String> postcodeContextWords = [
  'postcode',
  'adres',
  'woonplaats',
  'straat',
  'zip',
  'zip code',
  'postal code',
  'plz',
  'postleitzahl',
  'code postal',
  'adresse',
  'wohnort',
  'kod pocztowy',
];
