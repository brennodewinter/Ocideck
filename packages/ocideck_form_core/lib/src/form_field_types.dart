/// The field types and their rules (FORM_INTAKE.md §4.5), as **one descriptor
/// per type** (§4.10).
///
/// A type is not a `switch` scattered over the parser, the validator, the fill
/// view and the compiler — that is the failure class that makes a new
/// field type fall through silently. The descriptor is the one place that says
/// which attributes a type has, what each means, and which combinations are
/// contradictory. Later steps hang answer extraction, validation and writing on
/// the same descriptor; a test asserts every type has all of them.
library;

import 'form_blocks.dart';
import 'form_rule_values.dart';

/// What a rule's value looks like.
enum RuleKind {
  /// A bare key; takes no value.
  flag,

  /// A non-negative integer.
  count,

  /// An integer of at least 1.
  positiveInt,

  /// An inclusive range, `N | N..M | N.. | ..M`.
  range,

  /// A decimal number, kept as text (§4.7).
  number,

  /// A calendar date `YYYY-MM-DD`, kept as text.
  date,

  /// A `|`-separated list of distinct, non-empty items.
  list,

  /// One of a fixed set of words.
  enumOne,

  /// A `,`-separated list drawn from a fixed set of words.
  enumMany,
}

/// The typed value of one rule on one field.
sealed class FormRuleValue {
  const FormRuleValue();
}

/// A present flag (`required`, `ordered`, …).
class FlagRule extends FormRuleValue {
  const FlagRule();
}

class IntRule extends FormRuleValue {
  const IntRule(this.value);
  final int value;
}

class RangeRule extends FormRuleValue {
  const RangeRule(this.value);
  final FormRange value;
}

/// A number or a date as written, or one word of an enum.
class TextRule extends FormRuleValue {
  const TextRule(this.value);
  final String value;
}

class ListRule extends FormRuleValue {
  const ListRule(this.items);
  final List<String> items;
}

/// One attribute a field type understands.
class RuleSpec {
  const RuleSpec(
    this.key,
    this.kind, {
    this.required = false,
    this.values = const [],
  });

  final String key;
  final RuleKind kind;

  /// The author must state it (`options` on a `choice`).
  final bool required;

  /// The allowed words of an [RuleKind.enumOne] / [RuleKind.enumMany].
  final List<String> values;
}

/// A contradiction between two rules of one field, as `(rule, reason)` pairs.
typedef RuleCrossCheck =
    List<(String, String)> Function(Map<String, FormRuleValue> rules);

/// Everything the engine knows about one field type.
class FormFieldTypeDescriptor {
  const FormFieldTypeDescriptor(
    this.wire,
    this.rules, {
    this.crossChecks = _noCrossChecks,
  });

  /// The `type=` word.
  final String wire;

  /// The rules besides `required`, which every type has.
  final List<RuleSpec> rules;

  final RuleCrossCheck crossChecks;

  /// The rule named [key], or null.
  RuleSpec? rule(String key) {
    for (final r in rules) {
      if (r.key == key) return r;
    }
    return null;
  }
}

List<(String, String)> _noCrossChecks(Map<String, FormRuleValue> rules) =>
    const [];

const List<String> _patterns = ['email', 'url', 'phone', 'postcode-nl'];
const List<String> _imageFormats = ['jpg', 'png', 'webp', 'heic'];

IntRule? _int(Map<String, FormRuleValue> r, String k) =>
    r[k] is IntRule ? r[k]! as IntRule : null;

String? _text(Map<String, FormRuleValue> r, String k) =>
    r[k] is TextRule ? (r[k]! as TextRule).value : null;

