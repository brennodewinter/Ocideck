/// The recovery key of an organiser's editorial key (FORM_INTAKE.md §5.9, §7.6): the two
/// secrets — the Ed25519 seed that signs bundles and the age identity that opens
/// submissions — as one string a person writes down once and can type back on another
/// machine.
///
/// ```
/// payload = version(1) ‖ purpose(1) ‖ ed25519 seed(32) ‖ age identity scalar(32)   66 bytes
/// framed  = payload ‖ crc16(payload)(2)                                            68 bytes
/// text    = Crockford base32 of framed, in groups of four joined by '-'
/// ```
///
/// **It carries its own purpose byte** ([kFormRecoveryPurpose], `F`). The collaboration
/// identity has a recovery key of the same kind (`collab_recovery_key.dart`) whose payload has
/// none: an organiser who pasted *that* key into "restore the editorial key" would pass a
/// checksum and install the wrong X25519 key, after which every submission fails as `unknown
/// kid` — and a form published from the wrong signing key would show every respondent a
/// changed fingerprint. Here a collaboration key is the wrong length and has no purpose, and
/// a key of this layout with another purpose says so.
///
/// Crockford base32 has no `I`, `L`, `O` or `U` and is read case-insensitively, with `I`/`L` as
/// `1` and `O` as `0`: what a person copies from paper is forgiven. The CRC-16 catches a typo
/// or a truncation before anything is installed; it is not a security check — the seeds are the
/// secret, this is only their envelope.
library;

import 'dart:typed_data';

import 'form_bech32.dart';

/// The version byte of this layout.
const int kFormRecoveryVersion = 1;

/// The purpose byte: `F`, for the editorial key of forms.
const int kFormRecoveryPurpose = 0x46;

const String _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';

/// Why a recovery key was not read, so the screen can say which.
enum FormRecoveryIssue {
  /// Not base32, or not the length of this key — including a collaboration recovery key.
  format,

  /// A typo or a truncation: the checksum does not match.
  checksum,

  /// A version this build does not know.
  version,

  /// A key of this layout that was made for something else.
  purpose,
}

/// The outcome of [decodeFormRecoveryKey].
sealed class FormRecoveryDecoded {
  const FormRecoveryDecoded();
}

/// The two secrets of a recovery key.
class FormRecoveredKey extends FormRecoveryDecoded {
  const FormRecoveredKey({
    required this.signingSeed,
    required this.ageIdentity,
  });

  /// The Ed25519 seed, 32 bytes.
  final Uint8List signingSeed;

  /// The `AGE-SECRET-KEY-1…` identity.
  final String ageIdentity;
}

/// A recovery key that was not read.
class FormRecoveryRefused extends FormRecoveryDecoded {
  const FormRecoveryRefused(this.issue);

  final FormRecoveryIssue issue;
}

/// The recovery key of [signingSeed] (32 bytes) and [ageIdentity] (canonical
/// `AGE-SECRET-KEY-1…`), or throws [ArgumentError].
String encodeFormRecoveryKey({
  required List<int> signingSeed,
  required String ageIdentity,
}) {
  if (signingSeed.length != 32) {
    throw ArgumentError.value(
      signingSeed.length,
      'signingSeed',
      'must be 32 bytes',
    );
  }
  final scalar = ageIdentityScalar(ageIdentity);
  if (scalar == null) {
    throw ArgumentError.value(
      '<redacted>',
      'ageIdentity',
      'not an age identity',
    );
  }
  final payload = Uint8List(66)
    ..[0] = kFormRecoveryVersion
    ..[1] = kFormRecoveryPurpose
    ..setRange(2, 34, signingSeed)
    ..setRange(34, 66, scalar);
  final crc = _crc16(payload);
  final framed = Uint8List(68)
    ..setRange(0, 66, payload)
    ..[66] = (crc >> 8) & 0xff
    ..[67] = crc & 0xff;
  final text = _encode(framed);
  final groups = <String>[
    for (var i = 0; i < text.length; i += 4)
      text.substring(i, i + 4 > text.length ? text.length : i + 4),
  ];
  return groups.join('-');
}

/// Reads a recovery key as [encodeFormRecoveryKey] wrote it, whatever the case, spacing or
/// hyphens it was copied with. Never throws.
FormRecoveryDecoded decodeFormRecoveryKey(String text) {
  final framed = _decode(text);
  if (framed == null || framed.length != 68) {
    return const FormRecoveryRefused(FormRecoveryIssue.format);
  }
  final payload = framed.sublist(0, 66);
  final crc = (framed[66] << 8) | framed[67];
  if (crc != _crc16(payload)) {
    return const FormRecoveryRefused(FormRecoveryIssue.checksum);
  }
  if (payload[0] != kFormRecoveryVersion) {
    return const FormRecoveryRefused(FormRecoveryIssue.version);
  }
  if (payload[1] != kFormRecoveryPurpose) {
    return const FormRecoveryRefused(FormRecoveryIssue.purpose);
  }
  final identity = ageIdentityFromScalar(payload.sublist(34, 66))!;
  return FormRecoveredKey(
    signingSeed: Uint8List.fromList(payload.sublist(2, 34)),
    ageIdentity: identity,
  );
}

/// CRC-16/CCITT-FALSE (polynomial 0x1021, initial value 0xFFFF).
int _crc16(List<int> bytes) {
  var crc = 0xffff;
  for (final b in bytes) {
    crc ^= (b & 0xff) << 8;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 0x8000) != 0 ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xffff;
    }
  }
  return crc;
}

String _encode(List<int> bytes) {
  final out = StringBuffer();
  var buffer = 0;
  var bits = 0;
  for (final byte in bytes) {
    buffer = (buffer << 8) | (byte & 0xff);
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

/// The bytes of Crockford [input] — case-insensitive, `I` and `L` as `1`, `O` as `0`,
/// hyphens and white space ignored — or `null` for any other character or leftover bits that
/// are not zero.
Uint8List? _decode(String input) {
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final unit in input.toUpperCase().codeUnits) {
    final c = String.fromCharCode(unit);
    if (c == '-' || c.trim().isEmpty) continue;
    final normal = switch (c) {
      'I' || 'L' => '1',
      'O' => '0',
      _ => c,
    };
    final value = _alphabet.indexOf(normal);
    if (value < 0) return null;
    buffer = (buffer << 5) | value;
    bits += 5;
    if (bits >= 8) {
      out.add((buffer >> (bits - 8)) & 0xff);
      bits -= 8;
      buffer &= (1 << bits) - 1;
    }
  }
  if (bits > 0 && buffer != 0) return null;
  return Uint8List.fromList(out);
}
