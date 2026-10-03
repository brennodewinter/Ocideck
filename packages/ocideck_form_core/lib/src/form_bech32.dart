/// Bech32 (BIP-173), the text form of an age key: `age1…` for a recipient and
/// `AGE-SECRET-KEY-1…` for an identity (FORM_INTAKE.md §5.9).
///
/// It exists here for one reason: the **recovery key** of an organiser (`form_recovery_key.dart`)
/// carries the 32-byte secret of the age identity, not the 74-character text of it, and that
/// needs the text turned into the bytes and back. The age library keeps its own bech32 private,
/// and this is not a cryptographic primitive — it is a checksummed alphabet — so it can live in
/// a file that does not import one.
///
/// What is implemented is BIP-173 as it is written: lower case or upper case but never mixed,
/// an overall length of at most 90, a human-readable part of printable ASCII, the last `1` as
/// the separator, the six-character checksum with constant 1. Converting back to bytes is
/// strict: what is left over after the last whole byte must be fewer than five bits and zero.
library;

import 'dart:typed_data';

const String _charset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const List<int> _generator = [
  0x3b6a57b2,
  0x26508e6d,
  0x1ea119fa,
  0x3d4233dd,
  0x2a1462b3,
];

/// The human-readable part of an age identity, lower case as checksummed.
const String kAgeIdentityHrp = 'age-secret-key-';

/// The longest bech32 text BIP-173 allows.
const int kBech32MaxLength = 90;

int _polymod(List<int> values) {
  var chk = 1;
  for (final v in values) {
    final top = chk >> 25;
    chk = ((chk & 0x1ffffff) << 5) ^ v;
    for (var i = 0; i < 5; i++) {
      if ((top >> i) & 1 == 1) chk ^= _generator[i];
    }
  }
  return chk;
}

List<int> _hrpExpand(String hrp) => [
  for (final c in hrp.codeUnits) c >> 5,
  0,
  for (final c in hrp.codeUnits) c & 31,
];

/// The groups of [from] bits of [data] as groups of [to] bits, padding the last one with zeros
/// when [pad] is true; `null` if a value is out of range, or — when not padding — the leftover
/// is five bits or more, or not zero.
List<int>? _convert(List<int> data, int from, int to, {required bool pad}) {
  var acc = 0;
  var bits = 0;
  final out = <int>[];
  final max = (1 << to) - 1;
  for (final value in data) {
    if (value < 0 || value >> from != 0) return null;
    acc = (acc << from) | value;
    bits += from;
    while (bits >= to) {
      bits -= to;
      out.add((acc >> bits) & max);
    }
    acc &= (1 << bits) - 1;
  }
  if (pad) {
    if (bits > 0) out.add((acc << (to - bits)) & max);
  } else if (bits >= from || acc != 0) {
    return null;
  }
  return out;
}

/// The bech32 text of [data] under [hrp] (lower case), or `null` if [hrp] is empty or has a
/// character outside printable ASCII, a value of [data] is not a byte, or the result would be
/// longer than [kBech32MaxLength].
String? bech32Encode(String hrp, List<int> data) {
  if (hrp.isEmpty || hrp.codeUnits.any((c) => c < 33 || c > 126)) return null;
  final lower = hrp.toLowerCase();
  final groups = _convert(data, 8, 5, pad: true);
  if (groups == null) return null;
  final checksumInput = [..._hrpExpand(lower), ...groups, 0, 0, 0, 0, 0, 0];
  final mod = _polymod(checksumInput) ^ 1;
  final checksum = [for (var i = 0; i < 6; i++) (mod >> (5 * (5 - i))) & 31];
  final text =
      '${lower}1${[...groups, ...checksum].map((v) => _charset[v]).join()}';
  return text.length > kBech32MaxLength ? null : text;
}

/// The human-readable part and the bytes of the bech32 [text], or `null` if it is not valid
/// bech32 whose data is a whole number of bytes. Upper case is read as lower case; mixed
/// case is refused.
({String hrp, Uint8List data})? bech32Decode(String text) {
  if (text.length > kBech32MaxLength) return null;
  if (text.codeUnits.any((c) => c < 33 || c > 126)) return null;
  final lower = text.toLowerCase();
  if (text != lower && text != text.toUpperCase()) return null;
  final separator = lower.lastIndexOf('1');
  if (separator < 1 || separator + 7 > lower.length) return null;
  final hrp = lower.substring(0, separator);
  final values = <int>[];
  for (final c in lower.substring(separator + 1).split('')) {
    final value = _charset.indexOf(c);
    if (value < 0) return null;
    values.add(value);
  }
  if (_polymod([..._hrpExpand(hrp), ...values]) != 1) return null;
  final bytes = _convert(
    values.sublist(0, values.length - 6),
    5,
    8,
    pad: false,
  );
  if (bytes == null) return null;
  return (hrp: hrp, data: Uint8List.fromList(bytes));
}

/// The 32-byte secret of an `AGE-SECRET-KEY-1…` identity in its canonical (upper case) form,
/// or `null`.
Uint8List? ageIdentityScalar(String identity) {
  if (identity != identity.toUpperCase()) return null;
  final decoded = bech32Decode(identity);
  if (decoded == null ||
      decoded.hrp != kAgeIdentityHrp ||
      decoded.data.length != 32) {
    return null;
  }
  return decoded.data;
}

/// The `AGE-SECRET-KEY-1…` identity of a 32-byte [scalar], or `null` if it is not 32 bytes.
String? ageIdentityFromScalar(List<int> scalar) {
  if (scalar.length != 32) return null;
  return bech32Encode(kAgeIdentityHrp, scalar)?.toUpperCase();
}
