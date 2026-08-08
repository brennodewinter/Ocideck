import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../utils/asn1_der.dart';
import '../utils/secure_compare.dart';

/// RFC 3161-tijdstempels voor het documentzegel (PENTEST_MIAUW §8-A2). OciDeck
/// is hier een **producent van hashes**: het bouwt een TimeStampReq (`.tsq`) uit
/// de SHA-512-zegelhash, de gebruiker laat OpenKAT of een TSA die buiten de app
/// om tijdstempelen, en het teruggekomen token (`.tsr`) wordt geïmporteerd.
///
/// **Wat dit bestand doet.** Het ontleedt de TSTInfo uit het token, vergelijkt
/// de message imprint met de zegelhash, en *sinds #1370* verifieert het de
/// CMS-handtekening van de TSA tegen het in het token ingebedde certificaat
/// ([verifyTimeStampSignature]). Dat bewijst dat het token niet is gewijzigd
/// na ondertekening en dat de ondertekenaar de private key bij het ingebedde
/// certificaat had.
///
/// **Wat dit bestand niet controleert.** De certificaatketen van de TSA — er
/// wordt niet gecontroleerd of de ondertekenaar een TSA is (`id-kp-timeStamping`)
/// of überhaupt te vertrouwen valt. Volledige X.509-padvalidatie tegen een
/// vertrouwensanker staat op de roadmap als §8-A3; wie onweerlegbare
/// tijdsverankering nodig heeft, verifieert het token bij de TSA. OciDeck
/// bewaart het ongewijzigd zodat dat kan.
///
/// Wat OciDeck **sinds 2026-07-22 wél** doet (#563): de nonce van het uitstaande
/// verzoek bewaren in de zegel-sidecar en de echo bij het importeren nakijken.
/// Een ouder token voor dezelfde hash, opnieuw ingediend, wordt daardoor
/// geweigerd zolang er een verzoek uitstaat. Staat er geen verzoek uit, dan is
/// er niets te vergelijken en blijft de imprint het enige oordeel — zie
/// [timeStampEchoesNonce] en [buildTimeStampRequest].

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
/// De echo wordt sinds 2026-07-22 (#563) ook door OciDeck zelf nagekeken: de
/// nonce van het uitstaande verzoek staat in `<naam>.seal.json`
/// ([Deck.sealTimestampNonce]), zodat `_importTsr` een token kan weigeren dat
/// de imprint deelt maar het antwoord op een ánder verzoek is. Daarvóór kon
/// alleen iemand die beide bestanden bij de hand had dat zien.
///
/// De grens die daar wél blijft: staat er geen verzoek uit, dan is er niets te
/// vergelijken en blijft het bij de imprint. Een token dat van elders komt —
/// meegeleverd bij een deck, of van een eerdere machine — wordt dus op de
/// imprint beoordeeld en niet op de nonce.
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

/// Waarom een geïmporteerd tijdstempeltoken wel of niet als bewijs telt.
///
/// Twee faalvormen die uit elkaar gehouden moeten worden, want ze betekenen iets
/// anders voor de gebruiker: het token gaat over een ánder document, of het gaat
/// over dít document maar beantwoordt een ánder verzoek.
enum TimeStampImportVerdict {
  /// Imprint klopt, en de echo ook (of er stond geen verzoek uit).
  accepted,

  /// Het token stempelt een andere hash. Dit is niet dit document.
  imprintMismatch,

  /// De imprint klopt, maar de nonce van het uitstaande verzoek komt niet
  /// terug — een ouder token voor dezelfde hash, opnieuw ingediend.
  wrongRequest,
}

/// Beoordeelt [token] tegen [sealHash] en, wanneer er een verzoek uitstaat,
/// tegen [expectedNonceHex].
///
/// Los van de dialoog zodat dit oordeel toetsbaar is: in een widget-methode zou
/// het alleen via de bestandskiezer bereikbaar zijn, en die is platformspul.
///
/// **Geen uitstaand verzoek is geen fout.** Een leeg [expectedNonceHex] betekent
/// dat er niets te vergelijken valt — het token komt van elders, of is van vóór
/// deze build — en dan blijft de imprint het enige oordeel. Streng doen op een
/// nonce die nooit is verstuurd, zou een geldig token weigeren.
TimeStampImportVerdict judgeTimeStampImport(
  Uint8List token, {
  required String sealHash,
  required String expectedNonceHex,
}) {
  if (!timeStampImprintMatchesHash(token, sealHash)) {
    return TimeStampImportVerdict.imprintMismatch;
  }
  if (expectedNonceHex.isEmpty) return TimeStampImportVerdict.accepted;
  final nonce = decodeHashHex(expectedNonceHex);
  if (nonce == null || !timeStampEchoesNonce(token, nonce)) {
    return TimeStampImportVerdict.wrongRequest;
  }
  return TimeStampImportVerdict.accepted;
}

