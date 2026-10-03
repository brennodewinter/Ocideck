/// The canonical JSON of RFC 8785 (JCS), for what the bundle's signature covers
/// (FORM_INTAKE.md §5.1): two writers that disagree on key order or white space must
/// still sign the same bytes.
///
/// **Only the subset the bundle uses**: objects, arrays, strings, booleans, `null` and
/// **integers**. A number with a fraction or an exponent is refused ([FormJcsError]):
/// RFC 8785 defines their text by ECMAScript's number-to-string, which is a second
/// implementation to get wrong for no field that needs it. An integer beyond ±(2⁵³−1) is
/// refused too — a JSON reader in a browser would round it, and then signer and verifier
/// would no longer see the same number.
///
/// What it does, as the RFC says it: object members sorted by the **UTF-16 code units**
/// of their names; no white space; strings escaped with the short forms `\b \t \n \f \r`,
/// `\"` and `\\`, any other character below U+0020 as a lower-case `\u00xx`, and **every
/// other character literally** (so U+007F, U+2028 and an astral character go out as they
/// are).
library;

/// What cannot be canonicalised: a number outside the subset, a key that is not a
/// string, a value of a type JSON does not have.
class FormJcsError implements Exception {
  const FormJcsError(this.message);

  final String message;

  @override
  String toString() => 'FormJcsError: $message';
}

const int _maxSafeInteger = 9007199254740991;

/// The canonical JSON text of [value].
String canonicalJson(Object? value) {
  final out = StringBuffer();
  _write(value, out);
  return out.toString();
}

void _write(Object? value, StringBuffer out) {
  switch (value) {
    case null:
      out.write('null');
    case bool():
      out.write(value ? 'true' : 'false');
    case int():
      if (value > _maxSafeInteger || value < -_maxSafeInteger) {
        throw const FormJcsError('an integer beyond 2^53-1 is not portable');
      }
      out.write(value.toString());
    case double():
      throw const FormJcsError(
        'a number with a fraction is outside the subset',
      );
    case String():
      _writeString(value, out);
    case List():
      out.write('[');
      for (var i = 0; i < value.length; i++) {
        if (i > 0) out.write(',');
        _write(value[i], out);
      }
      out.write(']');
    case Map():
      final keys = <String>[];
      for (final key in value.keys) {
        if (key is! String) throw const FormJcsError('a key is not a string');
        keys.add(key);
      }
      // Dart compares strings by UTF-16 code unit, which is what the RFC asks for.
      keys.sort();
      out.write('{');
      for (var i = 0; i < keys.length; i++) {
        if (i > 0) out.write(',');
        _writeString(keys[i], out);
        out.write(':');
        _write(value[keys[i]], out);
      }
      out.write('}');
    default:
      throw FormJcsError('${value.runtimeType} is not JSON');
  }
}

bool _isHigh(int unit) => unit >= 0xd800 && unit <= 0xdbff;

bool _isLow(int unit) => unit >= 0xdc00 && unit <= 0xdfff;

void _writeString(String value, StringBuffer out) {
  out.write('"');
  final units = value.codeUnits;
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    // I-JSON (RFC 7493), which RFC 8785 requires: no lone surrogate, which has no UTF-8.
    final high = _isHigh(unit);
    final low = _isLow(unit);
    if (high && !(i + 1 < units.length && _isLow(units[i + 1]))) {
      throw const FormJcsError('a lone surrogate is not valid in I-JSON');
    }
    if (low && !(i > 0 && _isHigh(units[i - 1]))) {
      throw const FormJcsError('a lone surrogate is not valid in I-JSON');
    }
    switch (unit) {
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      case 0x08:
        out.write(r'\b');
      case 0x09:
        out.write(r'\t');
      case 0x0a:
        out.write(r'\n');
      case 0x0c:
        out.write(r'\f');
      case 0x0d:
        out.write(r'\r');
      default:
        if (unit < 0x20) {
          out.write('\\u${unit.toRadixString(16).padLeft(4, '0')}');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
}
