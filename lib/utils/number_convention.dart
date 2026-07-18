// Reading numbers out of a CSV somebody else wrote, without guessing.
//
// `1,234` is one thousand two hundred thirty-four in Ede and one-point-two-
// three-four in Edinburgh. A single value cannot say which. A *file* usually
// can, and this is where that is worked out.
//
// The rule throughout: **deduce or refuse, never guess.** Everything below is
// evidence that settles the question outright. What no evidence settles is
// handed back as [DecimalConventionScan.undecided] for a human to answer — it
// is not resolved by leaning toward whatever is more common.

/// Which mark separates the whole part of a number from its fraction.
enum DecimalConvention {
  /// `1,234.56` — the dot is the decimal mark, the comma groups thousands.
  dot,

  /// `1.234,56` — the comma is the decimal mark, the dot groups thousands.
  comma,
}

/// What a set of raw values proves about how their numbers are written.
class DecimalConventionScan {
  /// The convention the values themselves establish, or null when nothing in
  /// them settles it (including when two values contradict each other).
  final DecimalConvention? decided;

  /// Values that read differently under each convention and that [decided]
  /// does not resolve. Only comma-bearing values land here — see
  /// [scanDecimalConvention] for why a lone dot is never in doubt.
  final List<String> undecided;

  const DecimalConventionScan({required this.decided, required this.undecided});
}

final RegExp _numeric = RegExp(r'^[+-]?[\d.,]*\d[\d.,]*$');

/// True for a value shaped like a number written with grouping marks. Anything
/// else (`12%`, `€ 1000`, `oops`) carries no evidence and is left alone.
bool _looksNumeric(String value) => _numeric.hasMatch(value);

/// What one value proves about the role of [mark] within it, given that the
/// other grouping character is [other]. Returns null when it proves nothing.
bool? _markIsDecimal(String value, String mark, String other) {
  final positions = <int>[];
  for (var i = 0; i < value.length; i++) {
    if (value[i] == mark) positions.add(i);
  }
  if (positions.isEmpty) return null;

  // Both marks present: whichever comes last is the decimal one. True in every
  // convention in use, and the strongest evidence there is.
  final otherAt = value.lastIndexOf(other);
  if (otherAt != -1) return positions.last > otherAt;

  // A decimal mark cannot occur twice; a grouping mark routinely does.
  if (positions.length > 1) return false;

  final after = value.substring(positions.first + 1);
  if (after.isEmpty || !RegExp(r'^\d+$').hasMatch(after)) return null;

  // A group of exactly three digits is what thousands-grouping produces, so it
  // proves nothing on its own. Any other length cannot be a group, so the mark
  // must be decimal.
  return after.length == 3 ? null : true;
}

/// Work out how the numbers in [values] are written.
///
/// Evidence is gathered across the whole set, because that is what makes the
/// question answerable: `1,234` alone says nothing, but `1,234` next to `10,5`
/// says the comma is a decimal mark, and next to `10.5` says it groups
/// thousands. Contradictory files stay [DecimalConventionScan.decided] null.
///
/// Only comma ambiguity is ever reported as [DecimalConventionScan.undecided].
/// A dot followed by three digits is equally ambiguous in principle, but the
/// app writes its own CSV with a dot decimal mark, so treating `1.234` as
/// anything else would make it ask a question about every file it produced
/// itself.
DecimalConventionScan scanDecimalConvention(Iterable<String> values) {
  final candidates = [
    for (final v in values)
      if (_looksNumeric(v.trim())) v.trim(),
  ];

  var commaDecimal = false;
  var dotDecimal = false;
  for (final value in candidates) {
    final comma = _markIsDecimal(value, ',', '.');
    final dot = _markIsDecimal(value, '.', ',');
    if (comma == true || dot == false) commaDecimal = true;
    if (comma == false || dot == true) dotDecimal = true;
  }

  final decided = commaDecimal == dotDecimal
      ? null // nothing said, or the file contradicts itself
      : (commaDecimal ? DecimalConvention.comma : DecimalConvention.dot);

  return DecimalConventionScan(
    decided: decided,
    undecided: decided != null
        ? const []
        : [
            for (final value in candidates)
              if (value.contains(',') &&
                  _markIsDecimal(value, ',', '.') == null)
                value,
          ],
  );
}

/// Read [raw] as a number under [convention], or null when it is not one.
///
/// Values that are not shaped like a grouped number fall through to Dart's own
/// parsing, so exponent forms and the like keep working.
double? parseNumberUnder(String raw, DecimalConvention convention) {
  final value = raw.trim();
  if (!_looksNumeric(value)) return double.tryParse(value);
  final plain = convention == DecimalConvention.comma
      ? value.replaceAll('.', '').replaceAll(',', '.')
      : value.replaceAll(',', '');
  return double.tryParse(plain);
}