/// Of [token] de [nonce] terugkaatst die in het bijbehorende verzoek stond.
///
/// Dit is wat een nonce doet: hij bindt één token aan één verzoek. Een token
/// dat de imprint deelt maar een andere (of geen) nonce draagt, is het antwoord
/// op een ándere vraag — mogelijk een oudere, opnieuw ingediende. Een
/// imprint-vergelijking alleen ziet dat verschil niet.
///
/// Merk op: dit vergt beide helften. Het deck bewaart de nonce van het
/// uitstaande verzoek daarom in zijn zegel-sidecar; zonder uitstaand verzoek is
/// er niets te vergelijken. Zie [buildTimeStampRequest].
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

  return constantTimeEqualsString(trim(parsed!.nonceHex!), trim(_hex(nonce)));
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
      constantTimeEqualsString(
        parsed.messageImprintHex.toLowerCase(),
        sealHashHex.toLowerCase(),
      );
}

bool _isHashOid(Uint8List oid) {
  for (final alg in Rfc3161HashAlgorithm.values) {
    if (_bytesEqual(oid, alg.oidBody)) return true;
  }
  return false;
}

bool _bytesEqual(List<int> a, List<int> b) => constantTimeEqualsBytes(a, b);

/// De hex-vorm waarin een nonce in de zegel-sidecar wordt bewaard.
///
/// Dezelfde vorm als waarin [TimeStampToken.nonceHex] terugkomt, zodat de
/// vergelijking bij het importeren geen omweg nodig heeft.
String timeStampNonceHex(List<int> nonce) => _hex(nonce);

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

// ── CMS-signatuurverificatie (#1370) ─────────────────────────────────────────
//
// OciDeck verifieert de CMS-handtekening van de TSA tegen het certificaat dat
// in het token zelf is ingebed. Dat bewijst dat het token niet is gewijzigd
// na ondertekening en dat de ondertekenaar de private key had. Het bewijst
// niet dat het certificaat te vertrouwen is — daarvoor is padvalidatie tegen
// een vertrouwensanker nodig (roadmap §8-A3).
//
// Ondersteund: RSA-PKCS#1 v1.5 met SHA-256/384/512 (de meest voorkomende TSA-
// configuratie). ECDSA is nog niet geïmplementeerd; een token met een ECDSA-
// handtekening retourneert [TimeStampSignatureStatus.unsupportedAlgorithm].

/// Uitslag van de CMS-signatuurverificatie.
enum TimeStampSignatureStatus {
  /// De handtekening klopt tegen het ingebedde certificaat.
  verified,

  /// De handtekening klopt niet — het token is gemanipuleerd.
  invalid,

  /// Geen SignedData-structuur of geen certificaat gevonden.
  notSigned,

  /// Het sleuteltype of algoritme wordt niet ondersteund (bijv. ECDSA).
  unsupportedAlgorithm,
}

/// OID `1.2.840.113549.1.7.2` — `id-signedData`.
const _oidSignedData = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02];

/// OID `1.2.840.113549.1.1.1` — `rsaEncryption` (sleuteltype in het certificaat).
const _oidRsaEncryption = [
  0x2a,
  0x86,
  0x48,
  0x86,
  0xf7,
  0x0d,
  0x01,
  0x01,
  0x01,
];

/// OID `1.2.840.113549.1.9.4` — `id-messageDigest` (signedAttrs-attribuut).
const _oidMessageDigest = [
  0x2a,
  0x86,
  0x48,
  0x86,
  0xf7,
  0x0d,
  0x01,
  0x09,
  0x04,
];

/// SHA-256/384/512 OID-bodies voor digest-herkenning in SignerInfo.
const _oidSha256 = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01];
const _oidSha384 = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x02];
const _oidSha512 = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03];

/// RSA-handtekeningalgoritmen (signatureAlgorithm in SignerInfo).
const _oidSha256WithRsa = [
  0x2a,
  0x86,
  0x48,
  0x86,
  0xf7,
  0x0d,
  0x01,
  0x01,
  0x0b,
];
const _oidSha384WithRsa = [
  0x2a,
  0x86,
  0x48,
  0x86,
  0xf7,
  0x0d,
  0x01,
  0x01,
  0x0c,
];
const _oidSha512WithRsa = [
  0x2a,
  0x86,
  0x48,
  0x86,
  0xf7,
  0x0d,
  0x01,
  0x01,
  0x0d,
];

