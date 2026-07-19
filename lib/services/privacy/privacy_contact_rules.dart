// Adres, postcode en persoonsnaam.
//
// Dit is de familie die het lastigst te detecteren is, en de reden staat in de
// naam: een straat, een postcode en een naam hebben geen checksum. Er is niets
// dat "Kerkstraat 12" tot een geldig adres máákt zoals de mod-97 een IBAN tot een
// geldig IBAN maakt. Dus valt deze familie terug op het enige wat overblijft:
// vorm en samenhang.
//
// Drie keuzes sturen het ontwerp, alle drie in dienst van de
// vals-positieven-strategie (een scanner die te vaak roept, wordt uitgezet):
//
// 1. **Geen NER voor namen.** Een woord met een hoofdletter is geen naam — het is
//    ook het begin van een zin, een productnaam, een afdeling. We herkennen een
//    naam daarom alleen aan een aanhef (`dhr.`, `mevr.`) of een label (`naam:`,
//    `contactpersoon:`). Dat mist de kale naam in een titel — bewust: die is niet
//    te onderscheiden van de auteursvermelding, en de auteur is de afzender, geen
//    bevinding. Voor dat geval is er de handmatige `[[…]]`-markering.
//
// 2. **Adres en postcode los zijn hooguit een hint.** Een postcode op een
//    contactslide is vaak gewoon het kantooradres, en een straatnaam met een
//    nummer kan een verwijzing zijn. Elk voor zich blijft daarom `possible`
//    (informatief, onderbreekt niemand).
//
// 3. **Samen zijn ze een melding.** Postcode én huisnummer bij elkaar zijn in
//    Nederland vrijwel uniek identificerend — ze wijzen één woonadres aan. Staan
//    een straat-met-nummer en een postcode dicht bij elkaar (binnen
//    [kAddressLocationWindow] tekens), dan escaleren beide naar `certain`. Die
//    nabijheidseis is niet cosmetisch: een handleiding die ergens een
//    voorbeeldstraat noemt en tweehonderd regels verderop een voorbeeldpostcode,
//    is geen adres — en zou zonder die eis onterecht afgaan.

/// Straatnaam-achtervoegsels. Een straatnaam is een woord dat op een van deze
/// eindigt; het lijstje is Nederlands en bewust conservatief. De echte precisie
/// komt niet van dit lijstje maar van de huisnummereis erachter: "Beleid" is geen
/// adres, "Beleidsweg 12" wel.
const List<String> dutchStreetSuffixes = [
  'straat',
  'laan',
  'weg',
  'plein',
  'kade',
  'gracht',
  'dijk',
  'singel',
  'dreef',
  'plantsoen',
  'steeg',
  'boulevard',
  'hof',
  'pad',
  'park',
  'baan',
  'dwarsstraat',
];

/// Een straatnaam gevolgd door een huisnummer: `Kalverstraat 12`, `Beethovenln
/// 3A`.
///
/// De naam start met een ASCII-hoofdletter (straatnamen doen dat), mag daarna
/// accenttekens bevatten, en eindigt op een achtervoegsel uit
/// [dutchStreetSuffixes]. Het huisnummer is één tot vier cijfers met een optionele
/// toevoegingsletter. Zonder dat nummer vuurt de regel niet — dat nummer is wat
/// een straatnaam van een gewoon woord onderscheidt.
final RegExp streetAddressPattern = RegExp(
  r"\b[A-Z][a-zà-öø-ÿ.'\-]*(?:"
  '${dutchStreetSuffixes.join('|')}'
  r')\s+\d{1,4}\s?[a-zA-Z]?\b',
);

/// Een Nederlandse postcode: vier cijfers (niet met een nul beginnend), een
/// optionele spatie, twee hoofdletters. `1234 AB`, `1234AB`.
///
/// De hoofdlettereis doet echt werk: `2026 rc` in lopende tekst is geen postcode,
/// `2026 RC` mogelijk wel. De `#`-uitsluiting (zie [postcodeBoundaryOk]) houdt
/// hexkleuren als `#2563EB` eruit — die hebben precies deze vorm.
final RegExp dutchPostcodePattern = RegExp(r'\b[1-9]\d{3} ?[A-Z]{2}\b');

/// Lettercombinaties die in Nederlandse postcodes niet worden uitgegeven.
const Set<String> _forbiddenPostcodeLetters = {'SA', 'SD', 'SS'};

/// Is dit een geloofwaardige postcode? De vorm zit al in de regex; hier valt de
/// handvol niet-uitgegeven lettercombinaties af.
bool isPlausibleDutchPostcode(String raw) {
  final letters = raw.substring(raw.length - 2).toUpperCase();
  return !_forbiddenPostcodeLetters.contains(letters);
}

