// Digitale identificatoren: IP, MAC, IMEI, ICCID, IMSI, handles, device-ID's.
//
// Een familie die er makkelijker uitziet dan hij is. De patronen zijn triviaal —
// vier getallen met punten ertussen, zes hexparen met dubbele punten — en juist
// dáárom zit het werk hier volledig in de uitsluitingen. Een versienummer is
// vier getallen met punten. Een tijdstip is twee getallen met een dubbele punt.
// Een git-hash is hex. Zonder poorten meldt deze familie voornamelijk zichzelf.
//
// Drie soorten uitsluiting dragen het:
//
//   1. **De documentatiereeksen.** De IETF heeft hier expres bereiken voor
//      gereserveerd — RFC 5737 voor IPv4, RFC 3849 voor IPv6 — en elke
//      handleiding ter wereld gebruikt ze. Een scanner die op `192.0.2.1` afgaat,
//      gaat af op de voorbeelden in zijn eigen documentatie.
//   2. **De checksum, waar er een is.** IMEI en ICCID dragen een Luhn. Dat tilt
//      ze in één klap van "vijftien cijfers" naar `certain`.
//   3. **Het contextwoord, waar er géén checksum is.** Een kale UUID is te
//      generiek om iets te betekenen: hij is net zo goed een bestandsnaam, een
//      sessie-id of een primaire sleutel. Pas met `idfa`, `gaid` of `advertising`
//      ernaast is het een advertentie-identificator, en dus een persoonsgegeven.
//
// En één principiële: een RFC 1918-adres (`10.x`, `192.168.x`) is interne
// infrastructuur, geen persoonsgegeven. Het blijft `possible` — de melding is er
// wel, want een intern adresplan in een publieke slide is nog steeds een lek,
// maar het onderbreekt niemand.

import '../../models/privacy_finding.dart';
import 'privacy_checksums.dart';

/// Eén digitale regel: patroon plus de poort die er vals-positieven uit haalt.
class DigitalRule {
  final String id;
  final RegExp pattern;
  final PrivacyConfidence confidence;

  /// Extra controle bovenop de regex. Krijgt de volledige fragmenttekst mee,
  /// want sommige poorten kijken naar wat er vóór de treffer staat.
  final bool Function(RegExpMatch match, String text)? validate;

  const DigitalRule(
    this.id,
    this.pattern, {
    this.confidence = PrivacyConfidence.likely,
    this.validate,
  });
}

// ── IPv4 ─────────────────────────────────────────────────────────────────────

final RegExp _ipv4Pattern = RegExp(
  r'(?<![\w.])\d{1,3}(?:\.\d{1,3}){3}(?![\w.])',
);

/// Is elk octet 0-255? Zonder deze eis is `1.2.3.999` een IP en elk
/// versienummer met vier delen ook.
bool _octetsInRange(String value) =>
    value.split('.').every((part) => (int.tryParse(part) ?? 256) <= 255);

/// RFC 5737: de bereiken die expres voor documentatie zijn gereserveerd, plus de
/// adressen die per definitie niemand aanwijzen.
bool isDocumentationIpv4(String value) =>
    value.startsWith('192.0.2.') ||
    value.startsWith('198.51.100.') ||
    value.startsWith('203.0.113.') ||
    value == '127.0.0.1' ||
    value == '0.0.0.0' ||
    value == '255.255.255.255' ||
    value.startsWith('224.') || // multicast
    value.startsWith('169.254.'); // link-local

/// RFC 1918 en RFC 6598: privé-adresruimte. Interne infrastructuur, geen
/// persoonsgegeven — vandaar `possible` in plaats van `likely`.
bool isPrivateIpv4(String value) {
  final parts = value.split('.').map(int.parse).toList();
  if (parts[0] == 10) return true;
  if (parts[0] == 192 && parts[1] == 168) return true;
  if (parts[0] == 172 && parts[1] >= 16 && parts[1] <= 31) return true;
  if (parts[0] == 100 && parts[1] >= 64 && parts[1] <= 127) return true;
  return false;
}

/// Staat er een `v` of een `versie`-achtig woord vóór de treffer?
///
/// `v1.2.3.4` en `versie 10.0.19041.1` zijn geen adressen, en ze komen in
/// technische slides veel vaker voor dan echte IP's.
bool _looksLikeVersion(String text, int start) {
  if (start == 0) return false;
  final before = text.substring(0, start).toLowerCase();
  if (before.endsWith('v')) return true;
  final tail = before.length > 24
      ? before.substring(before.length - 24)
      : before;
  return tail.contains('versie ') ||
      tail.contains('version ') ||
      tail.contains('build ') ||
      tail.contains('release ');
}

// ── IPv6 ─────────────────────────────────────────────────────────────────────

