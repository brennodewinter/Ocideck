import 'dart:typed_data';

import 'package:ocideck/utils/asn1_der.dart';

/// Gedeelde bouwstenen voor RFC 3161-tijdstempeltokens in tests. Zowel de
/// parser-tests als de zegel-dialoog hebben een token nodig dat er echt uitziet;
/// twee kopieën van dezelfde DER-constructie gaan uit elkaar lopen.
const sha512Oid = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03];
const idSignedData = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02];
const idCtTstInfo = [
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

List<int> _tstInfo(List<int> hash, String genTime) => derSequence([
  derInteger(1),
  derOid(const [0x2b, 0x06, 0x01]), // arbitrary policy OID
  derSequence([
    derSequence([derOid(sha512Oid), derNull()]),
    derOctetString(hash),
  ]),
  derInteger(42), // serialNumber
  derTlv(0x18, genTime.codeUnits), // genTime (GeneralizedTime)
]);

/// A minimal but structurally-faithful timestamp token: a CMS wrapper whose
/// digestAlgorithms carry a **decoy** SHA-512 OID (to prove the parser navigates
/// to the real TSTInfo instead), then the TSTInfo inside the eContent.
Uint8List fakeTimeStampToken(List<int> hash, String genTime) =>
    Uint8List.fromList(
      derSequence([
        derOid(idSignedData),
        derTlv(
          0xa0,
          derSequence([
            derTlv(
              0x31,
              derSequence([
                derSequence([derOid(sha512Oid), derNull()]),
              ]),
            ),
            derSequence([
              derOid(idCtTstInfo),
              derTlv(0xa0, derOctetString(_tstInfo(hash, genTime))),
            ]),
          ]),
        ),
      ]),
    );

/// Hex-encode bytes the way a deck stores its seal hash.
String hexOf(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

/// A 64-byte stand-in for a SHA-512 seal digest.
Uint8List sampleSealDigest() => Uint8List.fromList(List.generate(64, (i) => i));
