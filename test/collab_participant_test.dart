import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/collab/collab_participant.dart';

void main() {
  group('deviceFingerprint', () {
    test('formats bytes as uppercase hex in groups of four', () {
      expect(deviceFingerprint([0x00, 0xab, 0xcd, 0xef, 0x12]), '00AB CDEF 12');
    });

    test('pads each byte to two hex digits', () {
      // 0x0a must render as "0A", not "A" — otherwise two keys could collide.
      expect(deviceFingerprint([0x0a, 0x01]), '0A01');
    });

    test('a full 32-byte identity key becomes 16 four-char groups', () {
      final key = [for (var i = 0; i < 32; i++) i];
      final fp = deviceFingerprint(key);
      expect(fp.split(' '), hasLength(16));
      expect(fp.replaceAll(' ', '').length, 64);
    });

    test('an empty key is the empty string', () {
      expect(deviceFingerprint(const []), '');
    });
  });
}
