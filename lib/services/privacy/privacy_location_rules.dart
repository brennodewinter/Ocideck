// Geboortedatum en coördinaten.
//
// Twee regels die weinig met elkaar te maken lijken te hebben, en die toch om
// dezelfde reden bij elkaar staan: ze wijzen allebei een persoon aan zónder hem
// te noemen. Een geboortedatum plus een postcode plus een geslacht is volgens
// Sweeney's klassieke werk voor het overgrote deel van een bevolking uniek — je
// hebt geen naam nodig om iemand te vinden. En een coördinatenpaar met vijf
// decimalen is een huisdeur.
//
// ── Waarom de geboortedatum een contextwoord eist ───────────────────────────
//
// Een datum is de meest voorkomende getalsvorm in een zakelijk deck. Releases,
// deadlines, kwartaalcijfers, vergaderingen, historische gebeurtenissen — een
// scanner die elke datum als geboortedatum meldt, meldt vooral de agenda. Dus:
// alleen mét een contextwoord (`geboren`, `geboortedatum`, `dob`) of onder een
// tabelkolom die het zegt.
//
// ── Waarom coördinaten géén contextwoord eisen ───────────────────────────────
//
// Omgekeerd juist: een decimaal coördinatenpaar heeft een vorm die in gewone
// tekst niet voorkomt. Twee kommagetallen met minstens vier decimalen, gescheiden
// door een komma, binnen het geldige bereik — dat is geen bedrag, geen versie en
// geen meetwaarde. Wat er wél uit moet: grafiekdata. Een chart-dataset is precies
// een reeks getallenparen, en die staat in OciDeck in een eigen veld.

/// Contextwoorden die van een datum een geboortedatum maken.
///
/// Meertalig, want de scanner draait in 31 talen. Data, geen UI — deze woorden
/// worden nooit getoond, alleen gematcht.
const List<String> birthdateContextWords = [
  'geboortedatum',
  'geboortedag',
  'geboren',
  'geb.',
  'geb ',
  'date of birth',
  'birth date',
  'birthdate',
  'born',
  'dob',
  'geburtsdatum',
  'geboren am',
  'date de naissance',
  'né le',
  'née le',
  'fecha de nacimiento',
  'nacido',
  'nacida',
  'data di nascita',
  'nato il',
  'nata il',
  'data de nascimento',
  'data urodzenia',
];

/// Een datum in de vormen die in Europa gangbaar zijn.
///
/// `31-12-1980`, `31/12/1980`, `1980-12-31`, `31.12.1980`. Het jaartal moet vier
/// cijfers hebben: een tweecijferig jaar is niet van een dag te onderscheiden en
/// levert alleen maar ruis op.
final RegExp birthdatePattern = RegExp(
  r'(?<![\d/.\-])(?:'
  r'\d{1,2}[-/.]\d{1,2}[-/.]\d{4}' // 31-12-1980
  r'|\d{4}-\d{1,2}-\d{1,2}' // 1980-12-31 (ISO)
  r')(?![\d/.\-])',
);

/// Een datum geschreven met de maandnaam erin: `12 maart 1980`, `3 May 1975`.
///
/// Alleen de maandnamen van de talen waarin de contextwoorden hierboven ook
/// staan — een maandnamenlijst voor 31 talen is werk voor het lexicon (fase 12),
/// niet voor deze regel.
final RegExp birthdateWordPattern = RegExp(
  r'(?<!\w)\d{1,2}\s+(?:'
  r'januari|februari|maart|april|mei|juni|juli|augustus|september|oktober|november|december'
  r'|january|february|march|may|june|july|august|october|december'
  r'|januar|februar|märz|mai|juni|juli|august|oktober|dezember'
  r'|janvier|février|mars|avril|mai|juin|juillet|août|septembre|octobre|novembre|décembre'
  r'|enero|febrero|marzo|abril|mayo|junio|julio|agosto|septiembre|octubre|noviembre|diciembre'
  r')\s+\d{4}(?!\d)',
  caseSensitive: false,
);