/// De volledige IPv6-grammatica, en dat is hier geen perfectionisme maar
/// noodzaak.
///
/// De voor de hand liggende korte versie — "twee tot zeven groepen hex met
/// dubbele punten ertussen" — matcht óók `00:00:00:00:00:00` (een MAC-adres) en
/// `01:02:03` (een tijdsduur). Beide stonden in de test en beide gingen af.
///
/// De discriminant is dat een echt IPv6-adres altijd één van tweeën is: een
/// samengetrokken vorm mét `::`, of acht volle groepen. Een MAC heeft er zes en
/// een tijdstip drie, geen van beide met `::` — en dus vallen ze er allebei
/// buiten zodra je die eis stelt. Elke tak hieronder eist dat.
final RegExp _ipv6Pattern = RegExp(
  r'(?<![\w:.])(?:'
  r'(?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}' // acht volle groepen
  r'|(?:[0-9a-fA-F]{1,4}:){1,7}:' // `::` aan het eind
  r'|(?:[0-9a-fA-F]{1,4}:){1,6}:[0-9a-fA-F]{1,4}'
  r'|(?:[0-9a-fA-F]{1,4}:){1,5}(?::[0-9a-fA-F]{1,4}){1,2}'
  r'|(?:[0-9a-fA-F]{1,4}:){1,4}(?::[0-9a-fA-F]{1,4}){1,3}'
  r'|(?:[0-9a-fA-F]{1,4}:){1,3}(?::[0-9a-fA-F]{1,4}){1,4}'
  r'|(?:[0-9a-fA-F]{1,4}:){1,2}(?::[0-9a-fA-F]{1,4}){1,5}'
  r'|[0-9a-fA-F]{1,4}:(?::[0-9a-fA-F]{1,4}){1,6}'
  r'|:(?:(?::[0-9a-fA-F]{1,4}){1,7}|:)' // `::` aan het begin
  r')(?![\w:.])',
);

/// RFC 3849: `2001:db8::/32` is het IPv6-documentatiebereik.
bool isDocumentationIpv6(String value) {
  final lower = value.toLowerCase();
  return lower.startsWith('2001:db8:') ||
      lower.startsWith('2001:0db8:') ||
      lower == '::' ||
      lower == '::1' ||
      lower.startsWith('fe80:') || // link-local
      lower.startsWith('ff02:'); // multicast
}

// ── MAC ──────────────────────────────────────────────────────────────────────

final RegExp _macPattern = RegExp(
  r'(?<![\w:.-])[0-9a-fA-F]{2}(?:[:-][0-9a-fA-F]{2}){5}(?![\w:.-])',
);

/// De adressen die geen apparaat aanwijzen: alles nul (niet toegekend) en alles
/// f (broadcast).
bool isMeaninglessMac(String value) {
  final hex = value.replaceAll(RegExp(r'[:-]'), '').toLowerCase();
  return hex == '000000000000' || hex == 'ffffffffffff';
}

// ── IMEI / ICCID / IMSI ──────────────────────────────────────────────────────

final RegExp _imeiPattern = RegExp(r'(?<!\d)\d{15}(?!\d)');

/// Een American Express-kaartnummer is óók vijftien cijfers met een geldige
/// Luhn, en dus niet van een IMEI te onderscheiden op vorm alleen.
///
/// Amex is het enige kaartmerk met vijftien cijfers, en zijn IIN-bereik is
/// `34` of `37`. Die ene uitsluiting ruimt daarmee de hele botsingsklasse op.
/// Dat dit nodig was, bleek niet uit nadenken maar uit de corpustest: het
/// Amex-testnummer stáát in `OCIWACHT.md`, in de alinea die uitlegt dat
/// testkaarten uitgesloten horen te zijn.
bool _looksLikeAmex(String digits) =>
    digits.startsWith('34') || digits.startsWith('37');

/// Een SIM-ICCID: begint met `89` (de ITU-branchecode voor telecom) en is 19 of
/// 20 cijfers lang. De Luhn erachter maakt hem `certain`.
final RegExp _iccidPattern = RegExp(r'(?<!\d)89\d{17,18}(?!\d)');

/// De IMSI heeft geen checksum, dus hier is een contextwoord verplicht.
final RegExp _imsiPattern = RegExp(r'(?<!\d)\d{15}(?!\d)');

const List<String> imeiContextWords = ['imei', 'toestel', 'handset', 'device'];
const List<String> imsiContextWords = ['imsi', 'sim', 'abonnee', 'subscriber'];

// ── Social handles ───────────────────────────────────────────────────────────

/// Profiel-URL's van de grote platforms. Het pad ná de host is het handvat, en
/// dat is precies wat een persoon aanwijst.
///
/// **GitHub staat er bewust niet bij.** Een `github.com/…`-link is in een
/// technisch deck vrijwel altijd een verwijzing naar een repository, niet naar
/// een persoon — en de vals-positievencorpustest bewees dat meteen door op onze
/// eigen `PENTEST_MIAUW.md` af te gaan. De platforms die er wél in staan hebben
/// geen andere betekenis dan "dit is iemands profiel".
///
/// De `@` in het pad is optioneel omdat Mastodon hem gebruikt
/// (`mastodon.social/@iemand`) en de rest niet.
final RegExp _profileUrlPattern = RegExp(
  r'https?://(?:[a-z0-9-]+\.)*(?:linkedin\.com/in|x\.com|twitter\.com|'
  r'facebook\.com|instagram\.com|t\.me|mastodon\.[a-z]+)/'
  r'@?[A-Za-z0-9._\-]{2,}',
  caseSensitive: false,
);

