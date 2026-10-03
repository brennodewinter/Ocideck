import 'dart:math';
import 'dart:typed_data';

import 'package:ocideck_form_core/src/form_base32.dart';
import 'package:test/test.dart';

void main() {
  group('RFC 4648 section 10, lower case, without padding', () {
    const vectors = {
      '': '',
      'f': 'my',
      'fo': 'mzxq',
      'foo': 'mzxw6',
      'foob': 'mzxw6yq',
      'fooba': 'mzxw6ytb',
      'foobar': 'mzxw6ytboi',
    };
    vectors.forEach((plain, encoded) {
      test('"$plain" is "$encoded"', () {
        final bytes = Uint8List.fromList(plain.codeUnits);
        expect(base32Encode(bytes), encoded);
        expect(base32Decode(encoded), bytes);
      });
    });
  });

  test(
    '32 bytes take 52 characters, 16 bytes take 26 (the length of an id)',
    () {
      expect(base32Encode(Uint8List(32)), hasLength(52));
      expect(base32Encode(Uint8List(16)), hasLength(26));
      expect(base32Encode(Uint8List(64)), hasLength(103));
    },
  );

  test('all bytes, all lengths: decode inverts encode', () {
    final random = Random(3);
    for (var length = 0; length < 70; length++) {
      final bytes = Uint8List.fromList(
        List.generate(length, (_) => random.nextInt(256)),
      );
      expect(base32Decode(base32Encode(bytes)), bytes, reason: '$length bytes');
    }
    expect(
      base32Decode(
        base32Encode(Uint8List.fromList(List.generate(256, (i) => i))),
      ),
      hasLength(256),
    );
  });

  test('only the alphabet [a-z2-7] is accepted', () {
    expect(base32Decode('MZXW6YTBOI'), isNull, reason: 'upper case');
    expect(base32Decode('mzxw6ytb0i'), isNull, reason: '0');
    expect(base32Decode('mzxw6ytb1i'), isNull, reason: '1');
    expect(base32Decode('mzxw6ytb8i'), isNull, reason: '8');
    expect(base32Decode('mzxw6ytb9i'), isNull, reason: '9');
    expect(base32Decode('mzxw6yq='), isNull, reason: 'padding');
    expect(base32Decode('mzxw 6yq'), isNull, reason: 'blank');
    expect(base32Decode('mzxw-6yq'), isNull, reason: 'hyphen');
    expect(base32Decode('mzxw6ytboé'), isNull, reason: 'non-ASCII');
  });

  test('a length no byte string has is refused', () {
    for (final n in [1, 3, 6, 9, 11, 14]) {
      expect(base32Decode('a' * n), isNull, reason: '$n characters');
    }
    for (final n in [0, 2, 4, 5, 7, 8, 10]) {
      expect(base32Decode('a' * n), isNotNull, reason: '$n characters');
    }
  });

  test('leftover bits must be zero: one byte has exactly one text', () {
    expect(base32Decode('my'), isNotNull);
    expect(base32Decode('mz'), isNull);
    expect(base32Decode('mzxq'), isNotNull);
    expect(base32Decode('mzxr'), isNull);
    expect(base32Decode('mzxw6yr'), isNull);
    expect(base32Decode('mzxw7'), isNull, reason: 'one leftover bit, set');
    expect(base32Decode('mzxw6'), isNotNull, reason: 'one leftover bit, clear');
    expect(base32Decode('aa'), Uint8List.fromList([0]));
    expect(base32Decode('ab'), isNull);
  });
}
