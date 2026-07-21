import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/rfc3161_timestamp.dart';
import 'package:ocideck/utils/asn1_der.dart';

import 'rfc3161_token_fixture.dart';

void main() {
  final hash = sampleSealDigest();

  group('buildTimeStampRequest', () {
    test('produces a parseable v1 request carrying the hash', () {
      final tsq = buildTimeStampRequest(hash);
      final root = parseDer(tsq)!;
      expect(root.tag, 0x30);
      expect(root.children.first.content, [1]); // version
      // The hashedMessage OCTET STRING equals the input hash.
      final octets = root.descendantsAndSelf.where((n) => n.tag == 0x04);
      expect(octets.any((n) => hexOf(n.content) == hexOf(hash)), isTrue);
      // certReq TRUE.
      expect(root.descendantsAndSelf.any((n) => n.tag == 0x01), isTrue);
    });
  });

  group('decodeHashHex', () {
    test('reads a hex digest back to its bytes, upper or lower case', () {
      expect(decodeHashHex('00ff10'), [0x00, 0xff, 0x10]);
      expect(decodeHashHex('00FF10'), [0x00, 0xff, 0x10]);
      expect(decodeHashHex(hexOf(hash)), hash);
    });

    test('refuses anything that is not a whole run of hex digits', () {
      // Half a byte: silently dropping the tail would shift every octet after
      // it and hand a TSA the imprint of a document that does not exist.
      expect(decodeHashHex('abc'), isNull);
      expect(decodeHashHex(''), isNull);
      expect(decodeHashHex('zz'), isNull);
      expect(decodeHashHex('ab cd'), isNull);
      // int.tryParse accepts these; hex does not.
      expect(decodeHashHex('+1'), isNull);
      expect(decodeHashHex('-1'), isNull);
    });
  });

  group('buildTimeStampRequestForSealHash', () {
    test('a well-formed SHA-512 seal yields the same request as the bytes', () {
      expect(
        buildTimeStampRequestForSealHash(hexOf(hash)),
        buildTimeStampRequest(hash),
      );
    });

    test('the imprint in the request is the seal, not something near it', () {
      final tsq = buildTimeStampRequestForSealHash(hexOf(hash))!;
      final octets = parseDer(
        tsq,
      )!.descendantsAndSelf.where((n) => n.tag == 0x04);
      expect(octets.map((n) => hexOf(n.content)), contains(hexOf(hash)));
    });

    test('a digest of the wrong length for the algorithm is refused', () {
      // 32 bytes announced as SHA-512: a TSA rejects this, days later and out
      // of band. Refuse it here, where the user can still act on it.
      final sha256 = hexOf(List.generate(32, (i) => i));
      expect(buildTimeStampRequestForSealHash(sha256), isNull);
      expect(
        buildTimeStampRequestForSealHash(
          sha256,
          algorithm: Rfc3161HashAlgorithm.sha256,
        ),
        isNotNull,
      );
    });

    test('a malformed seal hash is refused rather than half-read', () {
      expect(buildTimeStampRequestForSealHash(''), isNull);
      expect(buildTimeStampRequestForSealHash('niet-hex'), isNull);
      expect(buildTimeStampRequestForSealHash('${hexOf(hash)}a'), isNull);
    });

    test('every algorithm declares the digest length that matches its OID', () {
      for (final algorithm in Rfc3161HashAlgorithm.values) {
        final digest = hexOf(List.generate(algorithm.digestBytes, (i) => i));
        expect(
          buildTimeStampRequestForSealHash(digest, algorithm: algorithm),
          isNotNull,
          reason: '${algorithm.name} weigert zijn eigen digestlengte',
        );
      }
    });
  });

  group('parseTimeStampToken', () {
    test('extracts the message imprint and genTime', () {
      final parsed = parseTimeStampToken(
        fakeTimeStampToken(hash, '20260712120000Z'),
      )!;
      expect(parsed.messageImprintHex, hexOf(hash));
      expect(parsed.genTime, DateTime.utc(2026, 7, 12, 12, 0, 0));
    });

    test('tolerates fractional seconds in genTime', () {
      final parsed = parseTimeStampToken(
        fakeTimeStampToken(hash, '20260712120000.5Z'),
      )!;
      expect(parsed.genTime, DateTime.utc(2026, 7, 12, 12, 0, 0));
    });

    test('returns null on malformed input', () {
      expect(parseTimeStampToken(Uint8List.fromList([0x30, 0x03])), isNull);
    });
  });

  group('timeStampMatchesHash', () {
    test('true when the imprint equals the seal hash', () {
      expect(
        timeStampMatchesHash(
          fakeTimeStampToken(hash, '20260712120000Z'),
          hexOf(hash),
        ),
        isTrue,
      );
    });

    test('false for a different hash', () {
      expect(
        timeStampMatchesHash(
          fakeTimeStampToken(hash, '20260712120000Z'),
          'deadbeef',
        ),
        isFalse,
      );
    });
  });
}
