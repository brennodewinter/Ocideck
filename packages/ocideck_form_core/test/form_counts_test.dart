import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

FormFieldSpec fieldOf(String marker) {
  final r = parseForm(
    '<!-- form id=f -->\n$marker\nL\n<!-- answer -->\n<!-- /field id=x -->\n',
  );
  expect(r, isA<ParsedForm>(), reason: r is BrokenForm ? '${r.problems}' : '');
  return (r as ParsedForm).spec.fieldById('x')!;
}

void main() {
  group('formCounts', () {
    test('prose counts words against its range, and characters if limited', () {
      final field = fieldOf(
        '<!-- field id=x type=prose words=150..300 max-chars=2000 -->',
      );
      expect(formCounts(field, const FormAnswerValue(text: 'een twee drie')), [
        const FormCount(FormCountUnit.words, 3, min: 150, max: 300),
        const FormCount(FormCountUnit.chars, 13, max: 2000),
      ]);
    });

    test('the numbers are the ones the validator judges by', () {
      final field = fieldOf('<!-- field id=x type=prose words=..3 -->');
      const text = '1. één twee [x] drie vier';
      final count = formCounts(field, const FormAnswerValue(text: text)).single;
      expect(count.actual, countFormWords(text));
      expect(count.met, isFalse);
    });

    test('a field without a limit has no counter', () {
      expect(
        formCounts(
          fieldOf('<!-- field id=x type=prose -->'),
          const FormAnswerValue(text: 'abc'),
        ),
        isEmpty,
      );
      expect(
        formCounts(
          fieldOf('<!-- field id=x type=text -->'),
          const FormAnswerValue(text: 'abc'),
        ),
        isEmpty,
      );
      expect(
        formCounts(
          fieldOf('<!-- field id=x type=consent -->'),
          const FormAnswerValue(consent: true),
        ),
        isEmpty,
      );
    });

    test('text counts characters when it has a limit on them', () {
      final field = fieldOf(
        '<!-- field id=x type=text min-chars=2 max-chars=5 -->',
      );
      expect(
        formCounts(field, const FormAnswerValue(text: 'abc')).single,
        const FormCount(FormCountUnit.chars, 3, min: 2, max: 5),
      );
    });

    test('lists, choices, tables and images count their entries', () {
      expect(
        formCounts(
          fieldOf('<!-- field id=x type=list items=3..6 -->'),
          const FormAnswerValue(items: ['a', 'b']),
        ),
        [const FormCount(FormCountUnit.items, 2, min: 3, max: 6)],
      );
      expect(
        formCounts(
          fieldOf(
            '<!-- field id=x type=multichoice options="a|b|c" count=1..2 -->',
          ),
          const FormAnswerValue(items: ['a']),
        ),
        [const FormCount(FormCountUnit.choices, 1, min: 1, max: 2)],
      );
      expect(
        formCounts(
          fieldOf('<!-- field id=x type=table columns="A|B" rows=1.. -->'),
          const FormAnswerValue(
            rows: [
              ['1', '2'],
            ],
          ),
        ),
        [const FormCount(FormCountUnit.rows, 1, min: 1)],
      );
      expect(
        formCounts(
          fieldOf('<!-- field id=x type=image count=3..6 -->'),
          const FormAnswerValue(
            images: [FormImageRef('images/a-1.jpg', '', null)],
          ),
        ),
        [const FormCount(FormCountUnit.images, 1, min: 3, max: 6)],
      );
    });
  });

  group('FormCount', () {
    test('met honours open ends and both bounds', () {
      expect(const FormCount(FormCountUnit.words, 5).met, isTrue);
      expect(const FormCount(FormCountUnit.words, 5, min: 5).met, isTrue);
      expect(const FormCount(FormCountUnit.words, 4, min: 5).met, isFalse);
      expect(const FormCount(FormCountUnit.words, 5, max: 5).met, isTrue);
      expect(const FormCount(FormCountUnit.words, 6, max: 5).met, isFalse);
      expect(
        const FormCount(FormCountUnit.words, 5, min: 1, max: 9).met,
        isTrue,
      );
    });

    test('equality and hashing use every member', () {
      const a = FormCount(FormCountUnit.words, 5, min: 1, max: 9);
      expect(a, const FormCount(FormCountUnit.words, 5, min: 1, max: 9));
      expect(
        a.hashCode,
        const FormCount(FormCountUnit.words, 5, min: 1, max: 9).hashCode,
      );
      for (final other in const [
        FormCount(FormCountUnit.chars, 5, min: 1, max: 9),
        FormCount(FormCountUnit.words, 6, min: 1, max: 9),
        FormCount(FormCountUnit.words, 5, min: 2, max: 9),
        FormCount(FormCountUnit.words, 5, min: 1, max: 8),
      ]) {
        expect(a, isNot(other));
      }
      expect(a.toString(), contains('words'));
    });
  });
}
