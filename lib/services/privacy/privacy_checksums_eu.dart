// De checksums van de Europese persoonsnummers.
//
// Ruim twintig van de dertig Europese identificatienummers zijn zelfvaliderend:
// mod-97, mod-11, ISO 7064, Luhn. Dat is de reden dat "heel Europa aanzetten"
// verdedigbaar is — een checksum kost geen precisie, hij wínt precisie. De
// handvol zonder bruikbare checksum (Deens CPR sinds 2007, Brits NINO, Malta,
// Cyprus, Luxemburg) is contextpoort-gebonden, precies zoals het BSN dat is.
//
// Elke functie hier is puur en zelfstandig testbaar; `privacy_checksums_eu_test`
// voert per land een bekend-geldige én een bekend-ongeldige waarde in.

import 'privacy_checksums.dart';

/// Cijfers uit een string, zonder scheidingstekens.
String _digits(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

/// Gewogen som, met een gewicht per positie.
int _weighted(String digits, List<int> weights) {
  var sum = 0;
  for (var i = 0; i < weights.length && i < digits.length; i++) {
    sum += (digits.codeUnitAt(i) - 0x30) * weights[i];
  }
  return sum;
}

/// Is `dd`/`mm` een bestaande datum? De maandcodering verschilt per land — de
/// aanroeper normaliseert de maand eerst naar 1..12.
bool _plausibleDayMonth(int day, int month) =>
    month >= 1 && month <= 12 && day >= 1 && day <= 31;

// ── België ───────────────────────────────────────────────────────────────────

/// Rijksregisternummer: 11 cijfers, mod-97 over de eerste 9.
///
/// Voor geboorten vanaf 2000 wordt er een `2` vóór geplakt — beide varianten
/// moeten geprobeerd worden, want het nummer zelf zegt niet welke eeuw het is.
bool isValidBeRijksregister(String raw) {
  final d = _digits(raw);
  if (d.length != 11) return false;
  final body = int.tryParse(d.substring(0, 9));
  final check = int.tryParse(d.substring(9));
  if (body == null || check == null) return false;
  final pre2000 = 97 - (body % 97);
  final post2000 = 97 - (int.parse('2${d.substring(0, 9)}') % 97);
  return check == pre2000 || check == post2000;
}

// ── Duitsland ────────────────────────────────────────────────────────────────

/// Steuerliche Identifikationsnummer: 11 cijfers, ISO 7064 MOD 11,10.
///
/// Plus de cijferherhalingsregel: in de eerste tien cijfers komt precies één
/// cijfer twee of drie keer voor, en minstens één cijfer helemaal niet. Die regel
/// is geen franje — hij haalt een flinke hap uit de vals-positieven die de
/// checksum alleen zou doorlaten.
bool isValidDeSteuerId(String raw) {
  final d = _digits(raw);
  if (d.length != 11) return false;
  if (d[0] == '0') return false;

  final counts = <String, int>{};
  for (final c in d.substring(0, 10).split('')) {
    counts[c] = (counts[c] ?? 0) + 1;
  }
  final repeated = counts.values.where((n) => n > 1).toList();
  if (repeated.length != 1) return false;
  if (repeated.first > 3) return false;
  if (counts.length > 9) return false;

  // ISO 7064 MOD 11,10.
  var product = 10;
  for (var i = 0; i < 10; i++) {
    var sum = (d.codeUnitAt(i) - 0x30 + product) % 10;
    if (sum == 0) sum = 10;
    product = (2 * sum) % 11;
  }
  final check = (11 - product) % 10;
  return check == d.codeUnitAt(10) - 0x30;
}

// ── Frankrijk ────────────────────────────────────────────────────────────────

/// NIR (sécurité sociale): 13 cijfers + 2 controlecijfers = 97 − (n mod 97).
///
/// Corsica gebruikt `2A`/`2B` in het departementsveld; die tellen als 19 en 18.
/// Het nummer codeert geslacht, geboortejaar, geboortemaand en departement — het
/// is daarmee zelf al bijna een bijzonder gegeven.
bool isValidFrNir(String raw) {
  var body = raw.replaceAll(RegExp(r'[\s.-]'), '').toUpperCase();
  if (body.length != 15) return false;
  body = body.replaceFirst('2A', '19').replaceFirst('2B', '18');
  final n = int.tryParse(body.substring(0, 13));
  final check = int.tryParse(body.substring(13));
  if (n == null || check == null) return false;
  return check == 97 - (n % 97);
}

// ── Spanje ───────────────────────────────────────────────────────────────────

const String _dniLetters = 'TRWAGMYFPDXBNJZSQVHLCKE';

/// DNI (8 cijfers + letter) en NIE (X/Y/Z + 7 cijfers + letter): mod 23.
bool isValidEsDniNie(String raw) {
  final v = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (v.length != 9) return false;

  var body = v.substring(0, 8);
  final letter = v[8];
  final prefix = 'XYZ'.indexOf(body[0]);
  if (prefix >= 0) {
    body = '$prefix${body.substring(1)}';
  } else if (!RegExp(r'^\d{8}$').hasMatch(body)) {
    return false;
  }
  final n = int.tryParse(body);
  if (n == null) return false;
  return _dniLetters[n % 23] == letter;
}

// ── Portugal ─────────────────────────────────────────────────────────────────

/// NIF: 9 cijfers, gewogen 9..2, mod 11.
bool isValidPtNif(String raw) {
  final d = _digits(raw);
  if (d.length != 9) return false;
  final sum = _weighted(d, [9, 8, 7, 6, 5, 4, 3, 2]);
  final rest = sum % 11;
  final check = rest < 2 ? 0 : 11 - rest;
  return check == d.codeUnitAt(8) - 0x30;
}

// ── Polen ────────────────────────────────────────────────────────────────────

/// PESEL: 11 cijfers, gewichten 9-7-3-1-…, mod 10. Codeert geboortedatum en
/// geslacht.
bool isValidPlPesel(String raw) {
  final d = _digits(raw);
  if (d.length != 11) return false;
  // De maand draagt de eeuw (+20, +40, +60, +80). Zonder deze controle laat de
  // mod-10 te veel willekeurige reeksen door.
  final month = int.parse(d.substring(2, 4)) % 20;
  if (!_plausibleDayMonth(int.parse(d.substring(4, 6)), month)) return false;
  final sum = _weighted(d, [9, 7, 3, 1, 9, 7, 3, 1, 9, 7]);
  return sum % 10 == d.codeUnitAt(10) - 0x30;
}

// ── Italië ───────────────────────────────────────────────────────────────────

const String _cfEven = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const List<int> _cfOdd = [
  1, 0, 5, 7, 9, 13, 15, 17, 19, 21, //
  2, 4, 18, 20, 11, 3, 6, 8, 12, 14,
  16, 10, 22, 25, 24, 23,
];

/// Codice fiscale: 16 tekens; even en oneven posities tellen verschillend, mod 26
/// geeft de controleletter. Codeert geboortedatum, geslacht en geboorteplaats.
bool isValidItCodiceFiscale(String raw) {
  final v = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (!RegExp(r'^[A-Z0-9]{16}$').hasMatch(v)) return false;

  var sum = 0;
  for (var i = 0; i < 15; i++) {
    final c = v[i];
    // Cijfers tellen als hun waarde, letters als hun positie in het alfabet.
    final value = RegExp(r'\d').hasMatch(c) ? int.parse(c) : _cfEven.indexOf(c);
    if (value < 0) return false;
    // Posities zijn 1-gebaseerd: index 0 is dus een ONEVEN positie.
    sum += i.isEven ? _cfOdd[value] : value;
  }
  return _cfEven[sum % 26] == v[15];
}

// ── Kroatië ──────────────────────────────────────────────────────────────────

/// OIB: 11 cijfers, ISO 7064 MOD 11,10.
bool isValidHrOib(String raw) {
  final d = _digits(raw);
  if (d.length != 11) return false;
  var product = 10;
  for (var i = 0; i < 10; i++) {
    var sum = (d.codeUnitAt(i) - 0x30 + product) % 10;
    if (sum == 0) sum = 10;
    product = (2 * sum) % 11;
  }
  final check = (11 - product) % 10;
  return check == d.codeUnitAt(10) - 0x30;
}

// ── Bulgarije ────────────────────────────────────────────────────────────────

/// ЕГН: 10 cijfers, gewichten 2-4-8-5-10-9-7-3-6, mod 11 (11 → 0).
///
/// De checksum alléén is te zwak: mod-11 laat ongeveer één op de tien
/// willekeurige tiencijferige getallen door — dezelfde val als de 11-proef bij
/// het BSN. Daarom óók de ingebouwde geboortedatum valideren. Dat is geen extra:
/// zonder die controle ging de regel af op een 32-bits ARGB-kleurwaarde in een
/// JSON-voorbeeld in onze eigen documentatie, en dát is precies het soort ruis
/// waar een scanner aan onderdoor gaat.
bool isValidBgEgn(String raw) {
  final d = _digits(raw);
  if (d.length != 10) return false;
  if (!_validEgnDate(d)) return false;
  final sum = _weighted(d, [2, 4, 8, 5, 10, 9, 7, 3, 6]);
  final check = sum % 11 % 10;
  return check == d.codeUnitAt(9) - 0x30;
}

/// De maand draagt de eeuw: +20 voor de 19e eeuw, +40 voor de 21e.
bool _validEgnDate(String d) {
  var month = int.parse(d.substring(2, 4));
  if (month > 40) {
    month -= 40;
  } else if (month > 20) {
    month -= 20;
  }
  return _plausibleDayMonth(int.parse(d.substring(4, 6)), month);
}

// ── Roemenië ─────────────────────────────────────────────────────────────────

/// CNP: 13 cijfers, sleutel 279146358279, mod 11 (10 → 1).
bool isValidRoCnp(String raw) {
  final d = _digits(raw);
  if (d.length != 13) return false;
  if (!_plausibleDayMonth(
    int.parse(d.substring(5, 7)),
    int.parse(d.substring(3, 5)),
  )) {
    return false;
  }
  const key = [2, 7, 9, 1, 4, 6, 3, 5, 8, 2, 7, 9];
  final rest = _weighted(d, key) % 11;
  final check = rest == 10 ? 1 : rest;
  return check == d.codeUnitAt(12) - 0x30;
}

// ── Zweden ───────────────────────────────────────────────────────────────────

/// Personnummer: Luhn over de tien cijfers (YYMMDD-NNNC).
bool isValidSePersonnummer(String raw) {
  var d = _digits(raw);
  // Een 12-cijferige variant draagt de eeuw voorop; Luhn rekent op tien.
  if (d.length == 12) d = d.substring(2);
  if (d.length != 10) return false;
  return passesLuhn(d);
}

// ── Finland ──────────────────────────────────────────────────────────────────

const String _hetuChars = '0123456789ABCDEFHJKLMNPRSTUVWXY';

/// Henkilötunnus: DDMMYY + eeuwteken + 3 cijfers + controleteken (mod 31).
bool isValidFiHetu(String raw) {
  final v = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (v.length != 11) return false;
  final body = '${v.substring(0, 6)}${v.substring(7, 10)}';
  final n = int.tryParse(body);
  if (n == null) return false;
  return _hetuChars[n % 31] == v[10];
}

// ── Estland / Litouwen ───────────────────────────────────────────────────────

/// Isikukood (EE) en asmens kodas (LT): 11 cijfers, mod-11 met een tweede ronde
/// wanneer de eerste 10 oplevert.
bool isValidBalticPersonalCode(String raw) {
  final d = _digits(raw);
  if (d.length != 11) return false;
  if (!_plausibleDayMonth(
    int.parse(d.substring(5, 7)),
    int.parse(d.substring(3, 5)),
  )) {
    return false;
  }

  var rest = _weighted(d, [1, 2, 3, 4, 5, 6, 7, 8, 9, 1]) % 11;
  if (rest == 10) {
    rest = _weighted(d, [3, 4, 5, 6, 7, 8, 9, 1, 2, 3]) % 11;
    if (rest == 10) rest = 0;
  }
  return rest == d.codeUnitAt(10) - 0x30;
}

// ── Malta ────────────────────────────────────────────────────────────────────

/// De letters die achter een Maltees identiteitskaartnummer mogen staan.
///
/// Geen controleletter maar een categorie: `M` en `G` voor wie tussen 1900 en
/// 1999 in Malta respectievelijk Gozo is geregistreerd, `L` en `H` voor wie dat
/// vanaf 2000 is, `B` en `Z` voor de negentiende eeuw, `A` voor houders van een
/// verblijfsvergunning en `P` voor Maltezen die in het buitenland zijn geboren.
const String _mtIdCardSuffixes = 'ABGHLMPZ';

/// Identiteitskaartnummer: 7 cijfers + één van acht letters.
///
/// **Er is geen checksum, en die verzinnen we niet.** De letter codeert een
/// categorie en controleert niets; de zeven cijfers zijn een volgnummer. Wat
/// overblijft is een vorm die acht van de 26 letters toestaat — te weinig om
/// alleen op af te gaan, want `1234567M` is net zo goed een artikelcode. Vandaar
/// dat de regel in `privacy_eu_rules.dart` een contextwoord eist en nooit boven
/// `waarschijnlijk` komt, precies zoals `uk.nino` en `cw.sedula`.
bool isValidMtIdCard(String raw) {
  final v = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (!RegExp(r'^\d{7}[A-Z]$').hasMatch(v)) return false;
  return _mtIdCardSuffixes.contains(v[7]);
}

// ── Cyprus ───────────────────────────────────────────────────────────────────

/// De omzetting van de cijfers op de óneven posities in een Cypriotische TIC.
///
/// Geen gewichten maar een opzoektabel — een cijfer wordt vervangen door een
/// waarde die er niets mee te maken heeft (`2` → 5, `9` → 21). Dat is precies
/// wat de controle sterk maakt tegen omwisselingen, en waarom je hem niet uit
/// je hoofd kunt narekenen.
const List<int> _cyOddPositionMap = [1, 0, 5, 7, 9, 13, 15, 17, 19, 21];

/// De fiscale identificatiecode (TIC / ΑΦΜ): 8 cijfers + een controleletter.
///
/// **Waarom de TIC en niet het identiteitskaartnummer.** Het Cypriotische
/// ID-kaartnummer is een doorlopend volgnummer zonder enige controle — daar valt
/// geen verdedigbare regel op te bouwen. De TIC heeft er wél een: de letter is
/// een mod-26 over de acht cijfers, met een omzettabel voor de oneven posities.
///
/// **Twee dingen die deze controle níét weet.** Ten eerste of het om een mens
/// gaat: dezelfde code identificeert natuurlijke én rechtspersonen, en het
/// btw-nummer is deze code met `CY` ervoor. Vandaar `waarschijnlijk` in de
/// regeltabel en niet `zeker`. Ten tweede of het algoritme na 27 maart 2023 nog
/// hetzelfde is — vanaf die datum geeft het TFA-systeem codes uit vanaf
/// 60000000, en geen publieke bron zegt of de controleletter mee is veranderd.
/// De fout valt daar de goede kant op: mocht het schema zijn gewijzigd, dan
/// missen we die codes (vals-negatief) in plaats van willekeurige nummers te
/// melden.
bool isValidCyTic(String raw) {
  final v = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (!RegExp(r'^\d{8}[A-Z]$').hasMatch(v)) return false;
  // Het bereik `12xxxxxx` wordt niet uitgegeven.
  if (v.startsWith('12')) return false;

  var sum = 0;
  for (var i = 0; i < 8; i++) {
    final digit = v.codeUnitAt(i) - 0x30;
    sum += i.isEven ? _cyOddPositionMap[digit] : digit;
  }
  return v.codeUnitAt(8) == 0x41 + sum % 26;
}

// ── Luxemburg ────────────────────────────────────────────────────────────────

/// Matricule: 13 cijfers, `AAAAMMJJXXXC1C2`, met twee controlecijfers.
///
/// Het enige nummer in dit bestand met twéé onafhankelijke controles, en dat is
/// geen franje van de Luxemburgse wetgever: `C1` is een Luhn over de elf
/// identificerende cijfers, `C2` een Verhoeff over diezélfde elf. Niet over
/// twaalf — dat is de valkuil, want elke andere twee-controlecijferregeling die
/// je kent stapelt ze wél. Samen drukken ze de kans dat een willekeurige reeks
/// erdoorheen komt naar één op de honderd, en met de geboortedatum ervoor naar
/// ver daaronder.
///
/// Rechtspersonen krijgen een matricule met een ándere opbouw (jaar +
/// rechtsvorm + volgnummer + één mod-11-cijfer). Die valt hier af op de
/// datumcontrole, en dat is precies de bedoeling: een bedrijfsmatricule op een
/// factuurslide is geen persoonsgegeven.
bool isValidLuMatricule(String raw) {
  final d = _digits(raw);
  if (d.length != 13) return false;

  // Vier cijfers geboortejaar. De ondergrens is ruim genomen — het gaat er niet
  // om wie er nog leeft, maar om het uitsluiten van de negentig procent van de
  // willekeurige reeksen die met iets anders dan een jaartal beginnen.
  final year = int.parse(d.substring(0, 4));
  if (year < 1880 || year > 2099) return false;
  if (!_plausibleDayMonth(
    int.parse(d.substring(6, 8)),
    int.parse(d.substring(4, 6)),
  )) {
    return false;
  }

  final body = d.substring(0, 11);
  return _luhn('$body${d[11]}') && passesVerhoeff('$body${d[12]}');
}

// ── Letland ──────────────────────────────────────────────────────────────────

/// Personas kods: 11 cijfers, mod-11 met de gewichten 1-6-3-7-9-10-5-8-4-2.
///
/// **Niet** het Baltische schema van hierboven.
/// [isValidBalticPersonalCode] dekt Estland en Litouwen — die twee delen vorm
/// én dubbele mod-11 — maar Letland rekent anders: andere gewichten, één ronde,
/// en een afsluitende `mod 10` die een rest van 10 op 0 laat uitkomen. Een
/// Letse kods door de Estse validator halen keurt vier op de vijf echte nummers
/// af.
///
/// Twee formaten naast elkaar:
///
///  * **oud** — `ddmmjj` + eeuwcijfer (0 = 1800-1899, 1 = 1900-1999,
///    2 = 2000-2099) + drie volgnummercijfers + de controle;
///  * **nieuw** — sinds 1 juli 2017 begint een kods met `32` en draagt hij géén
///    geboortedatum meer. Dat is een privacymaatregel van de Letse wetgever, en
///    het kost ons precies de datumcontrole die het oude formaat wél levert.
///
/// Rechtspersonen beginnen met een cijfer boven de 3 en rekenen met een ander
/// schema. Die vallen hier af op het eerste cijfer, want een bedrijfsnummer is
/// geen persoonsgegeven.
bool isValidLvPersonasKods(String raw) {
  final d = _digits(raw);
  if (d.length != 11) return false;

  if (!d.startsWith('32')) {
    // Het oude formaat. Alles boven de 3 op positie 0 is een rechtspersoon, en
    // `30`/`31` blijven geldige dagen — vandaar de datumcontrole eronder in
    // plaats van een tweede cijfergrens.
    if (d.codeUnitAt(0) > 0x33) return false;
    if (!_plausibleDayMonth(
      int.parse(d.substring(0, 2)),
      int.parse(d.substring(2, 4)),
    )) {
      return false;
    }
    // Er zijn maar drie eeuwen uitgegeven. Zonder deze eis is dit de zwakste
    // schakel: hij haalt er in één regel zeventig procent uit.
    if (d.codeUnitAt(6) > 0x32) return false;
  }

  const weights = [1, 6, 3, 7, 9, 10, 5, 8, 4, 2];
  // 1101 ≡ 1 (mod 11); de vorm met 1101 staat zo in de Letse beschrijving en
  // houdt het tussenresultaat positief.
  final check = (1101 - _weighted(d, weights)) % 11 % 10;
  return check == d.codeUnitAt(10) - 0x30;
}

// ── Verenigd Koninkrijk ──────────────────────────────────────────────────────

/// NHS-nummer: 10 cijfers, gewichten 10..2, controle = 11 − rest (11 → 0,
/// 10 → ongeldig).
bool isValidUkNhs(String raw) {
  final d = _digits(raw);
  if (d.length != 10) return false;
  final sum = _weighted(d, [10, 9, 8, 7, 6, 5, 4, 3, 2]);
  final rest = 11 - (sum % 11);
  if (rest == 10) return false;
  final check = rest == 11 ? 0 : rest;
  return check == d.codeUnitAt(9) - 0x30;
}

/// National Insurance Number: geen checksum, wél een strak formaat met
/// uitgesloten prefixen.
///
/// Zonder checksum blijft dit een `waarschijnlijk`-regel: het formaat alleen is
/// geen bewijs.
bool isValidUkNino(String raw) {
  final v = raw.replaceAll(RegExp(r'\s'), '').toUpperCase();
  if (!RegExp(r'^[A-Z]{2}\d{6}[A-D]$').hasMatch(v)) return false;

  const forbiddenFirst = 'DFIQUV';
  const forbiddenSecond = 'DFIQUVO';
  const forbiddenPrefixes = {'BG', 'GB', 'KN', 'NK', 'NT', 'TN', 'ZZ'};
  if (forbiddenFirst.contains(v[0])) return false;
  if (forbiddenSecond.contains(v[1])) return false;
  if (forbiddenPrefixes.contains(v.substring(0, 2))) return false;
  return true;
}

// ── Oostenrijk ───────────────────────────────────────────────────────────────

/// Sozialversicherungsnummer: 10 cijfers, gewogen mod 11.
///
/// De eerste drie zijn een volgnummer, het vierde is het controlecijfer, en de
/// laatste zes zijn de geboortedatum (`ddmmjj`). Het controlecijfer staat dus
/// midden in het nummer en niet aan het eind — een detail dat je één keer fout
/// doet en daarna nooit meer.
bool isValidAtSvnr(String raw) {
  final d = _digits(raw);
  if (d.length != 10) return false;
  // De laatste zes cijfers zijn `ddmmjj`, en die datum móét kloppen. Zonder die
  // eis is dit alleen een mod-11 over tien cijfers, en komt één op de elf
  // willekeurige getallen erdoorheen — te zwak om `zeker` op te baseren. De
  // bestaande BSN-test ging er meteen op af met `7283982420`, waarvan de
  // datumhelft dag 98 in maand 24 zou zijn.
  if (!_plausibleDayMonth(
    int.parse(d.substring(4, 6)),
    int.parse(d.substring(6, 8)),
  )) {
    return false;
  }
  // Gewichten over de negen cijfers zónder het controlecijfer, in de volgorde
  // waarin ze in het nummer staan.
  const weights = [3, 7, 9, 0, 5, 8, 4, 2, 1, 6];
  var sum = 0;
  for (var i = 0; i < 10; i++) {
    if (i == 3) continue; // de controlepositie telt niet mee
    sum += (d.codeUnitAt(i) - 0x30) * weights[i];
  }
  final check = sum % 11;
  if (check == 10) return false; // zo'n nummer wordt niet uitgegeven
  return check == d.codeUnitAt(3) - 0x30;
}

// ── Zwitserland ──────────────────────────────────────────────────────────────

/// AHV-Nummer: `756.xxxx.xxxx.xx`, met een EAN-13-controlecijfer.
///
/// Begint altijd met 756 — de ISO-landcode van Zwitserland — en dat prefix doet
/// hier het meeste FP-werk: dertien willekeurige cijfers die óók met 756
/// beginnen én de EAN-controle halen, zijn zeldzaam.
bool isValidChAhv(String raw) {
  final d = _digits(raw);
  if (d.length != 13 || !d.startsWith('756')) return false;
  var sum = 0;
  for (var i = 0; i < 12; i++) {
    // EAN-13: afwisselend gewicht 1 en 3, van links af.
    sum += (d.codeUnitAt(i) - 0x30) * (i.isEven ? 1 : 3);
  }
  final check = (10 - (sum % 10)) % 10;
  return check == d.codeUnitAt(12) - 0x30;
}

// ── Tsjechië en Slowakije ────────────────────────────────────────────────────

/// Rodné číslo: geboortedatum plus volgnummer, sinds 1954 met een mod-11-controle.
///
/// Negen cijfers (vóór 1954) hebben géén controle en worden hier bewust
/// afgewezen: zonder checksum is het tien cijfers met een datum erin, en dat is
/// te weinig om `zeker` op te baseren.
///
/// De maand codeert het geslacht: +50 voor vrouwen, en sinds 2004 +20 wanneer
/// alle nummers voor die dag op zijn.
bool isValidCzSkRodneCislo(String raw) {
  final d = _digits(raw);
  if (d.length != 10) return false;

  var month = int.parse(d.substring(2, 4));
  if (month > 70) {
    month -= 70;
  } else if (month > 50) {
    month -= 50;
  } else if (month > 20) {
    month -= 20;
  }
  final day = int.parse(d.substring(4, 6));
  if (!_plausibleDayMonth(day, month)) return false;

  final head = int.parse(d.substring(0, 9));
  final check = d.codeUnitAt(9) - 0x30;
  final rest = head % 11;
  // De uitzondering uit de norm: rest 10 werd vroeger als 0 genoteerd.
  return check == (rest == 10 ? 0 : rest);
}

// ── Denemarken ───────────────────────────────────────────────────────────────

/// CPR-nummer: `ddmmjj-xxxx`.
///
/// **Bewust zonder checksum.** De mod-11-controle is in 2007 losgelaten omdat de
/// nummers opraakten, dus een geldig CPR hoeft hem niet te halen. Erop
/// controleren zou echte nummers afwijzen — precies de verkeerde fout. Wat
/// overblijft is de datum, en die is te zwak om alleen op af te gaan; vandaar
/// dat de regel een contextwoord eist en nooit hoger komt dan `waarschijnlijk`.
bool isValidDkCpr(String raw) {
  final d = _digits(raw);
  if (d.length != 10) return false;
  return _plausibleDayMonth(
    int.parse(d.substring(0, 2)),
    int.parse(d.substring(2, 4)),
  );
}

// ── Griekenland ──────────────────────────────────────────────────────────────

/// ΑΜΚΑ: 11 cijfers, Luhn, en de eerste zes zijn de geboortedatum.
bool isValidGrAmka(String raw) {
  final d = _digits(raw);
  if (d.length != 11) return false;
  if (!_plausibleDayMonth(
    int.parse(d.substring(0, 2)),
    int.parse(d.substring(2, 4)),
  )) {
    return false;
  }
  return _luhn(d);
}

/// De Luhn-controle over een cijferreeks.
bool _luhn(String digits) {
  var sum = 0;
  var double = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    var n = digits.codeUnitAt(i) - 0x30;
    if (double) {
      n *= 2;
      if (n > 9) n -= 9;
    }
    sum += n;
    double = !double;
  }
  return sum % 10 == 0;
}

