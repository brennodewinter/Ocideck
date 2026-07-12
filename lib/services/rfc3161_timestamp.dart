import 'dart:typed_data';

import '../utils/asn1_der.dart';

/// RFC 3161 trusted timestamping (PENTEST_MIAUW §8-A2). OciDeck stays a
/// **producer of hashes**: it builds a TimeStampReq (`.tsq`) from the deck's
/// SHA-512 seal hash, the user has OpenKAT / a TSA timestamp it out-of-band, and
/// the returned token (`.tsr`) is imported and **verified in-app** — the token's
/// message imprint must equal the current seal hash, and its `genTime` proves
/// the seal existed before that moment. Full CMS-signature verification of the
/// TSA certificate is deliberately deferred (§8-A3); this verifies that the token
/// timestamps *this* document.

/// The hash algorithms whose OID this module recognises (for building a request
/// and for locating the message imprint in a token).
enum Rfc3161HashAlgorithm {
  sha1([0x2b, 0x0e, 0x03, 0x02, 0x1a]),
  sha256([0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01]),
  sha512([0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03]);

  const Rfc3161HashAlgorithm(this.oidBody);

  /// The DER OID body (the octets after tag+length).
  final List<int> oidBody;
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

/// Build an RFC 3161 `TimeStampReq` (`.tsq`) for [hash] under [algorithm]. The
/// request asks the TSA to return its certificate (`certReq = TRUE`).
Uint8List buildTimeStampRequest(
  Uint8List hash, {
  Rfc3161HashAlgorithm algorithm = Rfc3161HashAlgorithm.sha512,
}) {
  final tsq = derSequence([
    derInteger(1), // version v1
    derSequence([
      // MessageImprint
      derSequence([derOid(algorithm.oidBody), derNull()]), // hashAlgorithm
      derOctetString(hash), // hashedMessage
    ]),
    derBoolean(true), // certReq
  ]);
  return Uint8List.fromList(tsq);
}

/// The data extracted from a timestamp token that OciDeck can verify offline.
class TimeStampToken {
  const TimeStampToken({
    required this.messageImprintHex,
    required this.genTime,
  });

  /// The hex of the hash the TSA timestamped (the token's message imprint).
  final String messageImprintHex;

  /// The TSA's asserted time (`genTime`), in UTC.
  final DateTime genTime;
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
  return TimeStampToken(messageImprintHex: hex, genTime: genTime);
}

/// Whether [token] is a valid timestamp for [sealHashHex] (case-insensitive):
/// its message imprint equals the seal hash.
bool timeStampMatchesHash(Uint8List token, String sealHashHex) {
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
