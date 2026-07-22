import 'dart:math';
import 'dart:typed_data';

import '../utils/asn1_der.dart';

/// RFC 3161-tijdstempels voor het documentzegel (PENTEST_MIAUW §8-A2). OciDeck
/// is hier een **producent van hashes**: het bouwt een TimeStampReq (`.tsq`) uit
/// de SHA-512-zegelhash, de gebruiker laat OpenKAT of een TSA die buiten de app
/// om tijdstempelen, en het teruggekomen token (`.tsr`) wordt geïmporteerd.
///
/// **Wat dit bestand doet, en wat het niet doet.** Het ontleedt de TSTInfo uit
/// het token en vergelijkt de message imprint met de zegelhash. Dat is één
/// controle, en het is de enige: *hoort dit token bij dit document?*
///
/// Niet gecontroleerd worden:
///
/// - de **CMS-handtekening** van het token — er wordt niets geverifieerd van
///   wat de TSA over de TSTInfo heeft ondertekend;
/// - de **certificaatketen** van de TSA, en dus ook niet of de ondertekenaar
///   een TSA is (`id-kp-timeStamping`) of überhaupt te vertrouwen valt;
/// - de **echo van de nonce**. Het verzoek dráágt sinds kort een nonce, en RFC
///   3161 §2.4.2 verplicht de TSA die te herhalen — maar OciDeck bewaart de
///   nonce niet, dus bij het importeren valt er niets mee te vergelijken. Een
///   ouder token voor dezelfde hash, opnieuw ingediend, is voor deze app dus
///   niet te onderscheiden van een vers token. Wie beide helften heeft kan het
///   wél nakijken; zie [timeStampEchoesNonce] en [buildTimeStampRequest].
///
/// De praktische betekenis: `genTime` is een *bewering van het token*, geen
/// vastgesteld feit. Wie het deck heeft, kan zelf een token maken met een
/// willekeurige tijd en een kloppende imprint. Daarom heet dit hier geen
/// "trusted timestamp" en toont de interface geen groen vinkje, maar een
/// neutrale melding met de kanttekening erbij.
///
/// Waarom niet gebouwd: echte tokenverificatie vraagt X.509-padvalidatie tegen
/// een vertrouwensanker. Dat is een afhankelijkheid erbij (met SBOM- en
/// licentiegevolgen) plus een meegeleverde ankerlijst die per definitie
/// veroudert — in een applicatie die verder geen netwerk op gaat en waarvan de
/// belofte tamper-*evidence* is, niet tamper-*proof*. Wie onweerlegbare
/// tijdsverankering nodig heeft, verifieert het token bij de TSA; OciDeck
/// bewaart het ongewijzigd zodat dat kan.

/// The hash algorithms whose OID this module recognises (for building a request
/// and for locating the message imprint in a token).
enum Rfc3161HashAlgorithm {
  sha1([0x2b, 0x0e, 0x03, 0x02, 0x1a], 20),
  sha256([0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01], 32),
  sha512([0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03], 64);

  const Rfc3161HashAlgorithm(this.oidBody, this.digestBytes);

  /// The DER OID body (the octets after tag+length).
  final List<int> oidBody;

  /// The digest length in bytes. A MessageImprint that declares this algorithm
  /// but carries a different number of octets is malformed, and a TSA is
  /// entitled to reject it — better to notice that here than after the user has
  /// mailed the request off.
  final int digestBytes;
}

/// OID `1.2.840.113549.1.9.16.1.4` — `id-ct-TSTInfo`, the eContent type that
/// wraps the TSTInfo inside a timestamp token.
const _oidTstInfo = [
  0x2a,
  0x86,
  0x48,
  0x86,
  0xf7,
  0x0d,
  0x01,
  0x09,
  0x10,
  0x01,
  0x04,
];

/// Hoeveel bytes de nonce in een `TimeStampReq` telt. Acht is wat RFC 3161
/// §2.4.1 als "large random number" in de praktijk betekent; meer levert niets
/// op omdat de nonce alleen dít verzoek aan dít antwoord hoeft te binden.
const int kTimeStampNonceBytes = 8;