/// Verifieer de CMS-handtekening van [token] tegen het ingebedde TSA-certificaat.
///
/// Dit is een **zelfstandige** verificatie: het certificaat wordt uit het token
/// zelf gehaald, niet uit een externe vertrouwenslijst. De garantie is dus dat
/// het token intern consistent is (de handtekening past bij de ingebedde sleutel
/// en bij de TSTInfo), niet dat de TSA te vertrouwen is.
///
/// De functie retourneert [TimeStampSignatureStatus.verified] wanneer:
/// 1. het token een CMS SignedData-structuur bevat met ten minste één certificaat;
/// 2. de handtekening in SignerInfo past bij de publieke sleutel in dat certificaat;
/// 3. het message-digest-attribuut in signedAttrs overeenkomt met de hash van
///    de TSTInfo.
///
/// Zie de kop van dit bestand voor wat deze controle wél en niet bewijst.
Future<TimeStampSignatureStatus> verifyTimeStampSignature(
  Uint8List token,
) async {
  final root = parseDer(token);
  if (root == null) return TimeStampSignatureStatus.notSigned;

  // Zoek de SignedData-structuur: de SEQUENCE na het id-signedData OID.
  final signedData = _findSignedData(root);
  if (signedData == null) return TimeStampSignatureStatus.notSigned;

  // certificates: [0] IMPLICIT SET OF Certificate — de eerste volstaat
  // (een RFC 3161-token bevat typisch alleen het TSA-certificaat).
  final cert = _findFirstCertificate(signedData);
  if (cert == null) return TimeStampSignatureStatus.notSigned;

  // signerInfos: SET OF SignerInfo — de eerste volstaat.
  final signerInfo = _findFirstSignerInfo(signedData);
  if (signerInfo == null) return TimeStampSignatureStatus.notSigned;

  // signedAttrs: [0] IMPLICIT SET OF Attribute — de DER-bytes met de [0]-tag
  // moeten worden omgetagd naar SET OF (0x31) voor de handtekeningverificatie.
  final signedAttrsNode = _findChildByTag(signerInfo, 0xa0);
  if (signedAttrsNode == null) return TimeStampSignatureStatus.notSigned;

  // signatureAlgorithm: SEQUENCE na signedAttrs.
  final sigAlgNode = _findChildByTag(signerInfo, 0x30, afterTag: 0xa0);
  if (sigAlgNode == null) return TimeStampSignatureStatus.notSigned;

  // signature: OCTET STRING na signatureAlgorithm.
  final sigNode = _findChildByTag(
    signerInfo,
    0x04,
    afterTag: 0x30,
    afterContent: sigAlgNode.content,
  );
  if (sigNode == null) return TimeStampSignatureStatus.notSigned;

  // digestAlgorithm: SEQUENCE (vóór signedAttrs) — bepaalt de hash over eContent.
  final digestAlgNode = _findDigestAlgorithm(signerInfo);
  if (digestAlgNode == null) return TimeStampSignatureStatus.notSigned;

  // eContent: de OCTET STRING met TSTInfo-bytes, uit encapContentInfo.
  final eContent = _findEContent(signedData);
  if (eContent == null) return TimeStampSignatureStatus.notSigned;

  // 1. Hash de eContent met de digest-algoritme uit SignerInfo.
  final digestOid = _algorithmOid(digestAlgNode);
  final hasher = _hasherForOid(digestOid);
  if (hasher == null) return TimeStampSignatureStatus.unsupportedAlgorithm;
  final digest = await hasher.hash(eContent);
  final digestBytes = Uint8List.fromList(digest.bytes);

  // 2. Controleer het message-digest-attribuut in signedAttrs.
  final msgDigestAttr = _findMessageDigest(signedAttrsNode);
  if (msgDigestAttr == null) return TimeStampSignatureStatus.invalid;
  if (!constantTimeEqualsBytes(msgDigestAttr, digestBytes)) {
    return TimeStampSignatureStatus.invalid;
  }

  // 3. Bepaal het signatuuralgoritme en de bijbehorende hash.
  //    Sommige TSA's (zoals openssl) zetten signatureAlgorithm op `rsaEncryption`
  //    (1.2.840.113549.1.1.1) i.p.v. `sha256WithRSAEncryption` — in dat geval
  //    komt de hash uit het digestAlgorithm-veld van SignerInfo.
  final sigAlgOid = _algorithmOid(sigAlgNode);
  final sigHasher = _hasherForSignatureOid(sigAlgOid) ?? hasher;
  if (_isRsaEncryption(sigAlgOid)) {
    // rsaEncryption zonder geëxpliciteerde hash — gebruik de digestAlgorithm-hash.
  } else if (!_isRsaPkcs1v15(sigAlgOid)) {
    return TimeStampSignatureStatus.unsupportedAlgorithm;
  }

  // 4. Extraheer de publieke sleutel uit het certificaat.
  final pubKey = _extractRsaPublicKey(cert);
  if (pubKey == null) return TimeStampSignatureStatus.unsupportedAlgorithm;

  // 5. Re-encode signedAttrs met SET OF-tag (0x31) i.p.v. [0]-tag (0xA0).
  //    RFC 5652 §5.4: "The IMPLICIT [0] tag ... is not used for the
  //    DER encoding ... an encoding ... with the SET OF tag ... is used."
  final signedAttrsReencoded = Uint8List.fromList(
    derTlv(0x31, signedAttrsNode.content.toList()),
  );

  // 6. Hash de re-encoded signedAttrs met de signatuur-hash.
  final sigDigest = await sigHasher.hash(signedAttrsReencoded);
  final sigDigestBytes = Uint8List.fromList(sigDigest.bytes);

  // 7. Verifieer de RSA PKCS#1 v1.5 handtekening.
  //    De pure-Dart `cryptography`-package implementeert geen RSA verify,
  //    dus doen we het met BigInt.modPow + PKCS#1 v1.5 padding-check.
  final isCorrect = _verifyRsaPkcs1v15(
    sigNode.content,
    sigDigestBytes,
    pubKey.n,
    pubKey.e,
  );
  return isCorrect
      ? TimeStampSignatureStatus.verified
      : TimeStampSignatureStatus.invalid;
}