/// Is dit een geldige kalenderdatum, en een plausibele geboortedatum?
///
/// De bovengrens is niet cosmetisch: een "geboortedatum" in 2090 is een
/// invoerfout of een verzonnen voorbeeld, en de ondergrens van 1900 houdt
/// jaartallen uit historische opsommingen buiten de deur.
bool isPlausibleBirthdate(int year, int month, int day) {
  if (year < 1900 || year > 2035) return false;
  if (month < 1 || month > 12) return false;
  if (day < 1 || day > 31) return false;
  const lengths = [31, 29, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day <= lengths[month - 1];
}

/// Ontleedt een numerieke datum naar (jaar, maand, dag), of `null`.
///
/// Accepteert zowel de ISO-volgorde als de Europese. De Amerikaanse
/// maand-eerst-volgorde is bewust *niet* apart behandeld: `03/04/1980` is
/// dubbelzinnig en welke lezing je ook kiest, de uitkomst is een geldige datum —
/// de melding verandert er dus niet door.
({int year, int month, int day})? parseNumericDate(String raw) {
  final parts = raw.split(RegExp(r'[-/.]'));
  if (parts.length != 3) return null;
  final numbers = [for (final p in parts) int.tryParse(p)];
  if (numbers.any((n) => n == null)) return null;
  final values = numbers.cast<int>();
  // Vier cijfers vooraan betekent ISO-volgorde.
  if (parts.first.length == 4) {
    return (year: values[0], month: values[1], day: values[2]);
  }
  return (year: values[2], month: values[1], day: values[0]);
}

// ── Coördinaten ──────────────────────────────────────────────────────────────

/// Een decimaal lat/lon-paar: `52.37403, 4.88969`.
///
/// Minstens vier decimalen aan beide kanten. Dat is de poort die dit van gewone
/// getallenparen scheidt: vier decimalen is ongeveer elf meter, en niemand
/// schrijft een omzetcijfer of een meetwaarde zo op. Met minder decimalen wijst
/// het paar bovendien een dorp aan en geen deur, en dan is het geen
/// persoonsgegeven meer.
final RegExp coordinatePairPattern = RegExp(
  r'(?<![\d.\-])(-?\d{1,2}\.\d{4,})\s*,\s*(-?\d{1,3}\.\d{4,})(?![\d.])',
);

/// Een `geo:`-URI zoals RFC 5870 hem definieert.
final RegExp geoUriPattern = RegExp(
  r'geo:-?\d{1,2}\.\d+,-?\d{1,3}\.\d+',
  caseSensitive: false,
);

/// Een Open Location Code (plus-code): `9F26RC2X+2F`, of met plaatsnaam
/// `RC2X+2F Amsterdam`.
final RegExp plusCodePattern = RegExp(
  r'(?<![\w+])[23456789CFGHJMPQRVWX]{4,8}\+[23456789CFGHJMPQRVWX]{2,3}(?![\w+])',
);

/// Een what3words-adres: `///stelsel.trotse.klapt`.
final RegExp whatThreeWordsPattern = RegExp(
  r'///[a-z]{3,}\.[a-z]{3,}\.[a-z]{3,}',
  caseSensitive: false,
);

/// Ligt het paar binnen het geldige bereik van de aardbol?
///
/// Zonder deze eis is elk paar kommagetallen een coördinaat, en juist bij
/// meetreeksen (`12.3456, 98.7654`) is dat een reële vergissing.
bool isPlausibleCoordinate(double latitude, double longitude) =>
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180 &&
    // Precies nul-nul is "geen locatie bekend" in vrijwel elk systeem, en het
    // ligt in de Golf van Guinee.
    !(latitude == 0 && longitude == 0);

/// Velden waarin een getallenpaar grafiekdata is en geen locatie.
///
/// OciDeck bewaart grafiekgegevens in een eigen veld; die hoeven we dus niet uit
/// de tekst te raden. §3-D vraagt expliciet om deze uitsluiting.
const Set<String> chartDataFields = {'chartData', 'chartLabels', 'chartSeries'};
