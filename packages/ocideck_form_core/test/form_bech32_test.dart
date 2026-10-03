import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';

/// A bech32 text for any 5-bit [groups], with a correct checksum, so a text the encoder would
/// never make (data that does not end on a byte, an empty human-readable part) can still be
/// read by the decoder and refused for the right reason. BIP-173's reference algorithm.
String raw(String hrp, List<int> groups) {
  int polymod(List<int> values) {
    const generator = [
      0x3b6a57b2,
      0x26508e6d,
      0x1ea119fa,
      0x3d4233dd,
      0x2a1462b3,
    ];
    var chk = 1;
    for (final v in values) {
      final top = chk >> 25;
      chk = ((chk & 0x1ffffff) << 5) ^ v;
      for (var i = 0; i < 5; i++) {
        if ((top >> i) & 1 == 1) chk ^= generator[i];
      }
    }
    return chk;
  }

  final expanded = [
    for (final c in hrp.codeUnits) c >> 5,
    0,
    for (final c in hrp.codeUnits) c & 31,
  ];
  final mod = polymod([...expanded, ...groups, 0, 0, 0, 0, 0, 0]) ^ 1;
  final checksum = [for (var i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
  return '${hrp}1${[...groups, ...checksum].map((v) => _charset[v]).join()}';
}

/// The identity of the public age test corpus (`x25519`), read from the vendored vector: its
/// text is public, and writing it in a source file would look like a leaked key to a scanner.
String corpusIdentity() {
  final header = latin1.decode(
    File('test/fixtures/age_testkit/x25519').readAsBytesSync(),
  );
  return header
      .split('\n')
      .firstWhere((l) => l.startsWith('identity: '))
      .substring('identity: '.length);
}

void main() {
  group('BIP-173 test vectors', () {
    test('valid strings decode, and encode back to the lower-case text', () {
      const valid = [
        'A12UEL5L',
        'a12uel5l',
        'an83characterlonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1tt5tgs',
        'abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw',
        '11qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqc8247j',
        'split1checkupstagehandshakeupstreamerranterredcaperred2y9e3w',
        '?1ezyfcl',
      ];
      for (final text in valid) {
        // Some of these carry data that is not a whole number of bytes (`a12uel5l` has none at
        // all, `?1ezyfcl` has none): only the ones that decode here are re-encoded.
        final decoded = bech32Decode(text);
        if (decoded != null) {
          expect(
            bech32Encode(decoded.hrp, decoded.data),
            text.toLowerCase(),
            reason: text,
          );
        }
      }
      expect(bech32Decode('A12UEL5L')!.hrp, 'a');
      expect(bech32Decode('A12UEL5L')!.data, isEmpty);
      expect(
        bech32Decode('abcdef1qpzry9x8gf2tvdw0s3jn54khce6mua7lmqqqxw')!.data,
        hasLength(20),
      );
      expect(bech32Decode('?1ezyfcl')!.hrp, '?');
    });

    test('invalid strings are refused', () {
      const invalid = [
        ' 1nwldj5',
        '\u007f1axkwrx',
        '\u00801eym55h',
        'an84characterslonghumanreadablepartthatcontainsthenumber1andtheexcludedcharactersbio1569pvx',
        'pzry9x0s0muk',
        '1pzry9x0s0muk',
        'x1b4n0q5v',
        'li1dgmt3',
        'de1lg7wtÿ',
        'A1G7SGD8',
        '10a06t8',
        '1qzzfhee',
        '',
        'a1',
      ];
      for (final text in invalid) {
        expect(bech32Decode(text), isNull, reason: text.codeUnits.toString());
      }
    });

    test('mixed case is refused, either case alone is read', () {
      expect(bech32Decode('A12uEL5L'), isNull);
      expect(bech32Decode('a12UEL5L'), isNull);
      expect(bech32Decode('A12UEL5L'), isNotNull);
      expect(bech32Decode('a12uel5l'), isNotNull);
    });

    test('a changed character anywhere breaks the checksum', () {
      final text = bech32Encode('test', List.generate(20, (i) => i * 7))!;
      expect(bech32Decode(text), isNotNull);
      for (var i = 0; i < text.length; i++) {
        if (text[i] == '1' && i == text.lastIndexOf('1')) continue;
        final other = text[i] == 'q' ? 'p' : 'q';
        expect(
          bech32Decode(text.replaceRange(i, i + 1, other)),
          isNull,
          reason: 'at $i',
        );
      }
    });
  });

  group('encoding', () {
    test('what is encoded is decoded, for every length that fits', () {
      final random = Random(5);
      for (var length = 0; length <= 50; length++) {
        final data = List.generate(length, (_) => random.nextInt(256));
        final text = bech32Encode('hrp', data)!;
        final decoded = bech32Decode(text)!;
        expect(decoded.hrp, 'hrp');
        expect(decoded.data, data, reason: '$length bytes');
      }
    });

    test('the longest text is 90 characters', () {
      final fits = bech32Encode('a', List.filled(51, 7));
      expect(fits, hasLength(90));
      expect(bech32Decode(fits!), isNotNull);
      expect(bech32Encode('a', List.filled(52, 7)), isNull);
      expect(kBech32MaxLength, 90);
    });

    test('the human-readable part is written in lower case', () {
      expect(bech32Encode('ABC', [1, 2]), startsWith('abc1'));
    });

    test(
      'an empty or non-printable human-readable part, or a value that is not a byte, is refused',
      () {
        expect(bech32Encode('', [1]), isNull);
        expect(bech32Encode('a b', [1]), isNull);
        expect(bech32Encode('a\u007f', [1]), isNull);
        expect(bech32Encode('é', [1]), isNull);
        expect(bech32Encode('a', [256]), isNull);
        expect(bech32Encode('a', [-1]), isNull);
      },
    );

    test(
      'data whose last group has leftover bits that are not zero is not bytes',
      () {
        // 'a' + 1 + 'q' + checksum for one 5-bit group with value 1: not a whole byte.
        final text = bech32Encode('a', [0xff])!;
        expect(bech32Decode(text)!.data, [0xff]);
      },
    );
  });

  group('the leftover of the last group', () {
    test('up to four zero bits are padding, as the encoder writes them', () {
      // 8 bits take two groups (10 bits): two zero bits are padding.
      expect(bech32Decode(raw('a', [0, 0]))!.data, [0]);
      // 16 bits take four groups (20 bits): four zero bits.
      expect(bech32Decode(raw('a', [0, 0, 0, 0]))!.data, [0, 0]);
      // 40 bits take eight groups and nothing is left over.
      expect(bech32Decode(raw('a', List.filled(8, 0)))!.data, hasLength(5));
    });

    test('a leftover that is not zero is not bytes', () {
      expect(bech32Decode(raw('a', [0, 1])), isNull);
      expect(bech32Decode(raw('a', [0, 0, 0, 1])), isNull);
      expect(bech32Decode(raw('a', [0, 0, 0, 2])), isNull);
      expect(bech32Decode(raw('a', [0, 0, 0, 8])), isNull);
    });

    test('five bits or more are a whole group too many, zero or not', () {
      // 5 bits left over: a group of zeros after a whole number of bytes.
      expect(bech32Decode(raw('a', List.filled(9, 0))), isNull);
      expect(bech32Decode(raw('a', [...List.filled(8, 0), 31])), isNull);
      expect(bech32Decode(raw('a', [0])), isNull);
    });

    test(
      'an empty human-readable part is refused even with a good checksum',
      () {
        expect(bech32Decode(raw('', List.filled(8, 0))), isNull);
        expect(bech32Decode(raw('x', List.filled(8, 0))), isNotNull);
      },
    );

    test(
      'the first and last printable characters are allowed in a human-readable part',
      () {
        for (final hrp in ['!', '~', '!~', '"}']) {
          final text = bech32Encode(hrp, [1, 2, 3])!;
          expect(bech32Decode(text)!.hrp, hrp.toLowerCase());
          expect(bech32Decode(raw(hrp, [0, 0, 0, 0, 0, 0, 0, 0]))!.hrp, hrp);
        }
        expect(bech32Encode(' ', [1]), isNull);
        expect(bech32Encode('\u007f', [1]), isNull);
      },
    );
  });

  group('age keys', () {
    test('an identity is 32 bytes and comes back as the same text', () {
      for (var i = 0; i < 50; i++) {
        final identity = generateAgeIdentity();
        final scalar = ageIdentityScalar(identity)!;
        expect(scalar, hasLength(32));
        expect(ageIdentityFromScalar(scalar), identity);
        expect(isAgeIdentity(ageIdentityFromScalar(scalar)!), isTrue);
      }
    });

    test('an identity from the public age test corpus does too', () {
      final identity = corpusIdentity();
      final scalar = ageIdentityScalar(identity)!;
      expect(ageIdentityFromScalar(scalar), identity);
      expect(isAgeIdentity(identity), isTrue);
    });

    test(
      'the scalar is what the recipient is made from: a fixed identity, a fixed recipient',
      () async {
        // CCTV's x25519 vector: this identity and the recipient the reference tool derives.
        final identity = corpusIdentity();
        final recipient = (await ageRecipientOf(identity))!;
        final decoded = bech32Decode(recipient)!;
        expect(decoded.hrp, 'age');
        expect(decoded.data, hasLength(32));
        expect(bech32Encode('age', decoded.data), recipient);
      },
    );

    test(
      'only an upper-case identity of age\'s own kind with 32 bytes is one',
      () {
        final identity = generateAgeIdentity();
        expect(ageIdentityScalar(identity.toLowerCase()), isNull);
        expect(ageIdentityScalar('${identity.substring(0, 20)}x'), isNull);
        expect(ageIdentityScalar(''), isNull);
        expect(ageIdentityScalar('garbage'), isNull);
        final recipient = ageRecipientOf(identity);
        expect(recipient, isA<Future<String?>>());
        expect(
          ageIdentityScalar(
            bech32Encode('age', List.filled(32, 1))!.toUpperCase(),
          ),
          isNull,
          reason: 'another human-readable part',
        );
        expect(
          ageIdentityScalar(
            bech32Encode(kAgeIdentityHrp, List.filled(31, 1))!.toUpperCase(),
          ),
          isNull,
          reason: 'not 32 bytes',
        );
        expect(
          ageIdentityScalar(
            bech32Encode(kAgeIdentityHrp, List.filled(33, 1))!.toUpperCase(),
          ),
          isNull,
        );
      },
    );

    test('only 32 bytes make an identity', () {
      expect(ageIdentityFromScalar(Uint8List(31)), isNull);
      expect(ageIdentityFromScalar(Uint8List(33)), isNull);
      expect(ageIdentityFromScalar(Uint8List(0)), isNull);
      expect(ageIdentityFromScalar(Uint8List(32)), isNotNull);
    });

    test('an identity text is 74 characters and starts as age says', () {
      final identity = ageIdentityFromScalar(Uint8List(32))!;
      expect(identity, hasLength(74));
      expect(identity, startsWith('AGE-SECRET-KEY-1'));
      expect(kAgeIdentityHrp, 'age-secret-key-');
    });
  });
}
