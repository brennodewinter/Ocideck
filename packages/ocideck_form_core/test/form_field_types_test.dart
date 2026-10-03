import 'package:ocideck_form_core/src/form_blocks.dart';
import 'package:ocideck_form_core/src/form_field_types.dart';
import 'package:ocideck_form_core/src/form_rule_values.dart';
import 'package:test/test.dart';

/// Reads one attribute the way the parser does, so a test can hand a rule a
/// value without building a whole marker.
FormAttr attr(String key, [String? value]) => FormAttr(key, value);

FormRange parseRange(String s) => parseRuleRange(s)!;

({FormRuleValue? value, String? reason}) read(
  String type,
  String key,
  String? value,
) {
  final spec = kFormFieldTypes[type]!.rule(key)!;
  return interpretRule(spec, attr(key, value));
}

void main() {
  test('the registry holds exactly the ten types of FORM_INTAKE.md §4.5', () {
    expect(kFormFieldTypes.keys.toList(), [
      'text',
      'prose',
      'number',
      'date',
      'choice',
      'multichoice',
      'list',
      'table',
      'image',
      'consent',
    ]);
    for (final e in kFormFieldTypes.entries) {
      expect(e.value.wire, e.key);
    }
  });

  test('there is no scale type and no sensitive flag (owner decision)', () {
    expect(kFormFieldTypes.containsKey('scale'), isFalse);
    for (final d in kFormFieldTypes.values) {
      expect(d.rule('sensitive'), isNull);
    }
  });

  test(
    'rule keys are unique per type, lower-case kebab, and never `required`',
    () {
      for (final d in kFormFieldTypes.values) {
        final keys = d.rules.map((r) => r.key).toList();
        expect(keys.toSet().length, keys.length, reason: d.wire);
        for (final k in keys) {
          expect(
            k,
            matches(RegExp(r'^[a-z][a-z0-9-]*$')),
            reason: '${d.wire}.$k',
          );
          expect(
            k,
            isNot('required'),
            reason: 'required is common to every type',
          );
          expect(
            k,
            isNot(anyOf('id', 'type')),
            reason: 'reserved by the marker',
          );
        }
      }
    },
  );

  group('rule kinds', () {
    test('a flag takes no value', () {
      expect(read('choice', 'other', null).value, isA<FlagRule>());
      expect(read('choice', 'other', 'yes').reason, 'flag-takes-no-value');
    });

    test('a value rule needs a value', () {
      expect(read('prose', 'words', null).reason, 'value-required');
      expect(read('text', 'max-chars', null).reason, 'value-required');
    });

    test('count is a non-negative integer', () {
      expect((read('text', 'min-chars', '0').value as IntRule).value, 0);
      expect(read('text', 'min-chars', '-1').reason, 'not-an-integer');
      expect(read('text', 'min-chars', '1.5').reason, 'not-an-integer');
    });

    test('a positive integer refuses zero', () {
      expect((read('text', 'max-chars', '80').value as IntRule).value, 80);
      expect(read('text', 'max-chars', '0').reason, 'not-a-positive-integer');
      expect(read('image', 'min-width', '0').reason, 'not-a-positive-integer');
      expect(
        read('image', 'max-bytes', 'big').reason,
        'not-a-positive-integer',
      );
    });

    test('a range goes through the §4.7 grammar', () {
      final ok = read('prose', 'words', '150..300').value as RangeRule;
      expect((ok.value.min, ok.value.max), (150, 300));
      expect(read('prose', 'words', '150-300').reason, 'bad-range');
      expect(read('prose', 'words', '300..150').reason, 'bad-range');
    });

    test('number and date rules are checked as text', () {
      expect((read('number', 'min', '2,5').value as TextRule).value, '2,5');
      expect(read('number', 'min', '0x10').reason, 'bad-number');
      expect(read('number', 'max', '1e3').reason, 'bad-number');
      expect(
        (read('date', 'min', '2026-11-01').value as TextRule).value,
        '2026-11-01',
      );
      expect(read('date', 'max', '2026-02-30').reason, 'bad-date');
    });

    test(
      'a list splits on the pipe and refuses empty items and duplicates',
      () {
        final ok = read('choice', 'options', 'A|B|C').value as ListRule;
        expect(ok.items, ['A', 'B', 'C']);
        expect(read('choice', 'options', 'A||C').reason, 'empty-item');
        expect(read('choice', 'options', 'A|B|A').reason, 'duplicate-item');
      },
    );

    test('a single-valued enum names the allowed values', () {
      expect(
        (read('text', 'pattern', 'email').value as TextRule).value,
        'email',
      );
      expect(read('text', 'pattern', '.*').reason, 'unknown-value');
      expect(read('text', 'pattern', 'EMAIL').reason, 'unknown-value');
    });

    test('a comma list of enum values must be non-empty, known and unique', () {
      final ok = read('image', 'formats', 'jpg,heic').value as ListRule;
      expect(ok.items, ['jpg', 'heic']);
      expect(read('image', 'formats', 'jpg,gif').reason, 'unknown-value');
      expect(read('image', 'formats', 'jpg,jpg').reason, 'duplicate-item');
      expect(read('image', 'formats', 'jpg,,png').reason, 'empty-item');
    });
  });

  group('cross checks', () {
    List<(String, String)> check(
      String type,
      Map<String, FormRuleValue> rules,
    ) => kFormFieldTypes[type]!.crossChecks(rules);

    test('min-chars may not exceed max-chars', () {
      expect(
        check('text', {'min-chars': IntRule(5), 'max-chars': IntRule(5)}),
        isEmpty,
      );
      expect(
        check('text', {'min-chars': IntRule(6), 'max-chars': IntRule(5)}),
        [('min-chars', 'exceeds-max-chars')],
      );
      expect(check('text', {'min-chars': IntRule(6)}), isEmpty);
    });

    test('number: min <= max by value, and step must be positive', () {
      expect(
        check('number', {'min': TextRule('2'), 'max': TextRule('10')}),
        isEmpty,
      );
      expect(check('number', {'min': TextRule('10'), 'max': TextRule('2')}), [
        ('min', 'exceeds-max'),
      ]);
      expect(check('number', {'step': TextRule('0')}), [
        ('step', 'not-positive'),
      ]);
      expect(check('number', {'step': TextRule('-1')}), [
        ('step', 'not-positive'),
      ]);
      expect(check('number', {'step': TextRule('0,5')}), isEmpty);
    });

    test('date: min <= max', () {
      expect(
        check('date', {
          'min': TextRule('2027-01-01'),
          'max': TextRule('2026-01-01'),
        }),
        [('min', 'exceeds-max')],
      );
      expect(
        check('date', {
          'min': TextRule('2026-01-01'),
          'max': TextRule('2026-01-01'),
        }),
        isEmpty,
      );
    });

    test('multichoice: count cannot demand more than the options offer', () {
      final opts = ListRule(['a', 'b']);
      final c3 = RangeRule(parseRange('3..'));
      expect(check('multichoice', {'options': opts, 'count': c3}), [
        ('count', 'exceeds-options'),
      ]);
      expect(
        check('multichoice', {
          'options': opts,
          'count': c3,
          'other': FlagRule(),
        }),
        isEmpty,
        reason: 'with `other` the respondent can add their own',
      );
      expect(
        check('multichoice', {
          'options': opts,
          'count': RangeRule(parseRange('..3')),
        }),
        isEmpty,
        reason: 'an upper bound above the options is harmless',
      );
    });

    test('image: strict only means something next to min-width', () {
      expect(check('image', {'strict': FlagRule()}), [
        ('strict', 'requires-min-width'),
      ]);
      expect(
        check('image', {'strict': FlagRule(), 'min-width': IntRule(2000)}),
        isEmpty,
      );
    });
  });

  test('required rules are named (options, columns)', () {
    expect(
      kFormFieldTypes['choice']!.rules
          .where((r) => r.required)
          .map((r) => r.key),
      ['options'],
    );
    expect(
      kFormFieldTypes['multichoice']!.rules
          .where((r) => r.required)
          .map((r) => r.key),
      ['options'],
    );
    expect(
      kFormFieldTypes['table']!.rules
          .where((r) => r.required)
          .map((r) => r.key),
      ['columns'],
    );
    for (final t in [
      'text',
      'prose',
      'number',
      'date',
      'list',
      'image',
      'consent',
    ]) {
      expect(
        kFormFieldTypes[t]!.rules.where((r) => r.required),
        isEmpty,
        reason: t,
      );
    }
  });
}
