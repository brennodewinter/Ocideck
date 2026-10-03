/// Base32 as the engine writes keys, fingerprints and signatures (FORM_INTAKE.md §5.1):
/// RFC 4648, **lower case, no padding**, the same alphabet a submission or form id uses
/// (`[a-z2-7]`). One alphabet means a fingerprint read aloud, typed into a link and pasted
/// back is the same string, and a string in a URL fragment needs no escaping.
///
/// Decoding is **canonical**: the length must be one a byte string can have, the leftover
/// bits must be zero, and nothing outside `[a-z2-7]` is accepted — not upper case, not
/// padding, not a blank. Two different texts for one byte string would be two different
/// fingerprints for one key.
library;

import 'dart:typed_data';

const String _alphabet = 'abcdefghijklmnopqrstuvwxyz234567';

/// [bytes] as lower-case base32 without padding.
String base32Encode(List<int> bytes) {
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
    // The read above masks to five bits, so this is not needed for the value on the VM; it keeps
    // the buffer small, which dart2js needs (its shifts are 32-bit).
    buffer &= (1 << bits) - 1;
  }
  if (bits > 0) out.write(_alphabet[(buffer << (5 - bits)) & 31]);
  return out.toString();
}

/// The bytes of [text], or `null` if it is not canonical lower-case base32.
Uint8List? base32Decode(String text) {
  // A byte string of n bytes takes ceil(8n / 5) characters, so the length mod 8 is one of
  // 0, 2, 4, 5 or 7; the others cannot be the end of any byte string.
  if (const {1, 3, 6}.contains(text.length % 8)) return null;
  final out = <int>[];
  var buffer = 0;
  var bits = 0;
  for (final unit in text.codeUnits) {
    final value = _alphabet.indexOf(String.fromCharCode(unit));
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
