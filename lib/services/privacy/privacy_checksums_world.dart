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

import 'privacy_checksums.dart';

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

// ── De zorgnummers ───────────────────────────────────────────────────────────
//
// Deze drie zijn in de VS routineuze administratie: een NPI staat in openbare
// registers, een MBI op de kaart in iemands portemonnee, een DEA-nummer op elk
// recept. Onder de AVG liggen ze anders. Ze verschijnen in de context van zorg,
// en een identificator plus die context maakt er een gegeven over gezondheid
// van — artikel 9, met de zwaarste weging die OciWacht kent.
//
// Dat is precies de blinde vlek die §15.2 beschrijft: wie de Amerikaanse
// opsomming overneemt, ziet hier claimadministratie; wie de AVG als maatstaf
// neemt, ziet bijzondere persoonsgegevens.

/// National Provider Identifier: tien cijfers, Luhn over `80840` + de eerste
/// negen.
///
/// De prefix is geen opsmuk maar het ISO-uitgeversnummer voor de Amerikaanse
/// zorg; hij hoort bij de berekening, niet bij het nummer zoals het geschreven
/// wordt.
///
/// Let op wat deze controle wél en niet waard is. Luhn over tien cijfers laat
/// ongeveer één op de tien willekeurige getallen door — dezelfde orde als de
/// 11-proef bij `nl.bsn`, en §15.4 corrigeert het ontwerp juist op dit punt:
/// wat een checksum sterk maakt is de lengte, niet de checksum. Vandaar dat
/// `us.npi` een contextpoort houdt en niet op `certain` uitkomt, ook al staat
/// hij in de ontwerptabel van §15.3 nog als "zeker".
bool isValidUsNpi(String raw) {
  final d = _digits(raw);
  if (d.length != 10) return false;
  // Alleen 1 en 2 zijn in gebruik: 1 voor personen, 2 voor organisaties. Een
  // NPI die met iets anders begint, bestaat niet.
  if (d[0] != '1' && d[0] != '2') return false;
  return passesLuhn('80840$d');
}

/// De tekenklasse die CMS in een MBI toestaat: `A-Z` zonder `S`, `L`, `O`, `I`,
/// `B` en `Z`.
///
/// Die zes zijn eruit omdat ze op een cijfer lijken zodra iemand het nummer
/// overtypt van een kaart: S/5, L/1, O/0, I/1, B/8, Z/2. Een ontwerpkeuze tegen
/// leesfouten, die ons hier gratis een strakkere controle oplevert.
const String _mbiLetters = 'ACDEFGHJKMNPQRTUVWXY';

/// Medicare Beneficiary Identifier: elf posities, elk met een eigen tekenklasse.
///
/// Geen checksum — de sterkte zit volledig in de vorm. Dat is meer dan het lijkt
/// (elf posities, en zes letters uitgesloten), maar niet genoeg: een
/// artikelnummer dat toevallig dezelfde afwisseling volgt, komt er doorheen.
/// Vandaar ook hier een contextpoort.
bool isValidUsMbi(String raw) {
  final s = raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
  if (s.length != 11) return false;

  bool digit(String c) => c.compareTo('1') >= 0 && c.compareTo('9') <= 0;
  bool digit0(String c) => c.compareTo('0') >= 0 && c.compareTo('9') <= 0;
  bool letter(String c) => _mbiLetters.contains(c);

  // Positie 1 is 1-9 (nooit 0); 4, 7, 10 en 11 mogen wel 0 zijn.
  return digit(s[0]) &&
      letter(s[1]) &&
      (digit0(s[2]) || letter(s[2])) &&
      digit0(s[3]) &&
      letter(s[4]) &&
      (digit0(s[5]) || letter(s[5])) &&
      digit0(s[6]) &&
      letter(s[7]) &&
      letter(s[8]) &&
      digit0(s[9]) &&
      digit0(s[10]);
}

/// DEA-registratienummer: twee letters, zeven cijfers, eigen controlecijfer.
///
/// De som van het 1e, 3e en 5e cijfer plus tweemaal de som van het 2e, 4e en 6e
/// eindigt op het 7e cijfer. Een mod-10 over zes cijfers, dus opnieuw één op de
/// tien — zie de opmerking bij [isValidUsNpi].
///
/// De tweede letter is de eerste letter van de achternaam van de geregistreerde.
/// Dat maakt dit nummer op zichzelf al een stukje persoonsgegeven: het draagt
/// een fragment van de naam mee.
bool isValidUsDea(String raw) {
  final s = raw.replaceAll(RegExp(r'[^0-9A-Za-z]'), '').toUpperCase();
  if (s.length != 9) return false;
  // De eerste letter is het registrantentype. X staat voor een
  // buprenorfine-ontheffing, en juist die zegt iets over de behandeling.
  if (!'ABCDEFGHJKLMPRSTUX'.contains(s[0])) return false;
  if (!RegExp(r'^[A-Z]$').hasMatch(s[1])) return false;
  final d = s.substring(2);
  if (!RegExp(r'^\d{7}$').hasMatch(d)) return false;

  int at(int i) => d.codeUnitAt(i) - 0x30;
  final odd = at(0) + at(2) + at(4);
  final even = at(1) + at(3) + at(5);
  return (odd + 2 * even) % 10 == at(6);
}