/// Build an RFC 3161 `TimeStampReq` (`.tsq`) for [hash] under [algorithm]. The
/// request asks the TSA to return its certificate (`certReq = TRUE`).
///
/// [nonce] wordt meegestuurd wanneer gegeven. RFC 3161 §2.4.2 verplicht de TSA
/// dezelfde waarde in het antwoord te herhalen, en dát is waar de nonce voor
/// dient: hij bindt één verzoek aan één token. Zonder nonce is elk geldig token
/// voor dezelfde imprint inwisselbaar voor elk ander — er valt dan niet vast te
/// stellen dát dit token het antwoord op dít verzoek is.
///
/// De echo is met [timeStampEchoesNonce] te controleren door wie beide helften
/// heeft. OciDeck zelf doet dat niet bij het importeren: het verzoek gaat
/// buiten de app om naar een TSA en het deck bewaart de nonce niet, dus na een
/// herstart is de andere helft weg. Dat is een bewuste grens en geen omissie.
///
/// De reden die daar oorspronkelijk bij stond — een sleutel erbij zou botsen
/// met de lopende verhuizing van het zegel naar een sidecar — geldt niet meer:
/// die verhuizing is af. `<naam>.seal.json` is nu precies de plek waar zo'n
/// nonce hoort (hij is ondoorzichtig en gaat over het document in plaats van
/// erin), dus de belemmering is weg. Wat overblijft is de keuze om het te
/// bouwen; tot dat gebeurt geldt de grens hierboven onverkort.
Uint8List buildTimeStampRequest(
  Uint8List hash, {
  Rfc3161HashAlgorithm algorithm = Rfc3161HashAlgorithm.sha512,
  Uint8List? nonce,
}) {
  final tsq = derSequence([
    derInteger(1), // version v1
    derSequence([
      // MessageImprint
      derSequence([derOid(algorithm.oidBody), derNull()]), // hashAlgorithm
      derOctetString(hash), // hashedMessage
    ]),
    // Volgorde volgens RFC 3161: de optionele nonce staat vóór certReq.
    if (nonce != null) derPositiveInteger(nonce),
    derBoolean(true), // certReq
  ]);
  return Uint8List.fromList(tsq);
}

/// Een verse nonce uit [Random.secure].
///
/// Nadrukkelijk de veilige generator: een voorspelbare nonce is geen nonce. Wie
/// de volgende waarde kan raden, kan vooraf een token laten maken dat straks
/// als antwoord op een nog te stellen vraag doorgaat.
Uint8List newTimeStampNonce() {
  final random = Random.secure();
  return Uint8List.fromList([
    for (var i = 0; i < kTimeStampNonceBytes; i++) random.nextInt(256),
  ]);
}

/// Decode a hex digest — the deck's `sealHash` as it is stored — to its bytes.
/// Returns null when [hex] is not an even-length run of hex digits.
///
/// Deliberately strict. The tempting version skips whatever it cannot read and
/// carries on, which turns a typo into a *different* imprint: the request then
/// asks a TSA to timestamp a document that does not exist, and the token that
/// comes back is worthless in exactly the situation it was meant for. Refusing
/// is the only safe answer.
Uint8List? decodeHashHex(String hex) {
  if (hex.isEmpty || hex.length.isOdd) return null;
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    // int.tryParse accepts a leading sign and surrounding whitespace, neither
    // of which is a hex digit; check the characters themselves.
    if (byte == null || !_isHexPair(hex, i * 2)) return null;
    out[i] = byte;
  }
  return out;
}

bool _isHexPair(String hex, int at) {
  for (var i = at; i < at + 2; i++) {
    final c = hex.codeUnitAt(i);
    final isDigit = c >= 0x30 && c <= 0x39;
    final isLower = c >= 0x61 && c <= 0x66;
    final isUpper = c >= 0x41 && c <= 0x46;
    if (!isDigit && !isLower && !isUpper) return false;
  }
  return true;
}

