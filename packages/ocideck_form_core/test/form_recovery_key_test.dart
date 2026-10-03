import 'dart:math';
import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// A recovery key text for any [payload], with the CRC of its first 66 bytes (or [crc]),
/// written the way [encodeFormRecoveryKey] writes it — so a layout the encoder would never
/// make can still be read by the decoder and refused for the right reason.
String forge(List<int> framedBody, {int? crc}) {
  final body = Uint8List.fromList(framedBody);
  final check = crc ?? _crc16(body);
  final framed = Uint8List(body.length + 2)
    ..setRange(0, body.length, body)
    ..[body.length] = (check >> 8) & 0xff
    ..[body.length + 1] = check & 0xff;
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in framed) {
    buffer = (buffer << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out.write(_alphabet[(buffer >> (bits - 5)) & 31]);
      bits -= 5;
    }
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

int _crc16(List<int> bytes) {
  var crc = 0xffff;
  for (final b in bytes) {
    crc ^= b << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xffff;
    }
  }
  return crc;
}

List<int> payload({
  int version = 1,
  int purpose = 0x46,
  int seedByte = 7,
  int scalarByte = 9,
}) => [
  version,
  purpose,
  ...List.filled(32, seedByte),
  ...List.filled(32, scalarByte),
];

FormRecoveryIssue issueOf(FormRecoveryDecoded r) =>
    (r as FormRecoveryRefused).issue;

