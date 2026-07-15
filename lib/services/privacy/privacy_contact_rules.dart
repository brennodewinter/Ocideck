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