/// Build the `.tsq` for a deck's `sealHash`, or null when that hash is not a
/// well-formed digest of the right length for [algorithm].
///
/// The length check is the point: a request that announces SHA-512 and encloses
/// 32 octets is malformed, and the failure would surface at the TSA — out of
/// band, days later, to a user who no longer has the deck in front of them.
///
/// [nonce] gaat mee wanneer gegeven. Deze functie maakt er zelf géén: de
/// willekeur hoort aan de rand, zodat wat hier gebeurt een zuivere, herhaalbaar
/// te toetsen omzetting blijft.
Uint8List? buildTimeStampRequestForSealHash(
  String sealHashHex, {
  Rfc3161HashAlgorithm algorithm = Rfc3161HashAlgorithm.sha512,
  Uint8List? nonce,
}) {
  final hash = decodeHashHex(sealHashHex);
  if (hash == null || hash.length != algorithm.digestBytes) return null;
  return buildTimeStampRequest(hash, algorithm: algorithm, nonce: nonce);
}

/// De twee velden die OciDeck uit een tijdstempeltoken leest. Uitgelezen, niet
/// geverifieerd — zie de kop van dit bestand.
class TimeStampToken {
  const TimeStampToken({
    required this.messageImprintHex,
    required this.genTime,
    this.nonceHex,
  });

  /// The hex of the hash the TSA timestamped (the token's message imprint).
  final String messageImprintHex;

  /// Het tijdstip dat het token *beweert* (`genTime`), in UTC. Geen
  /// gecontroleerd feit: de handtekening eronder wordt niet geverifieerd.
  final DateTime genTime;

  /// De nonce die de TSA terugkaatste, of null wanneer het token er geen draagt
  /// (de nonce is optioneel in TSTInfo, en een TSA die er geen kreeg zet er ook
  /// geen).
  final String? nonceHex;
}

/// Parse a timestamp token (`.tsr` / TimeStampResp or a bare TimeStampToken):
/// locate the TSTInfo (the eContent following the `id-ct-TSTInfo` OID), then read
/// its message imprint hash and `genTime`. Returns null when the token is not
/// well-formed or lacks those fields.
TimeStampToken? parseTimeStampToken(Uint8List token) {
  final root = parseDer(token);
  if (root == null) return null;
  final nodes = root.descendantsAndSelf.toList();

  // The TSTInfo is the DER inside the OCTET STRING that follows id-ct-TSTInfo.
  Asn1Node? tstInfo;
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].tag == 0x06 && _bytesEqual(nodes[i].content, _oidTstInfo)) {
      for (var j = i + 1; j < nodes.length; j++) {
        if (nodes[j].tag == 0x04) {
          tstInfo = parseDer(nodes[j].content);
          break;
        }
      }
      break;
    }
  }
  if (tstInfo == null) return null;
  final tstNodes = tstInfo.descendantsAndSelf.toList();

  // messageImprint: the OCTET STRING after the first hash-algorithm OID.
  String? hex;
  for (var i = 0; i < tstNodes.length; i++) {
    if (tstNodes[i].tag == 0x06 && _isHashOid(tstNodes[i].content)) {
      for (var j = i + 1; j < tstNodes.length; j++) {
        if (tstNodes[j].tag == 0x04) {
          hex = _hex(tstNodes[j].content);
          break;
        }
      }
      break;
    }
  }

  // genTime: the GeneralizedTime inside TSTInfo.
  DateTime? genTime;
  for (final n in tstNodes) {
    if (n.tag == 0x18) {
      genTime = _parseGeneralizedTime(n.content);
      if (genTime != null) break;
    }
  }

  if (hex == null || genTime == null) return null;
  return TimeStampToken(
    messageImprintHex: hex,
    genTime: genTime,
    nonceHex: _nonceOf(tstInfo),
  );
}