Asn1Node? _findSignedData(Asn1Node root) {
  final nodes = root.descendantsAndSelf.toList();
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].tag == 0x06 &&
        constantTimeEqualsBytes(nodes[i].content, _oidSignedData)) {
      // De [0] EXPLICIT wrapper na het OID bevat de SignedData SEQUENCE.
      for (var j = i + 1; j < nodes.length; j++) {
        if (nodes[j].tag == 0xa0) {
          // Binnen de [0] EXPLICIT staat de SignedData SEQUENCE.
          for (final child in nodes[j].children) {
            if (child.tag == 0x30) return child;
          }
        }
      }
      break;
    }
  }
  return null;
}

Asn1Node? _findFirstCertificate(Asn1Node signedData) {
  // certificates: [0] IMPLICIT SET OF Certificate.
  final certsNode = _findChildByTag(signedData, 0xa0);
  if (certsNode == null) return null;
  // De certificates-[0] is een SET OF Certificate — elk kind is een SEQUENCE.
  for (final child in certsNode.children) {
    if (child.tag == 0x30) return child;
  }
  return null;
}

Asn1Node? _findFirstSignerInfo(Asn1Node signedData) {
  // signerInfos: SET OF SignerInfo — de laatste SET in SignedData.
  // We onderscheiden van digestAlgorithms (ook een SET) door te checken dat
  // het eerste kind een SEQUENCE is die begint met een INTEGER (SignerInfo
  // version), terwijl AlgorithmIdentifier begint met een OID.
  for (final child in signedData.children) {
    if (child.tag == 0x31 && child.children.isNotEmpty) {
      final first = child.children.first;
      if (first.tag == 0x30 &&
          first.children.isNotEmpty &&
          first.children.first.tag == 0x02) {
        return first;
      }
    }
  }
  return null;
}

Asn1Node? _findChildByTag(
  Asn1Node parent,
  int tag, {
  int? afterTag,
  List<int>? afterContent,
}) {
  var seenAfter = afterTag == null;
  for (final child in parent.children) {
    if (!seenAfter) {
      if (child.tag == afterTag &&
          (afterContent == null ||
              constantTimeEqualsBytes(child.content, afterContent))) {
        seenAfter = true;
      }
      continue;
    }
    if (child.tag == tag) return child;
  }
  return null;
}