/// Staat een postcodetreffer op een echte woordgrens?
///
/// De regex-`\b` behandelt `#` als een grens, en dus zou `#2563EB` als postcode
/// tellen. Deze extra poort sluit een voorafgaande `#` (hexkleur) uit; de rest
/// van de woordgrens regelt de regex zelf.
bool postcodeBoundaryOk(String text, int start) {
  if (start == 0) return true;
  return text.codeUnitAt(start - 1) != 0x23; // '#'
}

/// Hoe dicht een straat-met-nummer en een postcode bij elkaar mogen staan om
/// samen als één woonadres te gelden. Ruim genoeg voor "Kalverstraat 12, 1234 AB
/// Amsterdam", krap genoeg dat twee losse voorbeelden in een lange tekst niet per
/// ongeluk een adres vormen.
const int kAddressLocationWindow = 40;

// ── Namen ────────────────────────────────────────────────────────────────────

/// Eén naamtoken: een hoofdletter (ook met accent) gevolgd door kleine letters.
const String _nameToken = r"[A-ZÀ-ÖØ-Þ][a-zà-öø-ÿ'’.\-]*";

/// De Nederlandse (en enkele anderstalige) tussenvoegsels.
const String _nameInfix =
    r"(?:van|de|der|den|ter|te|von|'t|op|bin|al|el|da|do|dos)";

/// Een persoonsnaam: één tot vier tokens, met tussenvoegsels ertussen.
/// "Jan Jansen", "Marieke de Vries", "Jan van der Berg", "Herr Müller".
const String _namePart =
    '$_nameToken(?:[ \\-]$_nameInfix\\b|[ \\-]$_nameToken){0,3}';

/// Een naam achter een expliciet label: `naam: Jan Jansen`,
/// `Contactpersoon = Marieke de Vries`, `t.a.v. J. de Boer`.
///
/// De naam zit in groep 1 en staat aan het eind van de match, zodat de scanner
/// zijn positie kan afleiden zonder groepsoffsets (die Dart niet los geeft).
final RegExp nameLabelPattern = RegExp(
  r'\b(?:[Nn]aam|[Vv]oornaam|[Aa]chternaam|[Vv]olledige naam|[Cc]ontactpersoon|'
  r'[Gg]eadresseerde|[Bb]etrokkene|[Oo]ndergetekende|[Tt]\.a\.v\.?|[Aa]ttn|'
  r'[Pp]atiëntnaam|[Cc]liëntnaam)\s*[:=]\s*'
  '($_namePart)',
);

/// Een naam achter een aanhef: `dhr. Jansen`, `Mevrouw De Boer`, `Dr. Müller`.
final RegExp nameSalutationPattern = RegExp(
  r'\b(?:[Dd]hr|[Mm]evr|[Mm]w|[Mm]evrouw|[Mm]eneer|[Dd]e heer|[Hh]err|[Ff]rau|'
  r'[Mm]me|[Mm]lle|[Dd]r|[Ii]r|[Ii]ng|[Pp]rof|[Mm]r|[Mm]rs)\.?\s+'
  '($_namePart)',
);

// ── Namen die de structuur bevestigt ─────────────────────────────────────────
//
// De aanhef en het label hierboven zijn de goedkope gevallen: de auteur schrijft
// er letterlijk bij dat dit een persoon is. Maar de formulering waar artikel 10
// nu juist over gaat draagt geen label:
//
//     Marieke de Vries wordt verdacht van diefstal
//
// Geen `naam:`, geen `mevr.` — en tóch is dit onmiskenbaar een persoon, want er
// staat een werkwoord achter dat alleen over mensen gaat. Dat is de opening die
// hieronder gebruikt wordt, en het is nadrukkelijk géén NER: we zoeken niet naar
// namen en kijken dan of er een persoon bij hoort, we zoeken naar structuren die
// een persoon aankondigen en lezen de naam daaruit af. Twee ervan:
//
//   1. een **persoonspredicaat** — een werkwoordsvorm die geen ander onderwerp
//      kan hebben dan een mens ("wordt verdacht van", "meldde zich ziek");
//   2. een **e-mailadres dat de naam bevestigt** — staat er "Marieke de Vries"
//      naast `m.devries@acme.nl`, dan bevestigen twee onafhankelijke structuren
//      elkaar, en dat is sterker bewijs dan elk van beide apart.
//
// Beide poorten eisen dat het kandidaat-naampatroon al klopt. Een losse
// hoofdletter passeert nooit: zonder predicaat en zonder bevestigend adres wordt
// er niets gemeld. Dat is precies de grens uit §5.5, en die blijft staan.