/// De nonce uit een TSTInfo: de eerste INTEGER ná de `genTime`.
///
/// Bewust op de kinderen van TSTInfo zelf en niet op de platte lijst. Er staan
/// namelijk meer INTEGERs in een token — `version` en `serialNumber` staan er
/// vóór, en een optionele `accuracy` draagt er zelf ook een paar, maar die
/// zitten een niveau dieper. Op de platte lijst zou de eerste treffer na
/// `genTime` dus de secondenwaarde van `accuracy` kunnen zijn, en dan wordt een
/// echo-controle een vergelijking met een willekeurig ander getal.
String? _nonceOf(Asn1Node tstInfo) {
  var seenGenTime = false;
  for (final child in tstInfo.children) {
    if (child.tag == 0x18) {
      seenGenTime = true;
      continue;
    }
    if (seenGenTime && child.tag == 0x02) return _hex(child.content);
  }
  return null;
}

/// Of [token] de [nonce] terugkaatst die in het bijbehorende verzoek stond.
///
/// Dit is wat een nonce doet: hij bindt één token aan één verzoek. Een token
/// dat de imprint deelt maar een andere (of geen) nonce draagt, is het antwoord
/// op een ándere vraag — mogelijk een oudere, opnieuw ingediende. Een
/// imprint-vergelijking alleen ziet dat verschil niet.
///
/// Merk op: dit vergt beide helften. Wie alleen het token heeft — en dat is
/// OciDeck na een herstart, want het deck bewaart het verzoek niet — kan hier
/// niets mee. Zie [buildTimeStampRequest].
bool timeStampEchoesNonce(Uint8List token, Uint8List nonce) {
  final parsed = parseTimeStampToken(token);
  if (parsed?.nonceHex == null) return false;
  // Leidende nulbytes tellen niet mee: DER schrijft de kortste vorm, dus een
  // nonce die met 0x00 begint komt korter terug dan hij de deur uit ging.
  String trim(String hex) {
    var i = 0;
    while (i + 2 < hex.length && hex.startsWith('00', i)) {
      i += 2;
    }
    return hex.substring(i);
  }

  return trim(parsed!.nonceHex!) == trim(_hex(nonce));
}

/// Of de **message imprint** van [token] gelijk is aan [sealHashHex]
/// (hoofdletterongevoelig) — oftewel: hoort dit token bij dit document?
///
/// De naam zegt met opzet `Imprint` en niet `IsValid`. Dit is geen
/// geldigheidscontrole: de CMS-handtekening van de TSA en haar certificaatketen
/// worden niet gecontroleerd (zie de kop van dit bestand). Een aanroeper die
/// hieruit "het token is geldig" leest, vertelt de gebruiker meer dan er is
/// gecontroleerd, en dat is precies de bewering die dit zegel niet wil doen.
bool timeStampImprintMatchesHash(Uint8List token, String sealHashHex) {
  final parsed = parseTimeStampToken(token);
  return parsed != null &&
      parsed.messageImprintHex.toLowerCase() == sealHashHex.toLowerCase();
}

bool _isHashOid(Uint8List oid) {
  for (final alg in Rfc3161HashAlgorithm.values) {
    if (_bytesEqual(oid, alg.oidBody)) return true;
  }
  return false;
}

bool _bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

final _reGenTime = RegExp(r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})');

/// Parse an ASN.1 `GeneralizedTime` (`YYYYMMDDHHMMSS[.fff]Z`) to a UTC
/// [DateTime]. Fractional seconds and the trailing `Z` are ignored.
DateTime? _parseGeneralizedTime(Uint8List content) {
  final text = String.fromCharCodes(content);
  final m = _reGenTime.firstMatch(text);
  if (m == null) return null;
  return DateTime.utc(
    int.parse(m.group(1)!),
    int.parse(m.group(2)!),
    int.parse(m.group(3)!),
    int.parse(m.group(4)!),
    int.parse(m.group(5)!),
    int.parse(m.group(6)!),
  );
}