void main() {
  late String identity;
  late Uint8List seed;
  setUp(() {
    identity = generateAgeIdentity();
    final random = Random(13);
    seed = Uint8List.fromList(List.generate(32, (_) => random.nextInt(256)));
  });

  group('the key', () {
    test('is read back as what it was made from', () {
      final text = encodeFormRecoveryKey(
        signingSeed: seed,
        ageIdentity: identity,
      );
      final r = decodeFormRecoveryKey(text) as FormRecoveredKey;
      expect(r.signingSeed, seed);
      expect(r.ageIdentity, identity);
    });

    test('is the same for the same secrets, and not for others', () {
      final a = encodeFormRecoveryKey(signingSeed: seed, ageIdentity: identity);
      expect(
        a,
        encodeFormRecoveryKey(signingSeed: seed, ageIdentity: identity),
      );
      expect(
        a,
        isNot(
          encodeFormRecoveryKey(
            signingSeed: seed,
            ageIdentity: generateAgeIdentity(),
          ),
        ),
      );
      final other = Uint8List.fromList(seed)..[0] ^= 1;
      expect(
        a,
        isNot(encodeFormRecoveryKey(signingSeed: other, ageIdentity: identity)),
      );
    });

    test(
      'is written in groups of four in Crockford base32: 109 characters',
      () {
        final text = encodeFormRecoveryKey(
          signingSeed: seed,
          ageIdentity: identity,
        );
        final groups = text.split('-');
        expect(groups, hasLength(28));
        expect(groups.take(27).every((g) => g.length == 4), isTrue);
        expect(groups.last, hasLength(1));
        expect(text.replaceAll('-', ''), hasLength(109));
        expect(text, matches(RegExp(r'^[0-9A-HJKMNP-TV-Z-]+$')));
      },
    );

    test(
      'is read however it was copied: case, spaces, line breaks, no hyphens',
      () {
        final text = encodeFormRecoveryKey(
          signingSeed: seed,
          ageIdentity: identity,
        );
        for (final copy in [
          text.toLowerCase(),
          text.replaceAll('-', ' '),
          text.replaceAll('-', '\n'),
          text.replaceAll('-', ''),
          '  $text\n',
          text.replaceAll('-', ' - '),
        ]) {
          final r = decodeFormRecoveryKey(copy);
          expect(r, isA<FormRecoveredKey>(), reason: copy);
          expect((r as FormRecoveredKey).ageIdentity, identity);
        }
      },
    );

    test('forgives what looks alike on paper: I and L for 1, O for 0', () {
      // Find a key that has a 1 and a 0 so both substitutions are made.
      for (var i = 0; i < 200; i++) {
        final id = generateAgeIdentity();
        final text = encodeFormRecoveryKey(signingSeed: seed, ageIdentity: id);
        if (!text.contains('1') || !text.contains('0')) continue;
        final swapped = text.replaceAll('1', 'I').replaceAll('0', 'O');
        expect(swapped, isNot(text));
        expect(
          (decodeFormRecoveryKey(swapped) as FormRecoveredKey).ageIdentity,
          id,
        );
        final lower = text.replaceAll('1', 'l').replaceAll('0', 'o');
        expect(
          (decodeFormRecoveryKey(lower) as FormRecoveredKey).ageIdentity,
          id,
        );
        return;
      }
      fail('no key with a 1 and a 0 in 200 tries');
    });

    test('is refused for secrets that are not the right size or kind', () {
      expect(
        () => encodeFormRecoveryKey(
          signingSeed: Uint8List(31),
          ageIdentity: identity,
        ),
        throwsArgumentError,
      );
      expect(
        () => encodeFormRecoveryKey(
          signingSeed: Uint8List(33),
          ageIdentity: identity,
        ),
        throwsArgumentError,
      );
      expect(
        () => encodeFormRecoveryKey(signingSeed: seed, ageIdentity: 'garbage'),
        throwsArgumentError,
      );
      expect(
        () => encodeFormRecoveryKey(
          signingSeed: seed,
          ageIdentity: identity.toLowerCase(),
        ),
        throwsArgumentError,
      );
    });

    test('the error never carries the secret', () {
      try {
        encodeFormRecoveryKey(
          signingSeed: seed,
          ageIdentity: 'AGE-SECRET-KEY-1NOTREALLY',
        );
        fail('should throw');
      } on ArgumentError catch (e) {
        expect(e.toString(), isNot(contains('NOTREALLY')));
      }
    });
  });

  group('a key that is not read', () {
    late String good;
    setUp(
      () => good = encodeFormRecoveryKey(
        signingSeed: seed,
        ageIdentity: identity,
      ),
    );

    test('nothing, too little, too much, or not base32', () {
      for (final bad in [
        '',
        '0',
        good.substring(0, 60),
        '$good-0000',
        'U${good.substring(1)}',
        '${good.substring(0, 10)}!${good.substring(11)}',
        'ÄÖ',
      ]) {
        expect(
          issueOf(decodeFormRecoveryKey(bad)),
          FormRecoveryIssue.format,
          reason: bad,
        );
      }
    });

    test('a typo or a truncation is a checksum failure, anywhere', () {
      final plain = good.replaceAll('-', '');
      for (var i = 0; i < plain.length; i++) {
        final c = plain[i];
        final other = c == '2' ? '3' : '2';
        final typo = plain.replaceRange(i, i + 1, other);
        final issue = issueOf(decodeFormRecoveryKey(typo));
        // The last character holds only leftover bits: changing it can also break them.
        expect(
          {FormRecoveryIssue.checksum, FormRecoveryIssue.format},
          contains(issue),
          reason: 'at $i',
        );
        if (i < plain.length - 1) {
          expect(issue, FormRecoveryIssue.checksum, reason: 'at $i');
        }
      }
    });

    test('leftover bits that are not zero are not this key', () {
      final plain = good.replaceAll('-', '');
      final last = _alphabet.indexOf(plain[plain.length - 1]);
      expect(last & 1, 0, reason: 'a 68-byte key ends in four zero bits');
      final other = plain.replaceRange(
        plain.length - 1,
        plain.length,
        _alphabet[last ^ 1],
      );
      expect(issueOf(decodeFormRecoveryKey(other)), FormRecoveryIssue.format);
    });

    test('another version, with a good checksum', () {
      expect(
        issueOf(decodeFormRecoveryKey(forge(payload(version: 2)))),
        FormRecoveryIssue.version,
      );
      expect(
        issueOf(decodeFormRecoveryKey(forge(payload(version: 0)))),
        FormRecoveryIssue.version,
      );
    });

    test('another purpose, with a good checksum', () {
      for (final purpose in [0, 0x43, 0x45, 0x47, 0xff]) {
        expect(
          issueOf(decodeFormRecoveryKey(forge(payload(purpose: purpose)))),
          FormRecoveryIssue.purpose,
          reason: '$purpose',
        );
      }
      expect(decodeFormRecoveryKey(forge(payload())), isA<FormRecoveredKey>());
    });

    test('the version is judged before the purpose', () {
      expect(
        issueOf(decodeFormRecoveryKey(forge(payload(version: 9, purpose: 1)))),
        FormRecoveryIssue.version,
      );
    });

    test('a wrong checksum is judged before version and purpose', () {
      expect(
        issueOf(
          decodeFormRecoveryKey(forge(payload(version: 9, purpose: 1), crc: 0)),
        ),
        FormRecoveryIssue.checksum,
      );
    });

    test(
      'a collaboration recovery key, which has no purpose and is 67 bytes, is the wrong length',
      () {
        // version(1) ‖ ed25519(32) ‖ x25519(32) ‖ crc(2): the layout of collab_recovery_key.dart.
        final collab = forge([1, ...List.filled(32, 5), ...List.filled(32, 6)]);
        expect(
          issueOf(decodeFormRecoveryKey(collab)),
          FormRecoveryIssue.format,
        );
      },
    );

    test('and the same for a key of 68 bytes that has none of this layout', () {
      // 66 bytes of payload whose second byte is not the purpose is a purpose failure, which
      // is how a future layout with the same length would be told apart.
      final other = forge([1, 0x43, ...List.filled(64, 3)]);
      expect(issueOf(decodeFormRecoveryKey(other)), FormRecoveryIssue.purpose);
    });
  });

  test('the constants', () {
    expect(kFormRecoveryVersion, 1);
    expect(kFormRecoveryPurpose, 0x46);
    expect(String.fromCharCode(kFormRecoveryPurpose), 'F');
  });
}