/// Werkwoordsvormen die alleen een mens als onderwerp kunnen hebben.
///
/// Bewust smal en bewust in de derde persoon: dit zijn de formuleringen waarin
/// een dossier, een verslag of een briefing over iemand spreekt. Een algemener
/// lijstje ("werkt bij", "zei dat") zou organisaties en producten meenemen, en
/// dan is de poort geen poort meer.
///
/// NL/EN/DE/FR/ES. Data, geen UI — deze woorden worden nooit getoond, alleen
/// gematcht, dus ze gaan niet door de l10n heen.
const List<String> personPredicates = [
  // Strafrechtelijk (art. 10)
  r'wordt verdacht', r'werd verdacht', r'is aangehouden', r'werd aangehouden',
  r'is veroordeeld', r'werd veroordeeld', r'is gedagvaard', r'zit vast',
  r'is suspected', r'was arrested', r'was convicted', r'was charged',
  r'wird verdächtigt', r'wurde verhaftet', r'wurde verurteilt',
  r'est soupçonné', r'a été arrêté', r'a été condamné',
  r'es sospechoso', r'fue detenido', r'fue condenado',
  // Gezondheid (art. 9)
  r'meldde zich ziek', r'meldt zich ziek', r'is opgenomen', r'is overleden',
  r'is gediagnosticeerd', r'wordt behandeld', r'lijdt aan', r'is zwanger',
  r'called in sick', r'was diagnosed', r'is pregnant', r'suffers from',
  r'ist schwanger', r'leidet an', r'wurde diagnostiziert',
  r'est enceinte', r'souffre de',
  r'está embarazada', r'sufre de',
];

/// Een naam gevolgd door een persoonspredicaat.
///
/// De naam zit in groep 1 en staat aan het **begin** van de match, dus zijn
/// positie is `match.start` — anders dan bij de label- en aanhefpatronen, waar
/// hij achteraan staat.
final RegExp namePredicatePattern = RegExp(
  '\\b($_namePart)\\s+(?:${personPredicates.join('|')})\\b',
);

/// Kandidaat-namen, zonder enig oordeel of het er een is.
///
/// Alleen bruikbaar in combinatie met een bevestiging (zie
/// [emailConfirmsName]): op zichzelf matcht dit elk woord met een hoofdletter,
/// inclusief het eerste woord van elke zin. Nooit los gebruiken.
final RegExp nameCandidatePattern = RegExp('\\b$_namePart\\b');

/// Bevestigt het lokale deel van [email] de naam [name]?
///
/// De toets is bewust streng, want dit is de poort die een kale hoofdletter tot
/// een gemelde persoonsnaam promoveert. Vereist:
///
///   * de **achternaam** (het laatste naamtoken van minstens drie letters) komt
///     voor in het lokale deel — `m.devries` bevat `vries`;
///   * én de **voornaam** komt er voor, óf het lokale deel begint met de
///     beginletter ervan — `m.devries` begint met de `m` van Marieke.
///
/// Zonder die tweede eis zou `devries@acme.nl` élke Vries op de slide
/// bevestigen, en dat is een achternaam die duizenden mensen delen.
bool emailConfirmsName(String email, String name) {
  final at = email.indexOf('@');
  if (at <= 0) return false;
  final local = _lettersOnly(email.substring(0, at));
  if (local.isEmpty) return false;

  final tokens = [
    for (final raw in name.split(RegExp(r'[\s\-]+')))
      if (_lettersOnly(raw).isNotEmpty) _lettersOnly(raw),
  ];
  if (tokens.length < 2) return false;

  final surname = tokens.last;
  if (surname.length < 3 || !local.contains(surname)) return false;

  final given = tokens.first;
  if (given.isEmpty) return false;
  return local.contains(given) || local.startsWith(given[0]);
}

/// Alleen de letters, in kleine letters. Punten, cijfers en streepjes uit een
/// e-mailadres of een naam vallen weg, zodat `m.de-vries` en `De Vries`
/// vergelijkbaar worden.
String _lettersOnly(String raw) =>
    raw.toLowerCase().replaceAll(RegExp(r'[^a-zà-öø-ÿ]'), '');

/// Placeholder-personen: de `example.com` van de namen. Ze staan in elke
/// handleiding en elk formuliervoorbeeld en horen dus bij niemand.
const Set<String> placeholderPersons = {
  'jan jansen',
  'jan de vries',
  'jan modaal',
  'pietje puck',
  'john doe',
  'jane doe',
  'john smith',
  'max mustermann',
  'erika mustermann',
  'erika musterfrau',
  'mario rossi',
  'maria rossi',
  'jean dupont',
  'marie dupont',
};

/// Is dit een bekende placeholder-naam? Vergelijkt genormaliseerd: kleine
/// letters, enkelvoudige spaties.
bool isPlaceholderPerson(String name) {
  final normalized = name.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  return placeholderPersons.contains(normalized);
}