// ── Hongarije ────────────────────────────────────────────────────────────────

/// TAJ-szám: 9 cijfers, gewogen mod 10 met afwisselend 3 en 7.
bool isValidHuTaj(String raw) {
  final d = _digits(raw);
  if (d.length != 9) return false;
  var sum = 0;
  for (var i = 0; i < 8; i++) {
    sum += (d.codeUnitAt(i) - 0x30) * (i.isEven ? 3 : 7);
  }
  return sum % 10 == d.codeUnitAt(8) - 0x30;
}

// ── Ierland ──────────────────────────────────────────────────────────────────

/// PPS Number: 7 cijfers, een controleletter, en soms een tweede letter.
///
/// De controleletter komt uit een mod-23-tabel. De optionele tweede letter (`W`
/// of een spatie) stamt uit het oude systeem voor echtgenotes en telt bij de
/// berekening als gewicht 0 — behalve `W`, dat expliciet wordt overgeslagen.
bool isValidIePps(String raw) {
  final s = raw.toUpperCase().replaceAll(RegExp(r'[^0-9A-Z]'), '');
  if (s.length < 8 || s.length > 9) return false;
  final digits = s.substring(0, 7);
  if (!RegExp(r'^\d{7}$').hasMatch(digits)) return false;
  final checkLetter = s[7];
  const alphabet = 'WABCDEFGHIJKLMNOPQRSTUV';
  if (!alphabet.contains(checkLetter)) return false;

  var sum = 0;
  for (var i = 0; i < 7; i++) {
    sum += (digits.codeUnitAt(i) - 0x30) * (8 - i);
  }
  // De tweede letter, als die er is, telt mee met gewicht 9.
  if (s.length == 9) {
    final second = s[8];
    if (second != 'W') sum += (second.codeUnitAt(0) - 0x40) * 9;
  }
  return alphabet[sum % 23] == checkLetter;
}

