import 'dart:typed_data';

import 'package:archive/archive.dart';

const testOciServePackagePassword = 'test-only-32-byte-ascii-password';

/// Maakt een decodeerbare AE-2-fixture met dezelfde wirevelden als OciServe.
///
/// `package:archive` schrijft AE-1. AE-1 en AE-2 gebruiken dezelfde
/// ciphertext/HMAC-opbouw; AE-2 zet uitsluitend vendor version 2 en gebruikt
/// geen CRC. Daarom passen we die protocolvelden aan voor clientcontracttests.
Uint8List ociServeAesPackage(Map<String, List<int>> members) {
  final archive = Archive();
  for (final entry in members.entries) {
    archive.add(ArchiveFile.bytes(entry.key, entry.value));
  }
  final bytes = Uint8List.fromList(
    ZipEncoder(password: testOciServePackagePassword).encodeBytes(archive),
  );
  for (var i = 0; i + 9 <= bytes.length; i++) {
    if (bytes[i] == 0x01 &&
        bytes[i + 1] == 0x99 &&
        bytes[i + 2] == 0x07 &&
        bytes[i + 3] == 0x00 &&
        bytes[i + 4] == 0x01 &&
        bytes[i + 5] == 0x00 &&
        bytes[i + 6] == 0x41 &&
        bytes[i + 7] == 0x45 &&
        bytes[i + 8] == 0x03) {
      bytes[i + 4] = 0x02;
    }
  }
  for (var i = 0; i + 18 <= bytes.length; i++) {
    final local = _uint32(bytes, i) == 0x04034b50;
    final central = _uint32(bytes, i) == 0x02014b50;
    if (!local && !central) continue;
    final crcOffset = i + (local ? 14 : 16);
    bytes.fillRange(crcOffset, crcOffset + 4, 0);
  }
  return bytes;
}

int _uint32(Uint8List bytes, int offset) =>
    bytes[offset] |
    (bytes[offset + 1] << 8) |
    (bytes[offset + 2] << 16) |
    (bytes[offset + 3] << 24);
