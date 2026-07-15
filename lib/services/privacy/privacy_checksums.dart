// Checksums voor de privacydetectie.
//
// Dit is het fundament onder de hele vals-positieven-strategie. Een regex die
// "negen cijfers" herkent, meldt elk ordernummer als BSN; de gebruiker zet de
// controle dan binnen een week uit, en daarna detecteert hij niets meer. Een
// checksum drukt die ruis naar bijna nul.
//
// Wat een checksum NIET oplost, staat er expliciet bij — zie de 11-proef.

/// De 11-proef over een BSN (9 cijfers).
///
/// Gewichten 9-8-7-6-5-4-3-2 voor de eerste acht cijfers, en **min 1** voor het
/// laatste; de som moet deelbaar zijn door 11.
///
/// **Belangrijk voor de aanroeper:** ongeveer één op de elf willekeurige
/// 9-cijferige getallen doorstaat deze proef. Een geldige 11-proef is dus *geen*
/// bewijs dat je naar een BSN kijkt — het is alleen bewijs dat het er een kán
/// zijn. Zonder een contextwoord of een veldpositie ("BSN: …", een tabelkolom
/// met die kop) hoort een treffer daarom hooguit informatief te zijn, nooit een
/// waarschuwing. Zie `docs/design/OCIWACHT.md` §5.2.
bool passesElevenProof(String digits) {
  if (digits.length != 9) return false;
  var sum = 0;
  for (var i = 0; i < 9; i++) {
    final code = digits.codeUnitAt(i);
    if (code < 0x30 || code > 0x39) return false;
    final digit = code - 0x30;
    // Het laatste cijfer telt negatief mee — dat is wat de 11-proef
    // onderscheidt van een gewone gewogen modulo-controle.
    sum += digit * (i == 8 ? -1 : 9 - i);
  }
  return sum % 11 == 0;
}

/// De Luhn-controle (creditcards, IMEI, ICCID, en enkele nationale nummers).
bool passesLuhn(String digits) {
  if (digits.length < 2) return false;
  var sum = 0;
  var double = false;
  for (var i = digits.length - 1; i >= 0; i--) {
    final code = digits.codeUnitAt(i);
    if (code < 0x30 || code > 0x39) return false;
    var digit = code - 0x30;
    if (double) {
      digit *= 2;
      if (digit > 9) digit -= 9;
    }
    sum += digit;
    double = !double;
  }
  return sum % 10 == 0;
}

/// De lengte van een geldig IBAN per land (ISO 13616).
///
/// De lengte is een even sterke filter als de checksum zelf: een string die
/// mod-97 haalt maar de verkeerde lengte heeft voor zijn landcode, is geen IBAN.
const Map<String, int> ibanLengths = {
  'AD': 24,
  'AE': 23,
  'AL': 28,
  'AT': 20,
  'AZ': 28,
  'BA': 20,
  'BE': 16,
  'BG': 22,
  'BH': 22,
  'BR': 29,
  'BY': 28,
  'CH': 21,
  'CR': 22,
  'CY': 28,
  'CZ': 24,
  'DE': 22,
  'DK': 18,
  'DO': 28,
  'EE': 20,
  'EG': 29,
  'ES': 24,
  'FI': 18,
  'FO': 18,
  'FR': 27,
  'GB': 22,
  'GE': 22,
  'GI': 23,
  'GL': 18,
  'GR': 27,
  'GT': 28,
  'HR': 21,
  'HU': 28,
  'IE': 22,
  'IL': 23,
  'IS': 26,
  'IT': 27,
  'JO': 30,
  'KW': 30,
  'KZ': 20,
  'LB': 28,
  'LC': 32,
  'LI': 21,
  'LT': 20,
  'LU': 20,
  'LV': 21,
  'MC': 27,
  'MD': 24,
  'ME': 22,
  'MK': 19,
  'MR': 27,
  'MT': 31,
  'MU': 30,
  'NL': 18,
  'NO': 15,
  'PK': 24,
  'PL': 28,
  'PS': 29,
  'PT': 25,
  'QA': 29,
  'RO': 24,
  'RS': 22,
  'SA': 24,
  'SE': 24,
  'SI': 19,
  'SK': 24,
  'SM': 27,
  'TN': 24,
  'TR': 26,
  'UA': 29,
  'VA': 22,
  'VG': 24,
  'XK': 20,
};

/// De IBAN-controle: juiste lengte voor de landcode, en mod-97 = 1 na
/// herschikking (ISO 7064). Spaties mogen; de aanroeper hoeft niet te normaliseren.
bool isValidIban(String raw) {
  final iban = raw.replaceAll(RegExp(r'[\s-]'), '').toUpperCase();
  if (iban.length < 15 || iban.length > 34) return false;

  final country = iban.substring(0, 2);
  final expected = ibanLengths[country];
  if (expected == null || iban.length != expected) return false;

  // De eerste vier tekens (land + controlecijfers) verhuizen naar achteren.
  final rearranged = iban.substring(4) + iban.substring(0, 4);

  // Letters worden getallen (A=10 … Z=35). Het resultaat is te groot voor een
  // int, dus we rekenen de modulo stapsgewijs uit in plaats van het hele getal
  // op te bouwen.
  var remainder = 0;
  for (var i = 0; i < rearranged.length; i++) {
    final code = rearranged.codeUnitAt(i);
    int value;
    if (code >= 0x30 && code <= 0x39) {
      value = code - 0x30;
      remainder = (remainder * 10 + value) % 97;
    } else if (code >= 0x41 && code <= 0x5a) {
      value = code - 0x41 + 10;
      remainder = (remainder * 100 + value) % 97;
    } else {
      return false;
    }
  }
  return remainder == 1;
}
