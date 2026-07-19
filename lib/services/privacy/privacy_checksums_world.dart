// Validaties voor de nummers buiten Europa (OCIWACHT §15).
//
// De splitsing volgt `privacy_checksums_eu.dart`: gedeelde primitieven staan in
// `privacy_checksums.dart`, en wat door precies één regel wordt aangeroepen
// staat hier.
//
// ── Wat hier anders is dan in Europa ────────────────────────────────────────
//
// De Europese tabel drijft op checksums: ruim twintig van de dertig nummers
// valideren zichzelf. De Amerikaanse kern doet dat níét. Het SSN heeft geen
// controlecijfer, het ITIN evenmin, en het EIN alleen een prefixlijst. Wat hier
// "validatie" heet is dus geen checksum maar een **bereikcontrole**: welke
// combinaties heeft de uitgevende instantie nooit uitgegeven.
//
// Dat is zwakker, en het bepaalt de hele opzet. Een bereikcontrole schrapt
// misschien één op de twintig willekeurige getallen; een mod-11 schrapt er tien
// van de elf. Daarom dragen deze regels zonder uitzondering een contextpoort en
// komen ze nooit boven `likely` uit — dezelfde afweging als bij `nl.bsn`, waar
// `privacy_checksums.dart` al uitlegt waarom een zwakke controle alléén niet
// genoeg is om `certain` op te baseren.

/// Alleen de cijfers uit [raw].
String _digits(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

// ── Verenigde Staten ─────────────────────────────────────────────────────────

/// Nummers die overal in voorbeelden opduiken en dus niemand aanwijzen.
///
/// `078-05-1120` is het beroemdste: het stond op de proefkaart in portefeuilles
/// van Woolworth in 1938, waarna duizenden mensen het als het hunne opgaven. Een
/// scanner die dát nummer rood maakt op een slide over identiteitsfraude, maakt
/// zichzelf belachelijk.
const Set<String> knownFakeSsns = {
  '078051120',
  '219099999',
  '123456789',
  '111111111',
  '222222222',
  '333333333',
};

/// Social Security Number: **geen checksum**, alleen bereikregels.
///
/// De uitgifte is in 2011 gerandomiseerd, waardoor de oude geografische betekenis
/// van de eerste drie cijfers verdween. Wat bleef zijn de combinaties die nooit
/// zijn uitgegeven: gebied 000, 666 en 900-999, groep 00, en volgnummer 0000.
///
/// Dat schrapt hooguit een paar procent van de willekeurige negencijferige
/// getallen. Veel te weinig om alleen op af te gaan — vandaar dat `us.ssn` een
/// contextwoord eist en op `likely` blijft steken.
bool isValidUsSsn(String raw) {
  final d = _digits(raw);
  if (d.length != 9) return false;
  if (knownFakeSsns.contains(d)) return false;

  final area = int.parse(d.substring(0, 3));
  if (area == 0 || area == 666 || area >= 900) return false;
  if (int.parse(d.substring(3, 5)) == 0) return false;
  if (int.parse(d.substring(5)) == 0) return false;

  // De SSA heeft 987-65-4320 t/m 987-65-4329 gereserveerd voor reclame, juist
  // om te voorkomen dat een advertentie iemands echte nummer toont. Die vallen
  // al af op `area >= 900`, maar de reden hoort opgeschreven: als dat bereik
  // ooit verschuift, is dit de regel die mee moet.
  return true;
}

/// Individual Taxpayer Identification Number.
///
/// Formaat als een SSN, maar het gebied begint altijd met 9 en de groep ligt in
/// een van de toegewezen reeksen. Wordt uitgegeven aan wie belastingplichtig is
/// zonder recht op een SSN — het wijst dus een niet-ingezetene aan, en dat
/// grenst aan verblijfsstatus. Reden om hem juist wél te detecteren, niet om hem
/// milder te behandelen.
bool isValidUsItin(String raw) {
  final d = _digits(raw);
  if (d.length != 9) return false;
  if (d[0] != '9') return false;

  final group = int.parse(d.substring(3, 5));
  const ranges = [
    [50, 65],
    [70, 88],
    [90, 92],
    [94, 99],
  ];
  if (!ranges.any((r) => group >= r[0] && group <= r[1])) return false;
  return int.parse(d.substring(5)) != 0;
}

/// De prefixen die de IRS werkelijk uitgeeft (de eerste twee cijfers).
///
/// Elk prefix hoort bij een uitgiftecampus. De lijst is niet compleet-voor-altijd
/// — de IRS voegt er af en toe een toe — maar hij is wél restrictief genoeg om
/// ordernummers eruit te houden, en dat is waar hij voor dient.
const Set<String> _einPrefixes = {
  '01', '02', '03', '04', '05', '06', '10', '11', '12', '13', '14', '15', //
  '16', '20', '21', '22', '23', '24', '25', '26', '27', '30', '31', '32', //
  '33', '34', '35', '36', '37', '38', '39', '40', '41', '42', '43', '44', //
  '45', '46', '47', '48', '50', '51', '52', '53', '54', '55', '56', '57', //
  '58', '59', '60', '61', '62', '63', '64', '65', '66', '67', '68', '71', //
  '72', '73', '74', '75', '76', '77', '80', '81', '82', '83', '84', '85', //
  '86', '87', '88', '90', '91', '92', '93', '94', '95', '98', '99', //
};

/// Employer Identification Number: negen cijfers met een geldig prefix.
///
/// Dit is in de regel *bedrijfs*data en dus geen persoonsgegeven. Bij een
/// eenmanszaak ligt dat anders: dan identificeert het EIN de ondernemer zelf.
/// Precies de constructie die OCIWACHT §3-A al beschrijft bij het oude
/// Nederlandse btw-nummer, waar de negen cijfers letterlijk het BSN zijn.
/// Vandaar `info` als vertrekpunt: melden, niet alarmeren.
bool isValidUsEin(String raw) {
  final d = _digits(raw);
  if (d.length != 9) return false;
  return _einPrefixes.contains(d.substring(0, 2));
}

/// ABA routing number: negen cijfers, gewogen mod 10 met 3-7-1.
///
/// Dit is wél een echte checksum, en daarmee de enige regel uit deze lichting
/// die op eigen kracht `certain` haalt. Hij hangt niet aan een landpakket maar
/// aan de financiële familie — een Amerikaans rekeningnummer in een Nederlands
/// deck hoort niet stil te blijven omdat iemand het VS-pakket uit had staan.
bool isValidAbaRouting(String raw) {
  final d = _digits(raw);
  if (d.length != 9) return false;
  if (int.parse(d) == 0) return false;

  // Het eerste octet is het Federal Reserve-district. 80-99 zijn buitenlandse
  // en speciale bereiken; 00 bestaat niet.
  final lead = int.parse(d.substring(0, 2));
  if (lead == 0 || (lead > 32 && lead < 61) || lead > 80) return false;

  const weights = [3, 7, 1, 3, 7, 1, 3, 7, 1];
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    sum += (d.codeUnitAt(i) - 0x30) * weights[i];
  }
  return sum % 10 == 0;
}