Asn1Node? _findDigestAlgorithm(Asn1Node signerInfo) {
  // digestAlgorithm is de SEQUENCE na sid (IssuerAndSerialNumber of [0] SKI).
  // Volgorde in SignerInfo: version, sid, digestAlgorithm, signedAttrs, ...
  // sid is SEQUENCE (IssuerAndSerialNumber) of [0] (SubjectKeyIdentifier).
  var seenSid = false;
  for (final child in signerInfo.children) {
    if (!seenSid) {
      // Sla version (INTEGER) over, dan is de volgende sid.
      if (child.tag == 0x30 || child.tag == 0x80) {
        seenSid = true;
      }
      continue;
    }
    if (child.tag == 0x30) return child; // digestAlgorithm SEQUENCE
  }
  return null;
}

List<int>? _algorithmOid(Asn1Node algId) {
  for (final child in algId.children) {
    if (child.tag == 0x06) return child.content.toList();
  }
  return null;
}

HashAlgorithm? _hasherForOid(List<int>? oid) {
  if (oid == null) return null;
  if (constantTimeEqualsBytes(oid, _oidSha256)) return Sha256();
  if (constantTimeEqualsBytes(oid, _oidSha384)) return Sha384();
  if (constantTimeEqualsBytes(oid, _oidSha512)) return Sha512();
  return null;
}

HashAlgorithm? _hasherForSignatureOid(List<int>? oid) {
  if (oid == null) return null;
  if (constantTimeEqualsBytes(oid, _oidSha256WithRsa)) return Sha256();
  if (constantTimeEqualsBytes(oid, _oidSha384WithRsa)) return Sha384();
  if (constantTimeEqualsBytes(oid, _oidSha512WithRsa)) return Sha512();
  // `rsaEncryption` (1.2.840.113549.1.1.1) zonder geëxpliciteerde hash:
  // de hash komt uit digestAlgorithm. Retourneer null hier — de aanroeper
  // valt terug op de digest-hash.
  return null;
}

/// Of het OID `rsaEncryption` (1.2.840.113549.1.1.1) is — RSA PKCS#1 v1.5
/// zonder geëxpliciteerde hash; de hash komt uit digestAlgorithm.
bool _isRsaEncryption(List<int>? oid) =>
    oid != null && constantTimeEqualsBytes(oid, _oidRsaEncryption);

/// Of het OID een `shaXXXWithRSAEncryption` is — RSA PKCS#1 v1.5 met
/// geëxpliciteerde hash.
bool _isRsaPkcs1v15(List<int>? oid) =>
    oid != null &&
    (constantTimeEqualsBytes(oid, _oidSha256WithRsa) ||
        constantTimeEqualsBytes(oid, _oidSha384WithRsa) ||
        constantTimeEqualsBytes(oid, _oidSha512WithRsa));

Uint8List? _findEContent(Asn1Node signedData) {
  // encapContentInfo: SEQUENCE met eContentType (OID) en eContent ([0] EXPLICIT
  // OCTET STRING). We zoeken de OCTET STRING die de TSTInfo bevat — dat is
  // de eContent na het id-ct-TSTInfo OID.
  final nodes = signedData.descendantsAndSelf.toList();
  for (var i = 0; i < nodes.length; i++) {
    if (nodes[i].tag == 0x06 &&
        constantTimeEqualsBytes(nodes[i].content, _oidTstInfo)) {
      // De [0] EXPLICIT wrapper bevat de OCTET STRING.
      for (var j = i + 1; j < nodes.length; j++) {
        if (nodes[j].tag == 0xa0) {
          for (final child in nodes[j].children) {
            if (child.tag == 0x04) return child.content;
          }
        }
        if (nodes[j].tag == 0x04) return nodes[j].content;
      }
      break;
    }
  }
  return null;
}

Uint8List? _findMessageDigest(Asn1Node signedAttrs) {
  // messageDigest-attribuut: SEQUENCE { OID(id-messageDigest), SET { OCTET STRING } }
  for (final attr in signedAttrs.children) {
    if (attr.tag != 0x30) continue;
    final children = attr.children;
    if (children.length < 2) continue;
    if (children[0].tag == 0x06 &&
        constantTimeEqualsBytes(children[0].content, _oidMessageDigest)) {
      // SET { OCTET STRING } — de hash.
      final setNode = children[1];
      for (final val in setNode.children) {
        if (val.tag == 0x04) return val.content;
      }
    }
  }
  return null;
}

/// De publieke sleutel uit een X.509-certificaat — modulus en exponent.
typedef RsaPubKey = ({List<int> n, List<int> e});

