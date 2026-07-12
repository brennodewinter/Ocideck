import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/rfc3161_timestamp.dart';
import 'package:ocideck/utils/asn1_der.dart';

const _sha512Oid = [0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x03];
const _idSignedData = [0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x07, 0x02];
const _idCtTstInfo = [
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
    derSequence([derOid(_sha512Oid), derNull()]),
    derOctetString(hash),
  ]),
  derInteger(42), // serialNumber
  derTlv(0x18, genTime.codeUnits), // genTime (GeneralizedTime)
]);

/// A minimal but structurally-faithful timestamp token: a CMS wrapper whose
/// digestAlgorithms carry a **decoy** SHA-512 OID (to prove the parser navigates
/// to the real TSTInfo instead), then the TSTInfo inside the eContent.
Uint8List _token(List<int> hash, String genTime) => Uint8List.fromList(
  derSequence([
    derOid(_idSignedData),
    derTlv(
      0xa0,
      derSequence([
        derTlv(
          0x31,
          derSequence([
            derSequence([derOid(_sha512Oid), derNull()]),
          ]),
        ),
        derSequence([
          derOid(_idCtTstInfo),
          derTlv(0xa0, derOctetString(_tstInfo(hash, genTime))),
        ]),
      ]),
    ),
  ]),
);

String _hex(List<int> bytes) =>
    [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();

void main() {
  final hash = Uint8List.fromList(List.generate(64, (i) => i));

  group('buildTimeStampRequest', () {
    test('produces a parseable v1 request carrying the hash', () {
      final tsq = buildTimeStampRequest(hash);
      final root = parseDer(tsq)!;
      expect(root.tag, 0x30);
      expect(root.children.first.content, [1]); // version
      // The hashedMessage OCTET STRING equals the input hash.
      final octets = root.descendantsAndSelf.where((n) => n.tag == 0x04);
      expect(octets.any((n) => _hex(n.content) == _hex(hash)), isTrue);
      // certReq TRUE.
      expect(root.descendantsAndSelf.any((n) => n.tag == 0x01), isTrue);
    });
  });

  group('parseTimeStampToken', () {
    test('extracts the message imprint and genTime', () {
      final parsed = parseTimeStampToken(_token(hash, '20260712120000Z'))!;
      expect(parsed.messageImprintHex, _hex(hash));
      expect(parsed.genTime, DateTime.utc(2026, 7, 12, 12, 0, 0));
    });

    test('tolerates fractional seconds in genTime', () {
      final parsed = parseTimeStampToken(_token(hash, '20260712120000.5Z'))!;
      expect(parsed.genTime, DateTime.utc(2026, 7, 12, 12, 0, 0));
    });

    test('returns null on malformed input', () {
      expect(parseTimeStampToken(Uint8List.fromList([0x30, 0x03])), isNull);
    });
  });

  group('timeStampMatchesHash', () {
    test('true when the imprint equals the seal hash', () {
      expect(
        timeStampMatchesHash(_token(hash, '20260712120000Z'), _hex(hash)),
        isTrue,
      );
    });

    test('false for a different hash', () {
      expect(
        timeStampMatchesHash(_token(hash, '20260712120000Z'), 'deadbeef'),
        isFalse,
      );
    });
  });
}
