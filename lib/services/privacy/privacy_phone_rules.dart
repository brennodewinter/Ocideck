// Telefoonnummers.
//
// Een telefoonnummer is een reeks cijfers, en dat is precies het probleem: dat is
// een ordernummer ook, en een factuurnummer, en een ISBN, en een datum. Een regel
// die "acht of meer cijfers" zoekt, vuurt op elke financiële slide en is binnen
// een week uitgezet. De hele kunst zit hier dus niet in het vínden maar in het
// níét-vinden.
//
// Drie poorten, van streng naar soepel:
//
//   1. **E.164** (`+31 6 2468 1357`). Het plusteken plus een tóégekend landnummer
//      plus een geldige lengte is een structurele validatie, geen gok — dezelfde
//      klasse bewijs als een IBAN-checksum. Dit is de enige vorm die `certain`
//      wordt.
//
//   2. **Nationale vorm met scheidingsteken** (`06-24681357`, `020 123 4567`).
//      Een nul-trunkprefix met een scheidingsteken erin. Sterk, maar zonder
//      landnummer niet hard te maken: `likely`.
//
//   3. **Kale cijferreeks met een contextwoord** (`tel: 0624681357`). Zonder dat
//      woord vuurt deze niet, en dat is bewust: `0417164300` is net zo goed een
//      oud bankrekeningnummer.
//
// ── Wat er expliciet uit moet ────────────────────────────────────────────────
//
//   * **Datums.** `01-01-2024` is acht cijfers met streepjes en een nul voorop.
//     Vandaar de ondergrens van negen cijfers: een datum haalt die nooit.
//   * **ISBN's.** `0-306-40615-2` begint met een nul, heeft streepjes en tien
//     cijfers. Vandaar de eis dat de eerste cijfergroep minstens twee cijfers
//     telt: een landnummer is nooit één cijfer achter een nul-trunk.
//   * **De auteur zelf.** Zijn nummer op de contactslide is geen bevinding maar
//     de afzender; dat regelt `OwnIdentity` in de scanner, voor alle regels
//     tegelijk.

/// Woorden die van een kale cijferreeks een telefoonnummer maken.
///
/// Meertalig, en bewust ruim: dit is geen UI-tekst maar matchmateriaal, dus het
/// gaat niet door de l10n heen. Een taal toevoegen is hier woorden toevoegen.
const List<String> phoneContextWords = [
  'tel',
  'telefoon',
  'telefoonnummer',
  'mobiel',
  'mobiele',
  'gsm',
  'phone',
  'mobile',
  'cell',
  'telefon',
  'handy',
  'rufnummer',
  'téléphone',
  'portable',
  'teléfono',
  'móvil',
  'celular',
  'telefono',
  'cellulare',
  'bereikbaar',
  'bel ',
  'call',
  'whatsapp',
  'sms',
];

/// De internationale vorm: `+` gevolgd door 8 tot 15 cijfers, scheidingstekens
/// toegestaan.
///
/// De grenzen komen uit E.164 zelf: maximaal vijftien cijfers inclusief
/// landnummer. De ondergrens van acht is de onze — korter dan dat kan geen
/// landnummer plus abonneenummer zijn, en korte plus-getallen zijn eerder
/// wiskunde dan telefonie.
final RegExp e164Pattern = RegExp(r'(?<![\w+])\+\d[\d\s().\-]{6,18}\d(?![\w])');

/// De nationale vorm: nul-trunkprefix, dan minstens één cijfer, dan cijfers met
/// eventuele scheidingstekens.
///
/// `0\d` aan het begin is de ISBN-poort: `0-306-40615-2` heeft achter de nul een
/// streepje, geen cijfer, en valt hier dus buiten.
final RegExp nationalPhonePattern = RegExp(
  r'(?<![\w+])0\d[\d\s.\-]{6,14}\d(?![\w])',
);

/// Alleen de cijfers uit een treffer.
String phoneDigits(String raw) => raw.replaceAll(RegExp(r'\D'), '');

/// Bevat de treffer een scheidingsteken? Zonder is een cijferreeks te goedkoop
/// om zonder contextwoord op af te gaan.
bool hasPhoneSeparator(String raw) => RegExp(r'[\s.\-()]').hasMatch(raw);