/// Een kale `@handle`.
///
/// De lookbehind is een *positieve* eis vermomd als negatieve: de `@` mag alleen
/// voorafgegaan worden door niets (regelbegin), witruimte of een openend
/// leesteken. Een handle begint namelijk altijd een token, en alles wat er
/// direct vóór plakt betekent dat de `@` een andere rol speelt:
///
///   * `marieke@acme.nl` — hoort bij het e-mailadres;
///   * `postgres://user:pass@host` — scheidt de authority in een URL;
///   * `mongodb://<user>:<password>@cluster` — idem, en dit stond letterlijk in
///     de secrets-test, waar het als handle afging.
///
/// Wat er daarna nog doorheen komt zijn annotaties en decorators
/// ([codeAnnotations]) — die staan wél op tokenbegin.
final RegExp _handlePattern = RegExp(
  r'''(?<![^\s(\[{"'])@([A-Za-z][A-Za-z0-9._]{2,29})(?![\w.@])''',
);

/// Annotaties en decorators die eruitzien als een handle maar het niet zijn.
const Set<String> codeAnnotations = {
  'override',
  'param',
  'return',
  'returns',
  'throws',
  'deprecated',
  'test',
  'author',
  'since',
  'see',
  'link',
  'todo',
  'nullable',
  'nonnull',
  'inject',
  'component',
  'injectable',
  'entity',
  'table',
  'column',
  'id',
  'media',
  'import',
  'charset',
  'keyframes',
  'supports',
  'font-face',
  'required',
  'observable',
  'state',
  'input',
  'output',
  'directive',
  'pragma',
  'immutable',
  'visiblefortesting',
  'protected',
  'mustcallsuper',
  'staticmethod',
  'property',
};

// ── Device- en advertentie-ID's ──────────────────────────────────────────────

final RegExp _uuidPattern = RegExp(
  r'(?<![\w-])[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}(?![\w-])',
);

const List<String> deviceIdContextWords = [
  'idfa',
  'gaid',
  'aaid',
  'advertising',
  'advertentie',
  'device id',
  'device-id',
  'deviceid',
  'apparaat-id',
];

/// De regels, in de volgorde waarin de scanner ze draait.
///
/// De volgorde is niet vrijblijvend: ICCID vóór IMEI, want een 19-cijferige
/// ICCID bevat geen 15-cijferige IMEI maar de patronen zouden elkaar wel in de
/// weg kunnen zitten als de grenzen ooit versoepelen.
final List<DigitalRule> digitalRules = [
  DigitalRule(
    'digital.ipv4',
    _ipv4Pattern,
    validate: (match, text) {
      final value = match.group(0)!;
      if (!_octetsInRange(value)) return false;
      if (isDocumentationIpv4(value)) return false;
      if (_looksLikeVersion(text, match.start)) return false;
      return true;
    },
  ),
  DigitalRule(
    'digital.ipv6',
    _ipv6Pattern,
    validate: (match, text) => !isDocumentationIpv6(match.group(0)!),
  ),
  DigitalRule(
    'digital.mac',
    _macPattern,
    validate: (match, text) => !isMeaninglessMac(match.group(0)!),
  ),
  DigitalRule(
    'digital.iccid',
    _iccidPattern,
    confidence: PrivacyConfidence.certain,
    validate: (match, text) => passesLuhn(match.group(0)!),
  ),
  DigitalRule(
    'digital.imei',
    _imeiPattern,
    confidence: PrivacyConfidence.certain,
    validate: (match, text) {
      final digits = match.group(0)!;
      if (_looksLikeAmex(digits)) return false;
      return passesLuhn(digits);
    },
  ),
  // `likely` en niet `certain`: dat er een profiel staat is zeker, dat het een
  // natúúrlijk persoon is niet — organisaties hebben ook accounts. Daarmee telt
  // een profiel-URL ook niet mee als persoonskoppeling voor artikel 9, en dat is
  // de juiste uitkomst.
  DigitalRule('digital.handle', _profileUrlPattern),
  DigitalRule(
    'digital.handle',
    _handlePattern,
    validate: (match, text) =>
        !codeAnnotations.contains(match.group(1)!.toLowerCase()),
  ),
];

/// Regels die een contextwoord nodig hebben, met dat woord erbij.
///
/// Apart van [digitalRules] omdat de contextpoort de fragmenttekst rondom de
/// treffer nodig heeft, en dat is werk van de scanner.
final List<({DigitalRule rule, List<String> contextWords})>
contextualDigitalRules = [
  (
    rule: DigitalRule(
      'digital.imsi',
      _imsiPattern,
      validate: (match, text) => !passesLuhn(match.group(0)!),
    ),
    contextWords: imsiContextWords,
  ),
  (
    rule: DigitalRule('digital.deviceid', _uuidPattern),
    contextWords: deviceIdContextWords,
  ),
];
