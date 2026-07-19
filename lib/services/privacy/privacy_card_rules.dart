// Creditcardnummers en hun beveiligingscode.
//
// De goedkoopste regel uit de financiële familie, en een die mensen aannemen dat
// hij er al is. Een PAN draagt een Luhn-controlecijfer én een IIN-bereik dat
// zegt van welk kaartschema hij is; die twee samen laten willekeurige
// cijferreeksen niet door.
//
// ── Waarom het IIN-bereik naast de Luhn moet ────────────────────────────────
//
// De Luhn alleen is te zwak: één op de tien willekeurige reeksen haalt hem.
// Vandaar de tweede eis, dat het nummer bij een bestaand kaartschema hoort. Pas
// samen zijn ze scherp — precies dezelfde redenering als bij de 11-proef en het
// contextwoord voor het BSN (§5.2), alleen is hier het tweede bewijs structureel
// in plaats van tekstueel.
//
// ── De botsing met de IMEI, die er al zat ───────────────────────────────────
//
// Een American Express-nummer is vijftien cijfers met een geldige Luhn, en dus
// op vorm niet van een IMEI te onderscheiden. Bij het bouwen van
// `digital.imei` is die botsing al opgelost door daar de Amex-bereiken 34 en 37
// uit te sluiten; deze regel pikt ze op. Dat de twee elkaar netjes aanvullen is
// dus geen toeval maar een eerder betaalde rekening.
//
// ── CVV: alleen in gezelschap ───────────────────────────────────────────────
//
// `123` betekent niets. Drie cijfers achter het woord `cvv` betekenen alleen
// iets als er ook een kaartnummer in de buurt staat — en dán betekenen ze
// meteen heel veel, want kaartnummer plus beveiligingscode is een bruikbare
// betaalinstructie. Vandaar dat `fin.cvv` nooit los vuurt.
//
// De vervaldatum staat hier bewust *niet* bij. §3-C noemt hem als tweede
// escalatiesignaal naast de CVV, maar die escalatie gaat naar `error` en die
// bestaat nog niet (zie de scanner voor waarom: beslissing §11.3). Een patroon
// dat niets verandert is dode code, dus hij komt terug wanneer
// `privacyStrictSeverity` er is.

import 'privacy_checksums.dart';

/// Een kandidaat-kaartnummer: 13 tot 19 cijfers, eventueel met spaties of
/// streepjes in groepjes.
///
/// Bewust ruim: de Luhn en het IIN-bereik doen het filterwerk, niet de regex.
final RegExp cardNumberPattern = RegExp(
  r'(?<![\d-])(?:\d[ -]?){12,18}\d(?![\d-])',
);

/// Het woord `cvv`/`cvc` gevolgd door drie of vier cijfers.
final RegExp cvvPattern = RegExp(
  r'\b(?:cvv|cvc|cvv2|cvc2|cid|beveiligingscode|security code|kaartcode)\b'
  r'\s*[:=]?\s*(\d{3,4})\b',
  caseSensitive: false,
);

/// De IIN-bereiken van de schema's die §3-C noemt.
///
/// Per schema het prefix en de toegestane lengtes. Bewust geen open einde: een
/// nummer dat wél de Luhn haalt maar bij geen enkel schema hoort, is geen
/// kaartnummer maar toeval.
const List<({String name, List<String> prefixes, List<int> lengths})>
cardSchemes = [
  (name: 'Visa', prefixes: ['4'], lengths: [13, 16, 19]),
  (
    name: 'Mastercard',
    // 51-55 is het oude bereik; 2221-2720 het bereik dat in 2017 is bijgekomen.
    prefixes: [
      '51',
      '52',
      '53',
      '54',
      '55',
      '22',
      '23',
      '24',
      '25',
      '26',
      '270',
      '271',
      '2720',
    ],
    lengths: [16],
  ),
  (name: 'American Express', prefixes: ['34', '37'], lengths: [15]),
  (
    name: 'Discover',
    prefixes: ['6011', '644', '645', '646', '647', '648', '649', '65'],
    lengths: [16, 17, 18, 19],
  ),
  (
    name: 'JCB',
    prefixes: ['352', '353', '354', '355', '356', '357', '358'],
    lengths: [16, 17, 18, 19],
  ),
  (name: 'UnionPay', prefixes: ['62'], lengths: [16, 17, 18, 19]),
  (
    name: 'Maestro',
    prefixes: ['50', '56', '57', '58', '6304', '6759', '676'],
    lengths: [12, 13, 14, 15, 16, 17, 18, 19],
  ),
];

/// Alleen de cijfers, zonder de spaties en streepjes waarin een kaartnummer
/// meestal wordt opgeschreven.
String cardDigits(String raw) => raw.replaceAll(RegExp(r'[ -]'), '');

/// Het kaartschema waar [digits] bij hoort, of `null`.
///
/// De Mastercard-bereiken 22-27 vragen om de nauwkeurige variant: `2720` mag
/// wel en `2721` niet, dus een prefixvergelijking op twee tekens zou te ruim
/// zijn. Vandaar dat de langere prefixen eerst worden geprobeerd.
String? cardSchemeOf(String digits) {
  for (final scheme in cardSchemes) {
    if (!scheme.lengths.contains(digits.length)) continue;
    final sorted = [...scheme.prefixes]
      ..sort((a, b) => b.length.compareTo(a.length));
    for (final prefix in sorted) {
      if (!digits.startsWith(prefix)) continue;
      // Het Mastercard-bereik loopt tot en met 2720; alles daarboven valt af.
      if (prefix.length == 2 && prefix.startsWith('2')) {
        final head = int.tryParse(digits.substring(0, 4)) ?? 0;
        if (head < 2221 || head > 2720) continue;
      }
      return scheme.name;
    }
  }
  return null;
}

/// Is dit een geloofwaardig kaartnummer?
///
/// Drie eisen, en alle drie zijn nodig: de Luhn, een bestaand IIN-bereik met de
/// juiste lengte, en niet op de lijst met officiële testnummers. Die laatste
/// doorstaan de Luhn met opzet — dat is waar ze voor gemaakt zijn — en zouden
/// zonder de lijst als `zeker` scoren in elke handleiding die ze noemt.
bool isPlausibleCardNumber(String digits) =>
    cardSchemeOf(digits) != null && passesLuhn(digits);