RsaPubKey? _extractRsaPublicKey(Asn1Node certificate) {
  // Certificate ::= SEQUENCE { tbsCertificate, signatureAlgorithm, signatureValue }
  // TBSCertificate ::= SEQUENCE { ... subjectPublicKeyInfo ... }
  // SubjectPublicKeyInfo ::= SEQUENCE { algorithm, subjectPublicKey BIT STRING }
  if (certificate.children.isEmpty) return null;
  final tbs = certificate.children[0];
  if (tbs.tag != 0x30) return null;

  // TBSCertificate kinderen: [0] version?, serialNumber, signature, issuer,
  // validity, subject, subjectPublicKeyInfo, ...
  // subjectPublicKeyInfo is het 7e kind (index 6) als version aanwezig is,
  // anders het 6e (index 5). We zoeken de SEQUENCE met een RSA-OID erin.
  for (final child in tbs.children) {
    if (child.tag != 0x30) continue;
    final algChildren = child.children;
    if (algChildren.length < 2) continue;
    // algorithm SEQUENCE met OID?
    final algSeq = algChildren[0];
    if (algSeq.tag != 0x30) continue;
    final oidNode = algSeq.children.isNotEmpty ? algSeq.children[0] : null;
    if (oidNode == null || oidNode.tag != 0x06) continue;
    if (!constantTimeEqualsBytes(oidNode.content, _oidRsaEncryption)) continue;

    // subjectPublicKey: BIT STRING — sla de eerste byte (unused bits) over.
    final bitString = algChildren[1];
    if (bitString.tag != 0x03) continue;
    final bitContent = bitString.content;
    if (bitContent.isEmpty || bitContent[0] != 0) continue; // 0 unused bits
    final keyBytes = Uint8List.sublistView(bitContent, 1);

    // RSAPublicKey ::= SEQUENCE { modulus INTEGER, publicExponent INTEGER }
    final rsaKey = parseDer(keyBytes);
    if (rsaKey == null || rsaKey.children.length < 2) return null;
    final modulus = rsaKey.children[0];
    final exponent = rsaKey.children[1];
    if (modulus.tag != 0x02 || exponent.tag != 0x02) return null;

    return (n: modulus.content.toList(), e: exponent.content.toList());
  }
  return null;
}

/// Verifieer een RSA PKCS#1 v1.5 handtekening met pure-Dart `BigInt.modPow`.
///
/// De `cryptography`-package implementeert RSA niet in pure Dart (alleen via
/// `cryptography_flutter`), dus doen we de modular exponentiatie + padding-
/// check zelf. Dit is ~15 regels en vermijdt een nieuwe afhankelijkheid.
///
/// PKCS#1 v1.5 signatuur: `s^e mod n` geeft `00 01 FF...FF 00 DigestInfo`,
/// waarbij DigestInfo een DER SEQUENCE is met de hash-algoritme OID en de hash.
bool _verifyRsaPkcs1v15(
  Uint8List signature,
  Uint8List expectedHash,
  List<int> modulusBytes,
  List<int> exponentBytes,
) {
  final n = _bytesToBigInt(modulusBytes);
  final e = _bytesToBigInt(exponentBytes);
  final s = _bytesToBigInt(signature);
  if (n == BigInt.zero || s >= n) return false;

  // RSA verification: m = s^e mod n
  final m = s.modPow(e, n);
  final keyLen = (n.bitLength + 7) ~/ 8;
  final em = _bigIntToBytes(m, keyLen);

  // PKCS#1 v1.5 padding: 00 01 FF...FF 00 DigestInfo
  if (em.length < 11 || em[0] != 0x00 || em[1] != 0x01) return false;
  var i = 2;
  while (i < em.length && em[i] == 0xff) {
    i++;
  }
  if (i < 10 || i >= em.length || em[i] != 0x00) return false; // min 8 FF's
  i++; // skip the 00 separator

  // DigestInfo ::= SEQUENCE { AlgorithmIdentifier, OCTET STRING }
  final digestInfo = parseDer(Uint8List.fromList(em.sublist(i)));
  if (digestInfo == null || digestInfo.children.length < 2) return false;
  final hashOctetString = digestInfo.children[1];
  if (hashOctetString.tag != 0x04) return false;

  return constantTimeEqualsBytes(hashOctetString.content, expectedHash);
}

BigInt _bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

List<int> _bigIntToBytes(BigInt value, int length) {
  final out = List<int>.filled(length, 0);
  var v = value;
  for (var i = length - 1; i >= 0 && v != BigInt.zero; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}