/// De toegekende landnummers (ITU-T E.164).
///
/// Ze zijn prefixvrij ontworpen: geen enkel landnummer is het begin van een
/// ander. Daarom mag [callingCodeOf] gewoon één, twee en dan drie cijfers
/// proberen — er kan er nooit meer dan één passen.
///
/// Dit is wat een `+`-treffer `certain` mag maken. Zonder deze lijst zou elk
/// getal met een plusteken ervoor een telefoonnummer heten, en dat is geen
/// validatie maar een aanname.
const Set<String> callingCodes = {
  '1', '7',
  // Afrika
  '20', '27', '211', '212', '213', '216', '218', '220', '221', '222', '223',
  '224', '225', '226', '227', '228', '229', '230', '231', '232', '233', '234',
  '235', '236', '237', '238', '239', '240', '241', '242', '243', '244', '245',
  '246', '247', '248', '249', '250', '251', '252', '253', '254', '255', '256',
  '257', '258', '260', '261', '262', '263', '264', '265', '266', '267', '268',
  '269', '290', '291', '297', '298', '299',
  // Europa
  '30', '31', '32', '33', '34', '36', '39', '40', '41', '43', '44', '45', '46',
  '47', '48', '49', '350', '351', '352', '353', '354', '355', '356', '357',
  '358', '359', '370', '371', '372', '373', '374', '375', '376', '377', '378',
  '379', '380', '381', '382', '383', '385', '386', '387', '389', '420', '421',
  '423',
  // Latijns-Amerika en de Cariben
  '51', '52', '53', '54', '55', '56', '57', '58', '500', '501', '502', '503',
  '504', '505', '506', '507', '508', '509', '590', '591', '592', '593', '594',
  '595', '596', '597', '598', '599',
  // Azië en Oceanië
  '60', '61', '62', '63', '64', '65', '66', '81', '82', '84', '86', '90', '91',
  '92', '93', '94', '95', '98', '670', '672', '673', '674', '675', '676', '677',
  '678', '679', '680', '681', '682', '683', '685', '686', '687', '688', '689',
  '690', '691', '692', '850', '852', '853', '855', '856', '880', '886', '960',
  '961', '962', '963', '964', '965', '966', '967', '968', '970', '971', '972',
  '973', '974', '975', '976', '977', '992', '993', '994', '995', '996', '998',
};

/// Het landnummer waarmee deze cijferreeks begint, of `null` als het er geen is.
String? callingCodeOf(String digits) {
  for (var length = 1; length <= 3; length++) {
    if (digits.length <= length) break;
    final code = digits.substring(0, length);
    if (callingCodes.contains(code)) return code;
  }
  return null;
}

/// De gereserveerde "drama"-nummers: de `example.com` van de telefonie.
///
/// Toezichthouders houden reeksen vrij die nooit aan iemand worden uitgegeven,
/// juist zodat ze in films, handleidingen en documentatie gebruikt kunnen worden.
/// Ze staan dus per definitie in precies het soort tekst dat wij scannen — en dat
/// is geen theorie: onze eigen ontwerpdocumentatie noemt `+49 30 23125 xx` als
/// voorbeeld, en de vals-positieven-corpustest ving deze regel daar prompt op.
///
/// Gewerkt wordt op de kale cijfers, met of zonder landnummer, want `+44 7700
/// 900123` en `07700 900123` zijn hetzelfde nummer.
final List<RegExp> _reservedPhonePatterns = [
  // NANP (VS/Canada): 555-0100 t/m 555-0199.
  RegExp(r'^1?\d{3}55501\d{2}$'),
  // Duitsland: +49 30 23125 xx (Bundesnetzagentur). De staartcijfers zijn
  // optioneel: in documentatie staat het nummer vaak als `+49 30 23125 xx`, en
  // dan houdt de treffer op na het blok dat wél cijfers heeft.
  RegExp(r'^(?:49|0)3023125\d{0,4}$'),
  // Verenigd Koninkrijk (Ofcom): mobiel 07700 900xxx.
  RegExp(r'^(?:44|0)7700900\d{3}$'),
  // Verenigd Koninkrijk: Londen 020 7946 0xxx en het landelijke 01632 960xxx.
  RegExp(r'^(?:44|0)2079460\d{3}$'),
  RegExp(r'^(?:44|0)1632960\d{3}$'),
  // Verenigd Koninkrijk: de `xxx 496 0xxx`-blokken van de grote steden.
  RegExp(r'^(?:44|0)1\d{2}4960\d{3}$'),
];

/// Nooit-uitgegeven nummer, of een reeks zonder informatie (`0000000000`)?
bool isReservedPhoneNumber(String raw) {
  final digits = phoneDigits(raw);
  if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return true;
  return _reservedPhonePatterns.any((p) => p.hasMatch(digits));
}

/// Is dit een geldige E.164-treffer?
///
/// Een toegekend landnummer én een lengte die binnen E.164 past. Het abonneenummer
/// moet minstens vier cijfers overhouden — anders is `+31 123` een telefoonnummer,
/// en dat is het niet.
bool isValidE164(String raw) {
  final digits = phoneDigits(raw);
  if (digits.length < 8 || digits.length > 15) return false;
  if (isReservedPhoneNumber(raw)) return false;
  final code = callingCodeOf(digits);
  if (code == null) return false;
  return digits.length - code.length >= 4;
}

/// Is dit een geloofwaardige nationale vorm?
///
/// Negen cijfers is de ondergrens, en die grens doet één specifiek werk: een
/// datum (`01-01-2024`) heeft er acht en valt er dus buiten. Dertien is de
/// bovengrens; daarboven is het geen abonneenummer meer maar een referentie.
bool isPlausibleNationalPhone(String raw) {
  final digits = phoneDigits(raw);
  if (digits.length < 9 || digits.length > 13) return false;
  return !isReservedPhoneNumber(raw);
}
