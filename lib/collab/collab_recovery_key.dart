// The recovery key for a device's collaboration identity (COLLABORATION Phase 2
// "Blok B"; SELF_ENCRYPTED_RELAY.md §5.3, §9.3). A device's identity lives as two
// 32-byte seeds in the keychain (`collab_device_store.dart`); losing the device
// loses the identity — and with it the fingerprint co-authors verified and the
// key that signs a deck's provenance (Blok C). The recovery key is that identity
// made portable: a readable string the user saves once and can type or paste on a
// new device to restore the *same* identity.
//
// Encoding, chosen for human transcription (owner's decision 2026-08-01):
//   payload = version(1) ‖ ed25519Seed(32) ‖ x25519Seed(32)   → 65 bytes
//   framed  = payload ‖ crc16(payload)(2)                      → 67 bytes
//   text    = Crockford-Base32(framed), grouped in fours with '-'
// Crockford Base32 omits I, L, O, U (no look-alike ambiguity) and is
// case-insensitive; the CRC-16 catches a mistyped or truncated key before it is
// ever written as an identity. No dependency, nothing security-critical here — the
// seeds are the secret, this is only their envelope.

import 'dart:typed_data';

/// The format version carried in byte 0. Bumped only if the payload layout
/// changes; [decodeRecoveryKey] rejects a version it does not know rather than
/// misreading old bytes as new.
const int kRecoveryKeyVersion = 1;

/// Crockford Base32 — digits plus A–Z without I, L, O, U.
const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Why a recovery key would not decode, so the UI can say which rather than a
/// generic failure: [format] (not valid Base32 / wrong length), [checksum] (a
/// typo — the CRC did not match), or [version] (from a newer build).
enum RecoveryKeyError { format, checksum, version }

/// Thrown by [decodeRecoveryKey]; carries a [reason] the UI localises.
class RecoveryKeyException implements Exception {
  const RecoveryKeyException(this.reason);
  final RecoveryKeyError reason;
  @override
  String toString() => 'RecoveryKeyException(${reason.name})';
}

/// The two identity seeds a recovery key carries.
class RecoveredSeeds {
  const RecoveredSeeds({required this.ed25519Seed, required this.x25519Seed});
  final List<int> ed25519Seed;
  final List<int> x25519Seed;
}

/// Encode [ed25519Seed] and [x25519Seed] (32 bytes each) into a grouped,
/// human-transcribable recovery key.
String encodeRecoveryKey(List<int> ed25519Seed, List<int> x25519Seed) {
  assert(ed25519Seed.length == 32 && x25519Seed.length == 32);
  final payload = Uint8List(65)
    ..[0] = kRecoveryKeyVersion
    ..setRange(1, 33, ed25519Seed)
    ..setRange(33, 65, x25519Seed);
  final crc = _crc16(payload);
  final framed = Uint8List(67)
    ..setRange(0, 65, payload)
    ..[65] = (crc >> 8) & 0xff
    ..[66] = crc & 0xff;
  return _group(_base32Encode(framed));
}

/// Decode a recovery key produced by [encodeRecoveryKey]. Tolerant of spacing,
/// hyphens and case; throws [RecoveryKeyException] on anything malformed so the
/// caller never writes a half-valid identity.
RecoveredSeeds decodeRecoveryKey(String input) {
  final framed = _base32Decode(input);
  if (framed.length != 67)
    throw const RecoveryKeyException(RecoveryKeyError.format);
  final payload = framed.sublist(0, 65);
  final crc = (framed[65] << 8) | framed[66];
  if (crc != _crc16(payload)) {
    throw const RecoveryKeyException(RecoveryKeyError.checksum);
  }
  if (payload[0] != kRecoveryKeyVersion) {
    throw const RecoveryKeyException(RecoveryKeyError.version);
  }
  return RecoveredSeeds(
    ed25519Seed: payload.sublist(1, 33),
    x25519Seed: payload.sublist(33, 65),
  );
}

/// CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF): a compact, well-understood
/// typo/truncation guard. Not a security check — the seeds are the secret.
int _crc16(List<int> bytes) {
  var crc = 0xFFFF;
  for (final b in bytes) {
    crc ^= (b & 0xff) << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc;
}

String _base32Encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final b in bytes) {
    buffer = (buffer << 8) | (b & 0xff);
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      out.write(_alphabet[(buffer >> bits) & 0x1f]);
    }
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
  return out.toString();
}

Uint8List _base32Decode(String input) {
  final cleaned = input.toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final ch in cleaned.split('')) {
    final v = _alphabet.indexOf(ch);
    if (v < 0) throw const RecoveryKeyException(RecoveryKeyError.format);
    buffer = (buffer << 5) | v;
    bits += 5;
    if (bits >= 8) {
      bits -= 8;
      out.add((buffer >> bits) & 0xff);
    }
  }
  return Uint8List.fromList(out);
}

/// Groups a Base32 string into blocks of four separated by '-', so it reads and
/// transcribes like a licence key rather than one long run.
String _group(String s) {
  final parts = <String>[];
  for (var i = 0; i < s.length; i += 4) {
    parts.add(s.substring(i, i + 4 > s.length ? s.length : i + 4));
  }
  return parts.join('-');
}
