/// The counters the fill view shows next to a field (FORM_INTAKE.md §8): how many
/// words, characters, items, choices, rows or images the answer has *now*, against
/// the limits the field's rules set.
///
/// The counts are the same numbers the validator judges by — [countFormWords] and
/// [countFormChars] for text, the number of entries for the structured types — so
/// "412 / 300" on screen and `too-many-words` in the validator can never disagree.
/// A field with no limit for a quantity has no counter for it: a counter nobody
/// asked for is noise.
library;

import 'form_answers.dart';
import 'form_rule_values.dart';
import 'form_spec.dart';
import 'form_words.dart';

/// What a [FormCount] counts.
enum FormCountUnit { words, chars, items, choices, rows, images }

/// One counter: [actual] against the optional [min] and [max].
class FormCount {
  const FormCount(this.unit, this.actual, {this.min, this.max});

  final FormCountUnit unit;
  final int actual;
  final int? min;
  final int? max;

  /// Whether [actual] is within the limits (an open end never fails).
  bool get met =>
      (min == null || actual >= min!) && (max == null || actual <= max!);

  @override
  bool operator ==(Object other) =>
      other is FormCount &&
      other.unit == unit &&
      other.actual == actual &&
      other.min == min &&
      other.max == max;

  @override
  int get hashCode => Object.hash(unit, actual, min, max);

  @override
  String toString() => 'FormCount($unit $actual, min: $min, max: $max)';
}

/// The counters of [field] for [value], in the order they are shown. Empty when
/// the field has no limit worth counting against.
List<FormCount> formCounts(FormFieldSpec field, FormAnswerValue value) {
  FormCount? ranged(FormCountUnit unit, FormRange? range, int actual) =>
      range == null
      ? null
      : FormCount(unit, actual, min: range.min, max: range.max);

  FormCount? chars() {
    final min = field.intRule('min-chars');
    final max = field.intRule('max-chars');
    if (min == null && max == null) return null;
    return FormCount(
      FormCountUnit.chars,
      countFormChars(value.text ?? ''),
      min: min,
      max: max,
    );
  }

  final counts = switch (field.type) {
    'text' => [chars()],
    'prose' => [
      ranged(
        FormCountUnit.words,
        field.range('words'),
        countFormWords(value.text ?? ''),
      ),
      chars(),
    ],
    'list' => [
      ranged(FormCountUnit.items, field.range('items'), value.items.length),
    ],
    'multichoice' => [
      ranged(FormCountUnit.choices, field.range('count'), value.items.length),
    ],
    'table' => [
      ranged(FormCountUnit.rows, field.range('rows'), value.rows.length),
    ],
    'image' => [
      ranged(FormCountUnit.images, field.range('count'), value.images.length),
    ],
    _ => <FormCount?>[],
  };
  return [for (final count in counts) ?count];
}