/// The registry. Order is the order of FORM_INTAKE.md §4.5.
final Map<String, FormFieldTypeDescriptor> kFormFieldTypes = {
  for (final d in <FormFieldTypeDescriptor>[
    FormFieldTypeDescriptor(
      'text',
      const [
        RuleSpec('min-chars', RuleKind.count),
        RuleSpec('max-chars', RuleKind.positiveInt),
        RuleSpec('pattern', RuleKind.enumOne, values: _patterns),
      ],
      crossChecks: (r) {
        final min = _int(r, 'min-chars');
        final max = _int(r, 'max-chars');
        return min != null && max != null && min.value > max.value
            ? [('min-chars', 'exceeds-max-chars')]
            : const [];
      },
    ),
    const FormFieldTypeDescriptor('prose', [
      RuleSpec('words', RuleKind.range),
      RuleSpec('max-chars', RuleKind.positiveInt),
    ]),
    FormFieldTypeDescriptor(
      'number',
      const [
        RuleSpec('min', RuleKind.number),
        RuleSpec('max', RuleKind.number),
        RuleSpec('step', RuleKind.number),
      ],
      crossChecks: (r) {
        final out = <(String, String)>[];
        final min = _text(r, 'min');
        final max = _text(r, 'max');
        final step = _text(r, 'step');
        if (min != null && max != null && compareNumberText(min, max) > 0) {
          out.add(('min', 'exceeds-max'));
        }
        if (step != null && compareNumberText(step, '0') <= 0) {
          out.add(('step', 'not-positive'));
        }
        return out;
      },
    ),
    FormFieldTypeDescriptor(
      'date',
      const [RuleSpec('min', RuleKind.date), RuleSpec('max', RuleKind.date)],
      crossChecks: (r) {
        final min = _text(r, 'min');
        final max = _text(r, 'max');
        // Valid dates compare correctly as plain text (fixed width, big-endian).
        return min != null && max != null && min.compareTo(max) > 0
            ? [('min', 'exceeds-max')]
            : const [];
      },
    ),
    const FormFieldTypeDescriptor('choice', [
      RuleSpec('options', RuleKind.list, required: true),
      RuleSpec('other', RuleKind.flag),
    ]),
    FormFieldTypeDescriptor(
      'multichoice',
      const [
        RuleSpec('options', RuleKind.list, required: true),
        RuleSpec('count', RuleKind.range),
        RuleSpec('other', RuleKind.flag),
      ],
      crossChecks: (r) {
        final options = r['options'];
        final count = r['count'];
        if (options is! ListRule || count is! RangeRule) return const [];
        // With `other` the respondent can add their own, so more than the
        // listed options may legitimately be asked for.
        final min = count.value.min;
        return min != null &&
                min > options.items.length &&
                !r.containsKey('other')
            ? [('count', 'exceeds-options')]
            : const [];
      },
    ),
    const FormFieldTypeDescriptor('list', [
      RuleSpec('items', RuleKind.range),
      RuleSpec('ordered', RuleKind.flag),
      RuleSpec('item-words', RuleKind.range),
    ]),
    const FormFieldTypeDescriptor('table', [
      RuleSpec('columns', RuleKind.list, required: true),
      RuleSpec('rows', RuleKind.range),
    ]),
    FormFieldTypeDescriptor(
      'image',
      const [
        RuleSpec('count', RuleKind.range),
        RuleSpec('min-width', RuleKind.positiveInt),
        RuleSpec('max-bytes', RuleKind.positiveInt),
        RuleSpec('formats', RuleKind.enumMany, values: _imageFormats),
        RuleSpec('alt', RuleKind.flag),
        RuleSpec('credit', RuleKind.flag),
        RuleSpec('faces', RuleKind.range),
        RuleSpec('strict', RuleKind.flag),
      ],
      crossChecks: (r) => r.containsKey('strict') && !r.containsKey('min-width')
          ? [('strict', 'requires-min-width')]
          : const [],
    ),
    const FormFieldTypeDescriptor('consent', []),
  ])
    d.wire: d,
};

/// Reads [attr] as the value [spec] describes.
///
/// Returns the typed [FormRuleValue], or a `reason` token (`value-required`,
/// `flag-takes-no-value`, `not-an-integer`, `not-a-positive-integer`,
/// `bad-range`, `bad-number`, `bad-date`, `empty-item`, `duplicate-item`,
/// `unknown-value`) — never both, never neither.
({FormRuleValue? value, String? reason}) interpretRule(
  RuleSpec spec,
  FormAttr attr,
) {
  ({FormRuleValue? value, String? reason}) fail(String reason) =>
      (value: null, reason: reason);
  ({FormRuleValue? value, String? reason}) ok(FormRuleValue v) =>
      (value: v, reason: null);

  final text = attr.value;
  if (spec.kind == RuleKind.flag) {
    return text == null ? ok(const FlagRule()) : fail('flag-takes-no-value');
  }
  if (text == null) return fail('value-required');

  switch (spec.kind) {
    case RuleKind.flag:
      return fail('flag-takes-no-value'); // handled above
    case RuleKind.count:
      final n = parseRuleInt(text);
      return n == null ? fail('not-an-integer') : ok(IntRule(n));
    case RuleKind.positiveInt:
      final n = parseRuleInt(text);
      return n == null || n < 1
          ? fail('not-a-positive-integer')
          : ok(IntRule(n));
    case RuleKind.range:
      final r = parseRuleRange(text);
      return r == null ? fail('bad-range') : ok(RangeRule(r));
    case RuleKind.number:
      return isValidNumberText(text) ? ok(TextRule(text)) : fail('bad-number');
    case RuleKind.date:
      return isValidCalendarDate(text) ? ok(TextRule(text)) : fail('bad-date');
    case RuleKind.list:
      final list = parseRuleList(text, '|');
      return list.error != null ? fail(list.error!) : ok(ListRule(list.items!));
    case RuleKind.enumOne:
      return spec.values.contains(text)
          ? ok(TextRule(text))
          : fail('unknown-value');
    case RuleKind.enumMany:
      final list = parseRuleList(text, ',');
      if (list.error != null) return fail(list.error!);
      return list.items!.every(spec.values.contains)
          ? ok(ListRule(list.items!))
          : fail('unknown-value');
  }
}