// ── Canada ───────────────────────────────────────────────────────────────────

/// De testwaarde die in vrijwel elke SIN-validator als voorbeeld staat.
const Set<String> knownFakeSins = {'046454286', '000000000'};

/// Social Insurance Number: negen cijfers met een Luhn.
///
/// **Let op de zekerheid.** OCIWACHT §3-A gaf dit nummer eerst als `zeker` op
/// grond van de Luhn alleen, en dat kan niet: een Luhn over negen cijfers laat
/// één op de tien willekeurige getallen door. Dat is dezelfde orde als de
/// 11-proef bij het BSN, en `privacy_checksums.dart` legt daar al uit waarom die
/// in zijn eentje niet volstaat. Wat een checksum sterk maakt is de lengte, niet
/// de checksum. Vandaar de contextpoort op de regel en `likely` als plafond.
///
/// Het eerste cijfer draagt wél echt onderscheid: 0 en 8 zijn nooit uitgegeven.
bool isValidCaSin(String raw) {
  final d = _digits(raw);
  if (d.length != 9) return false;
  if (knownFakeSins.contains(d)) return false;
  if (d[0] == '0' || d[0] == '8') return false;

  return passesLuhn(d);
}

/// Business Number: negen cijfers met een Luhn, soms gevolgd door een
/// programmacode (`RC0001`, `RT0001`).
///
/// Bedrijfsdata, en dus in de regel geen persoonsgegeven. Bij een eenmanszaak
/// ligt dat anders — dezelfde constructie als bij `us.ein` en bij het oude
/// Nederlandse btw-nummer, waar de negen cijfers letterlijk het BSN zijn.
bool isValidCaBn(String raw) {
  final d = _digits(raw);
  if (d.length < 9) return false;
  // Alleen de eerste negen cijfers dragen de checksum; een programmacode als
  // `RC0001` hangt erachter en telt niet mee.
  final negen = d.substring(0, 9);
  if (negen[0] == '0') return false;

  return passesLuhn(negen);
}

/// RAMQ (Québec): vier letters plus acht cijfers.
///
/// De letters zijn de eerste drie van de achternaam plus de eerste van de
/// voornaam; daarna `jjmmdd` en twee volgcijfers. De maand telt +50 voor vrouwen,
/// net als bij het Sloveense en Kroatische stelsel.
///
/// Dat maakt dit nummer bijzonder: het codeert geboortedatum én geslacht, en is
/// daarmee — net als de Franse NIR — bijna zelf al een bijzonder gegeven. Er is
/// geen openbaar gedocumenteerd controlecijfer, dus de datum draagt het bewijs
/// en de regel eist context.
bool isValidCaRamq(String raw) {
  final s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
  if (s.length != 12) return false;
  if (!RegExp(r'^[A-Z]{4}\d{8}$').hasMatch(s)) return false;

  var maand = int.parse(s.substring(6, 8));
  if (maand > 50) maand -= 50;
  final dag = int.parse(s.substring(8, 10));
  return maand >= 1 && maand <= 12 && dag >= 1 && dag <= 31;
}

/// OHIP (Ontario): tien cijfers, optioneel gevolgd door twee versieletters.
///
/// **Eerlijk over de zekerheid.** §15.3 gaf hier een mod-10 op. Die is publiek
/// niet hard te krijgen — de gangbare bewering is dat het tiende cijfer een
/// Luhn-controle is, maar dat heb ik niet tegen een gezaghebbende bron kunnen
/// leggen. De test hieronder toetst daarom dat de *implementatie* discrimineert
/// (precies één controlecijfer past), niet dat Luhn het juiste algoritme ís.
///
/// Zolang dat open staat blijft de regel op `likely` met een contextpoort. Een
/// verkeerd gekozen algoritme kan dan hooguit treffers missen, en nooit een
/// valse `certain` opleveren — de fout die je wél wilt maken.
bool isValidCaOhip(String raw) {
  final d = _digits(raw);
  if (d.length != 10) return false;
  if (d[0] == '0') return false;

  return passesLuhn(d);
}
