/// Parsing of the *values* a rule can have: integers, inclusive ranges, decimal
/// numbers, calendar dates and lists (FORM_INTAKE.md §4.7). Pure functions over
/// text — no platform number type is ever consulted, because dart2js and the VM
/// disagree about `25.0` and a counter that differs between a respondent's
/// browser and the organiser's desktop is the failure this feature exists to
/// avoid.
library;

/// The largest integer a rule may carry: twelve digits, exact on every platform.
const int _maxIntDigits = 12;

/// The most digits a decimal number may have in total (integer part plus
/// fraction): fifteen are exact in a double.
const int _maxNumberDigits = 15;

final RegExp _digits = RegExp(r'^[0-9]+$');

/// A non-negative integer written as ASCII digits only, or null.
int? parseRuleInt(String s) {
  if (s.isEmpty || s.length > _maxIntDigits || !_digits.hasMatch(s)) {
    return null;
  }
  return int.parse(s);
}

/// An inclusive range with either end optional (`N`, `N..M`, `N..`, `..M`).
class FormRange {
  const FormRange(this.min, this.max);

  /// null means "no lower bound".
  final int? min;

  /// null means "no upper bound".
  final int? max;

  bool contains(int n) =>
      (min == null || n >= min!) && (max == null || n <= max!);

  @override
  String toString() {
    if (min != null && min == max) return '$min';
    return '${min ?? ''}..${max ?? ''}';
  }

  @override
  bool operator ==(Object other) =>
      other is FormRange && other.min == min && other.max == max;

  @override
  int get hashCode => Object.hash(min, max);
}

/// A range in the exact grammar `N | N..M | N.. | ..M`, or null when malformed.
///
/// A malformed range is an **author error that blocks publishing**: reading
/// `150-300` or `150…300` as "no rule" would let a 20-word answer through.
FormRange? parseRuleRange(String s) {
  if (s.isEmpty) return null;
  final dots = s.indexOf('..');
  if (dots < 0) {
    final n = parseRuleInt(s);
    return n == null ? null : FormRange(n, n);
  }
  final left = s.substring(0, dots);
  final right = s.substring(dots + 2);
  if (left.isEmpty && right.isEmpty) return null;
  final min = left.isEmpty ? null : parseRuleInt(left);
  final max = right.isEmpty ? null : parseRuleInt(right);
  if (left.isNotEmpty && min == null) return null;
  if (right.isNotEmpty && max == null) return null;
  if (min != null && max != null && min > max) return null;
  return FormRange(min, max);
}

final RegExp _numberText = RegExp(r'^-?([0-9]+)(?:[.,]([0-9]+))?$');

/// Whether [s] is a decimal number as §4.7 defines it: ASCII digits with one
/// optional `.` or `,` decimal mark and an optional leading `-`; no exponent,
/// no hexadecimal, no blanks, no `+`, and at most fifteen digits in all.
bool isValidNumberText(String s) {
  final m = _numberText.firstMatch(s);
  if (m == null) return false;
  return m.group(1)!.length + (m.group(2)?.length ?? 0) <= _maxNumberDigits;
}

/// Orders two numbers written as valid number text by *value*. Exact — decimals
/// are compared as scaled integers, never through a double.
int compareNumberText(String a, String b) {
  final x = _scaled(a);
  final y = _scaled(b);
  final scale = x.$2 > y.$2 ? x.$2 : y.$2;
  final left = x.$1 * BigInt.from(10).pow(scale - x.$2);
  final right = y.$1 * BigInt.from(10).pow(scale - y.$2);
  return left.compareTo(right);
}

/// Whether `value - base` is a whole multiple of [step], in exact decimal
/// arithmetic: `0,3` is a multiple of `0,1` here, although it is not in doubles.
/// All three must be valid number text and [step] must be positive.
bool isMultipleOfStep(String value, String base, String step) {
  final v = _scaled(value);
  final b = _scaled(base);
  final s = _scaled(step);
  final scale = [v.$2, b.$2, s.$2].reduce((a, c) => a > c ? a : c);
  BigInt up(BigInt n, int from) => n * BigInt.from(10).pow(scale - from);
  final diff = up(v.$1, v.$2) - up(b.$1, b.$2);
  return diff % up(s.$1, s.$2) == BigInt.zero;
}

(BigInt, int) _scaled(String s) {
  final m = _numberText.firstMatch(s)!;
  final negative = s.startsWith('-');
  final fraction = m.group(2) ?? '';
  final value = BigInt.parse('${m.group(1)}$fraction');
  return (negative ? -value : value, fraction.length);
}

final RegExp _dateText = RegExp(r'^([0-9]{4})-([0-9]{2})-([0-9]{2})$');

/// Whether [s] is `YYYY-MM-DD` **and** a real Gregorian calendar date. Neither
/// `DateTime.tryParse` (it accepts `2026-02-30` and `20261101`) nor a regex alone
/// is the definition; this is.
bool isValidCalendarDate(String s) {
  final m = _dateText.firstMatch(s);
  if (m == null) return false;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  if (year < 1 || month < 1 || month > 12 || day < 1) return false;
  return day <= _daysInMonth(year, month);
}

int _daysInMonth(int year, int month) {
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  if (month == 2) {
    final leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
    return leap ? 29 : 28;
  }
  return days[month - 1];
}

/// The result of splitting a list value: [items], or an [error] token
/// (`empty-item`, `duplicate-item`).
typedef RuleListResult = ({List<String>? items, String? error});

/// Splits [s] on [separator], trims every item, and refuses an empty item or a
/// duplicate (compared case-sensitively).
RuleListResult parseRuleList(String s, String separator) {
  final items = <String>[];
  final seen = <String>{};
  for (final raw in s.split(separator)) {
    final item = raw.trim();
    if (item.isEmpty) return (items: null, error: 'empty-item');
    if (!seen.add(item)) return (items: null, error: 'duplicate-item');
    items.add(item);
  }
  return (items: items, error: null);
}
