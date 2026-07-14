// De registry van bekende nepwaarden.
//
// Dit bestand bestaat om één reden: een demodeck dat rood kleurt op zijn eigen
// voorbeelden ondermijnt het vertrouwen in álle andere meldingen. Wie één keer
// "BSN gevonden" ziet bij het voorbeeld-BSN uit de handleiding, gelooft de
// volgende melding niet meer — en zet de controle uit.
//
// Alles hier is publieke, gedocumenteerde testdata: reeksen die officieel voor
// documentatie en tests zijn gereserveerd. Ze horen dus per definitie bij
// niemand.

/// Domeinen die nooit een echt persoon aanwijzen (RFC 2606, RFC 6761).
const Set<String> reservedDomains = {
  'example.com',
  'example.org',
  'example.net',
  'example.edu',
  'localhost',
  'test',
  'invalid',
  'local',
};

/// Lokale delen van een adres dat naar een postbus wijst, niet naar een mens.
const Set<String> impersonalMailboxes = {
  'noreply',
  'no-reply',
  'donotreply',
  'do-not-reply',
  'postmaster',
  'webmaster',
  'abuse',
  'hostmaster',
  'mailer-daemon',
};

/// IBANs die in documentatie rondzwerven. `NL91ABNA0417164300` is hét
/// voorbeeld-IBAN van de Nederlandse bankensector; hij staat in elke handleiding.
const Set<String> exampleIbans = {
  'NL91ABNA0417164300',
  'DE89370400440532013000',
  'GB82WEST12345698765432',
  'FR1420041010050500013M02606',
  'BE68539007547034',
  'CH9300762011623852957',
  'NL02ABNA0123456789',
};

/// De officiële testkaartnummers van de kaartschema's. Ze doorstaan Luhn — dat
/// is juist hun bedoeling — en zouden dus zonder deze lijst als "zeker" scoren.
const Set<String> testCardNumbers = {
  '4111111111111111',
  '4012888888881881',
  '4222222222222',
  '4242424242424242',
  '5555555555554444',
  '5105105105105100',
  '378282246310005',
  '371449635398431',
  '6011111111111117',
  '3530111333300000',
  '30569309025904',
};

/// BSN's die als voorbeeld rondzwerven en de 11-proef doorstaan.
///
/// `123456782` is hét voorbeeld-BSN van het internet: het is zo gekozen dát het
/// de 11-proef haalt. Een oplopende-reeks-check vangt het níét — het eindigt op
/// een 2, niet op een 9 — dus het moet met naam en toenaam op deze lijst.
const Set<String> exampleBsns = {'123456782', '111222333', '010203040'};

/// Cijferreeksen zonder informatie: alle cijfers gelijk, of strikt oplopend of
/// aflopend. Vangt `111111111` en `123456789`, maar niet elk voorbeeld — daar is
/// [exampleBsns] voor.
bool isMeaninglessDigitRun(String digits) {
  if (digits.length < 4) return false;
  if (RegExp(r'^(\d)\1+$').hasMatch(digits)) return true;

  var ascending = true;
  var descending = true;
  for (var i = 1; i < digits.length; i++) {
    final prev = digits.codeUnitAt(i - 1);
    final cur = digits.codeUnitAt(i);
    if (cur != prev + 1) ascending = false;
    if (cur != prev - 1) descending = false;
  }
  return ascending || descending;
}

/// Een BSN dat bij niemand hoort: het officiële Nederlandse testbereik
/// (`999999xxx`), een bekend voorbeeldnummer, of een betekenisloze cijferreeks.
///
/// Deze nummers doorstaan allemaal de 11-proef — dat is juist waarom ze als
/// voorbeeld gekozen zijn — en zouden dus zonder deze lijst als "zeker" scoren.
bool isNonPersonalBsn(String digits) =>
    digits.startsWith('999999') ||
    exampleBsns.contains(digits) ||
    isMeaninglessDigitRun(digits);

/// Is dit e-mailadres onmiskenbaar geen persoon?
bool isPlaceholderEmail(String address) {
  final at = address.lastIndexOf('@');
  if (at <= 0) return true;
  final local = address.substring(0, at).toLowerCase();
  final domain = address.substring(at + 1).toLowerCase();

  if (impersonalMailboxes.contains(local)) return true;
  if (reservedDomains.contains(domain)) return true;

  // Ook subdomeinen en de gereserveerde TLD's: `mail.example.com`, `foo.invalid`.
  for (final reserved in reservedDomains) {
    if (domain.endsWith('.$reserved')) return true;
  }
  return false;
}

/// Is dit IBAN een bekend voorbeeld?
bool isExampleIban(String iban) =>
    exampleIbans.contains(iban.replaceAll(RegExp(r'[\s-]'), '').toUpperCase());

/// Is dit creditcardnummer een bekend testnummer?
bool isTestCardNumber(String digits) => testCardNumbers.contains(digits);