// ── Noorwegen ────────────────────────────────────────────────────────────────

/// Fødselsnummer: 11 cijfers met twee mod-11-controlecijfers.
bool isValidNoFodselsnummer(String raw) {
  final d = _digits(raw);
  if (d.length != 11) return false;
  if (!_plausibleDayMonth(
    int.parse(d.substring(0, 2)),
    int.parse(d.substring(2, 4)),
  )) {
    return false;
  }
  const w1 = [3, 7, 6, 1, 8, 9, 4, 5, 2];
  const w2 = [5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  final k1 = 11 - (_weighted(d, w1) % 11);
  if ((k1 == 11 ? 0 : k1) != d.codeUnitAt(9) - 0x30) return false;
  if (k1 == 10) return false;
  final k2 = 11 - (_weighted(d, w2) % 11);
  if (k2 == 10) return false;
  return (k2 == 11 ? 0 : k2) == d.codeUnitAt(10) - 0x30;
}

// ── IJsland ──────────────────────────────────────────────────────────────────

/// Kennitala: 10 cijfers, mod-11 met de gewichten 3-2-7-6-5-4-3-2.
///
/// Opbouw `ddmmjj` + twee volgnummercijfers + het controlecijfer + het
/// eeuwcijfer (`9` voor 1900-1999, `0` vanaf 2000). Het controlecijfer telt
/// zelf mee met gewicht 1 en het eeuwcijfer met 0, zodat de hele gewogen som
/// restloos door 11 deelbaar moet zijn — dezelfde formulering als de
/// referentie-implementatie, en één stap minder dan `11 − rest` uitrekenen.
///
/// **Rechtspersonen worden bewust afgewezen.** Een bedrijfskennitala heeft
/// exact dezelfde vorm met 40 opgeteld bij de dag (41-71), en die staat in elk
/// zakelijk deck met een IJslandse leverancier erin. Het is geen
/// persoonsgegeven, en de dagcontrole hieronder houdt hem tegen zonder dat er
/// een aparte regel voor nodig is.
///
/// De kerfiskennitala — het systeemnummer voor wie kort in IJsland verblijft —
/// heeft wél dezelfde vorm én dezelfde betekenis: hij wijst een mens aan. Die
/// valt dus terecht onder deze regel, en er is niets aan te onderscheiden.
bool isValidIsKennitala(String raw) {
  final d = _digits(raw);
  if (d.length != 10) return false;
  // Alleen deze twee eeuwcijfers worden uitgegeven. Het is de goedkoopste eis
  // in de hele controle en hij haalt er meteen tachtig procent uit.
  if (d[9] != '0' && d[9] != '9') return false;
  if (!_plausibleDayMonth(
    int.parse(d.substring(0, 2)),
    int.parse(d.substring(2, 4)),
  )) {
    return false;
  }
  return _weighted(d, [3, 2, 7, 6, 5, 4, 3, 2, 1, 0]) % 11 == 0;
}

// ── Slovenië ─────────────────────────────────────────────────────────────────

/// EMŠO: 13 cijfers, mod-11 over de eerste twaalf.
///
/// Dezelfde opzet als in de andere voormalig-Joegoslavische landen: `ddmmjjj`
/// gevolgd door een regiocode, een volgnummer en het controlecijfer.
bool isValidSiEmso(String raw) {
  final d = _digits(raw);
  if (d.length != 13) return false;
  if (!_plausibleDayMonth(
    int.parse(d.substring(0, 2)),
    int.parse(d.substring(2, 4)),
  )) {
    return false;
  }
  const weights = [7, 6, 5, 4, 3, 2, 7, 6, 5, 4, 3, 2];
  final m = 11 - (_weighted(d, weights) % 11);
  final check = m == 11 ? 0 : m;
  if (m == 10) return false;
  return check == d.codeUnitAt(12) - 0x30;
}

/// Het oude Nederlandse btw-identificatienummer van een eenmanszaak.
///
/// Vorm `NL` + negen cijfers + `B` + twee cijfers. Tot 2020 wáren die negen
/// cijfers het BSN van de ondernemer — daarom staat dit nummer hier en niet bij
/// de fiscale nummers: wie het publiceert, publiceert een BSN.
///
/// Sinds 1 januari 2020 krijgen eenmanszaken een omzetbelastingnummer dat níét
/// van het BSN is afgeleid. Die nieuwe nummers halen de 11-proef zelden, en dat
/// is precies de bedoeling van deze controle: hij scheidt het oude, gevaarlijke
/// nummer van het nieuwe, onschuldige. Zonder de 11-proef zou elk btw-nummer op
/// een factuurslide een melding opleveren.
bool isValidNlBtwIdLegacy(String raw) {
  final normalized = raw.toUpperCase().replaceAll(RegExp(r'[ .]'), '');
  final m = RegExp(r'^NL(\d{9})B\d{2}$').firstMatch(normalized);
  if (m == null) return false;
  return passesElevenProof(m.group(1)!);
}
