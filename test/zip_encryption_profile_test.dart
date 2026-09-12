import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/zip_encryption.dart';

import 'support/ociserve_aes_fixture.dart';

void main() {
  late Uint8List valid;

  setUp(() {
    valid = ociServeAesPackage({
      'lesson.md': utf8.encode('# Les'),
      'assets/image.txt': utf8.encode('beeld'),
    });
  });

  test('accepts every member of the explicit AE-2 server profile', () {
    expect(
      hasExactOciServeAesPackageProfile(
        valid,
        profile: ociServeAesPackageProfile,
      ),
      isTrue,
    );
  });

  test('refuses AE-1 and an unknown protocol profile', () {
    final ae1 = Uint8List.fromList(valid);
    _replaceAesVendorVersion(ae1, 1);

    expect(_valid(ae1), isFalse);
    expect(
      hasExactOciServeAesPackageProfile(valid, profile: 'future-profile'),
      isFalse,
    );
  });

  test('refuses mixed encryption and inconsistent local headers', () {
    final mixed = Uint8List.fromList(valid);
    final central = _signatureOffset(mixed, 0x02014b50);
    mixed[central + 8] &= 0xfe;

    final inconsistent = Uint8List.fromList(valid);
    final local = _signatureOffset(inconsistent, 0x04034b50);
    inconsistent[local + 8] = 8;
    inconsistent[local + 9] = 0;

    expect(_valid(mixed), isFalse);
    expect(_valid(inconsistent), isFalse);
  });

  test('refuses trailing bytes outside the declared ZIP', () {
    expect(_valid(Uint8List.fromList([...valid, 0, 1])), isFalse);
  });
}

bool _valid(Uint8List bytes) => hasExactOciServeAesPackageProfile(
  bytes,
  profile: ociServeAesPackageProfile,
);

void _replaceAesVendorVersion(Uint8List bytes, int version) {
  for (var offset = 0; offset + 11 <= bytes.length; offset++) {
    if (bytes[offset] == 0x01 &&
        bytes[offset + 1] == 0x99 &&
        bytes[offset + 2] == 0x07 &&
        bytes[offset + 3] == 0x00) {
      bytes[offset + 4] = version;
      bytes[offset + 5] = 0;
    }
  }
}

int _signatureOffset(Uint8List bytes, int signature) {
  for (var offset = 0; offset + 4 <= bytes.length; offset++) {
    final value =
        bytes[offset] |
        (bytes[offset + 1] << 8) |
        (bytes[offset + 2] << 16) |
        (bytes[offset + 3] << 24);
    if (value == signature) return offset;
  }
  throw StateError('ZIP signature ontbreekt in fixture');
}
