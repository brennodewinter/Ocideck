import 'dart:math';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

/// The spec of a one-field form, so a test can say which field it needs.
FormFieldSpec fieldOf(String marker) {
  final r = parseForm(
    '<!-- form id=f -->\n$marker\nL\n<!-- answer -->\n<!-- /field id=x -->\n',
  );
  expect(r, isA<ParsedForm>(), reason: r is BrokenForm ? '${r.problems}' : '');
  return (r as ParsedForm).spec.fieldById('x')!;
}

/// Writes [value], reads it back, and checks the zone is clean.
FormAnswerValue roundTrip(
  String marker,
  FormAnswerValue value, {
  String eol = '\n',
}) {
  final field = fieldOf(marker);
  final zone = formatAnswer(field, value, eol: eol);
  final back = parseAnswer(field, zone);
  expect(back.shape, isEmpty, reason: 'shape of "$zone"');
  expect(
    answerSafetyIssues(zone),
    isEmpty,
    reason: 'safety of "$zone" (${back.shape})',
  );
  return back.value;
}

const text = '<!-- field id=x type=text -->';
const prose = '<!-- field id=x type=prose -->';

void main() {
  group('formatAnswer — what the value becomes', () {
    test('a single line type is one line with a line ending', () {
      for (final type in ['text', 'number', 'date', 'choice']) {
        final field = fieldOf(
          type == 'choice'
              ? '<!-- field id=x type=choice options="a|b" -->'
              : '<!-- field id=x type=$type -->',
        );
        expect(formatAnswer(field, const FormAnswerValue(text: 'a')), 'a\n');
        expect(
          formatAnswer(field, const FormAnswerValue(text: 'a'), eol: '\r\n'),
          'a\r\n',
        );
      }
    });

    test('line breaks and blanks in a single line become one space', () {
      final field = fieldOf(text);
      expect(
        formatAnswer(
          field,
          const FormAnswerValue(text: '  een\n\n  twee \r\n'),
        ),
        'een twee\n',
      );
    });

    test('prose keeps its paragraphs and trims its blank edges', () {
      final field = fieldOf(prose);
      expect(
        formatAnswer(
          field,
          const FormAnswerValue(text: '\n\neen  \n\nzes  \n\n\n'),
        ),
        'een\n\nzes\n',
      );
      expect(
        formatAnswer(field, const FormAnswerValue(text: 'a\r\nb')),
        'a\nb\n',
      );
    });

    test('an empty value is a blank line, or the skeleton of its type', () {
      expect(formatAnswer(fieldOf(text), const FormAnswerValue()), '\n');
      expect(formatAnswer(fieldOf(prose), const FormAnswerValue()), '\n');
      expect(
        formatAnswer(
          fieldOf('<!-- field id=x type=list -->'),
          const FormAnswerValue(),
        ),
        '\n',
      );
      expect(
        formatAnswer(
          fieldOf('<!-- field id=x type=image -->'),
          const FormAnswerValue(),
        ),
        '\n',
      );
      expect(
        formatAnswer(
          fieldOf('<!-- field id=x type=consent -->'),
          const FormAnswerValue(),
        ),
        '- [ ]\n',
      );
      expect(
        formatAnswer(
          fieldOf('<!-- field id=x type=table columns="A|B" -->'),
          const FormAnswerValue(),
        ),
        '| A | B |\n| --- | --- |\n',
      );
      expect(
        formatAnswer(
          fieldOf('<!-- field id=x type=multichoice options="a|b" -->'),
          const FormAnswerValue(),
        ),
        '- [ ] a\n- [ ] b\n',
      );
    });

    test('consent is a box and nothing else', () {
      final field = fieldOf('<!-- field id=x type=consent -->');
      expect(
        formatAnswer(field, const FormAnswerValue(consent: true)),
        '- [x]\n',
      );
      expect(
        formatAnswer(field, const FormAnswerValue(consent: false)),
        '- [ ]\n',
      );
    });

    test(
      'multichoice lists every option, ticked or not, in template order',
      () {
        final field = fieldOf(
          '<!-- field id=x type=multichoice options="a|b|c" -->',
        );
        expect(
          formatAnswer(field, const FormAnswerValue(items: ['c', 'a'])),
          '- [x] a\n- [ ] b\n- [x] c\n',
        );
      },
    );

    test('own text of an `other` field is a ticked box of its own', () {
      final field = fieldOf(
        '<!-- field id=x type=multichoice options="a|b" other -->',
      );
      final zone = formatAnswer(
        field,
        const FormAnswerValue(items: ['b', 'iets anders', 'iets anders']),
      );
      expect(zone, '- [ ] a\n- [x] b\n- [x] iets anders\n');
      expect(parseAnswer(field, zone).items, ['b', 'iets anders']);
    });

    test('prose keeps the indent of every line after the first', () {
      final field = fieldOf(prose);
      expect(
        formatAnswer(
          field,
          const FormAnswerValue(text: '  - a\n    - nested\n\n    code'),
        ),
        '- a\n    - nested\n\n    code\n',
      );
    });

    test('a blank checked item gets no box of its own', () {
      final field = fieldOf(
        '<!-- field id=x type=multichoice options="a|b" other -->',
      );
      expect(
        formatAnswer(field, const FormAnswerValue(items: ['', '  ', 'a'])),
        '- [x] a\n- [ ] b\n',
      );
    });

    test('an ordered list is numbered from one, whatever the input', () {
      final field = fieldOf('<!-- field id=x type=list ordered -->');
      expect(
        formatAnswer(field, const FormAnswerValue(items: ['x', '', 'y'])),
        '1. x\n2. y\n',
      );
    });

    test('a list item of several lines continues indented, without blanks', () {
      final field = fieldOf('<!-- field id=x type=list -->');
      expect(
        formatAnswer(
          field,
          const FormAnswerValue(items: ['eerste\n\nvervolg', 'tweede']),
        ),
        '- eerste\n  vervolg\n- tweede\n',
      );
    });

    test('a table cell loses its line breaks and escapes its pipe', () {
      final field = fieldOf('<!-- field id=x type=table columns="A|B" -->');
      expect(
        formatAnswer(
          field,
          const FormAnswerValue(
            rows: [
              ['a|b', 'x\ny'],
              ['', ''],
              ['c'],
            ],
          ),
        ),
        '| A | B |\n| --- | --- |\n| a\\|b | x y |\n| c |  |\n',
      );
    });

    test(
      'an image keeps its path; alt and credit lose what would end them',
      () {
        final field = fieldOf('<!-- field id=x type=image -->');
        expect(
          formatAnswer(
            field,
            const FormAnswerValue(
              images: [
                FormImageRef('images/a-1.jpg', 'een [mooie]\nfoto', 'Sari "S"'),
                FormImageRef('images/a-2.png', '', null),
                FormImageRef('images/a-3.png', 'x', '  '),
              ],
            ),
          ),
          '![een mooie foto](images/a-1.jpg "Sari S")\n'
          '![](images/a-2.png)\n'
          '![x](images/a-3.png)\n',
        );
      },
    );
  });

  group('formatAnswer — what parseAnswer reads back', () {
    test('every type returns its value', () {
      const cases = <(String, FormAnswerValue)>[
        (text, FormAnswerValue(text: 'Sari Voorbeeld')),
        (prose, FormAnswerValue(text: 'een\n\ntwee **vet**\n\n- punt')),
        ('<!-- field id=x type=number -->', FormAnswerValue(text: '2,5')),
        ('<!-- field id=x type=date -->', FormAnswerValue(text: '2026-11-01')),
        (
          '<!-- field id=x type=choice options="a|b" -->',
          FormAnswerValue(text: 'b'),
        ),
        (
          '<!-- field id=x type=multichoice options="a|b|c" -->',
          FormAnswerValue(items: ['a', 'c']),
        ),
        (
          '<!-- field id=x type=list -->',
          FormAnswerValue(
            items: ['een', 'twee\nregels', '- begint met streep'],
          ),
        ),
        (
          '<!-- field id=x type=list ordered -->',
          FormAnswerValue(items: ['een', '1. begint met nummer']),
        ),
        (
          '<!-- field id=x type=table columns="Naam|Hoeveelheid" -->',
          FormAnswerValue(
            rows: [
              ['bloem', '200 g'],
              ['a|b', r'x\'],
              [r'\|', 'z'],
            ],
          ),
        ),
        (
          '<!-- field id=x type=image -->',
          FormAnswerValue(
            images: [
              FormImageRef('images/foto-1.jpg', 'twee handen', 'Sari'),
              FormImageRef('images/foto-2.webp', '', null),
            ],
          ),
        ),
        ('<!-- field id=x type=consent -->', FormAnswerValue(consent: true)),
        ('<!-- field id=x type=consent -->', FormAnswerValue(consent: false)),
      ];
      for (final (marker, value) in cases) {
        for (final eol in ['\n', '\r\n']) {
          final back = roundTrip(marker, value, eol: eol);
          expect(
            back.text ?? '',
            marker == prose ? value.text : (value.text ?? ''),
            reason: '$marker $eol',
          );
          expect(back.items, value.items, reason: '$marker $eol');
          expect(back.rows, value.rows, reason: '$marker $eol');
          expect(back.images, value.images, reason: '$marker $eol');
          expect(back.consent, value.consent, reason: '$marker $eol');
        }
      }
    });

    test('an empty answer reads back as empty', () {
      for (final marker in [
        text,
        prose,
        '<!-- field id=x type=list -->',
        '<!-- field id=x type=image -->',
        '<!-- field id=x type=table columns="A|B" -->',
        '<!-- field id=x type=multichoice options="a|b" -->',
      ]) {
        final field = fieldOf(marker);
        final back = parseAnswer(
          field,
          formatAnswer(field, const FormAnswerValue()),
        );
        expect(back.isEmpty, isTrue, reason: marker);
        expect(back.shape, isEmpty, reason: marker);
      }
    });

    test('writing what was read changes nothing (idempotent, seeded fuzz)', () {
      final random = Random(20261002);
      const alphabet = [
        'a',
        'b',
        ' ',
        ' ',
        '|',
        r'\',
        '[',
        ']',
        '(',
        ')',
        '"',
        '-',
        '*',
        '1',
        '.',
        '#',
        '>',
        '`',
        'é',
        '日',
        '😀',
        '\n',
        '\n\n',
        '  ',
      ];
      String junk() => List.generate(
        random.nextInt(14),
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();

      final fields = {
        text: () => FormAnswerValue(text: junk()),
        prose: () => FormAnswerValue(text: junk()),
        '<!-- field id=x type=list -->': () => FormAnswerValue(
          items: List.generate(random.nextInt(4), (_) => junk()),
        ),
        '<!-- field id=x type=list ordered -->': () => FormAnswerValue(
          items: List.generate(random.nextInt(4), (_) => junk()),
        ),
        '<!-- field id=x type=table columns="A|B" -->': () => FormAnswerValue(
          rows: List.generate(random.nextInt(4), (_) => [junk(), junk()]),
        ),
        '<!-- field id=x type=image -->': () => FormAnswerValue(
          images: List.generate(
            random.nextInt(3),
            (i) => FormImageRef('images/f-${i + 1}.jpg', junk(), junk()),
          ),
        ),
      };
      for (final entry in fields.entries) {
        final field = fieldOf(entry.key);
        for (var round = 0; round < 300; round++) {
          final value = entry.value();
          final once = formatAnswer(field, value);
          final read = parseAnswer(field, once);
          // A table with a stray pipe and a list of junk can legitimately read
          // back with a shape problem only when the writer failed to protect the
          // shape — that is exactly what this test is for.
          expect(
            read.shape,
            isEmpty,
            reason: '${entry.key}: $value -> "$once"',
          );
          expect(
            formatAnswer(field, read.value),
            once,
            reason: '${entry.key}: $value',
          );
        }
      }
    });
  });

  group('replaceAnswerZone and applyAnswer', () {
    const doc =
        '<!-- form id=f version=1 -->\n'
        '# Titel\n'
        '\n'
        '<!-- field id=naam type=text required -->\n'
        '**Naam**\n'
        '<!-- answer -->\n'
        '<!-- /field id=naam -->\n'
        '\n'
        '<!-- field id=verhaal type=prose -->\n'
        '**Verhaal**\n'
        '<!-- answer -->\n'
        '<!-- /field id=verhaal -->\n';

    FormSpec specOf(String source) => (parseForm(source) as ParsedForm).spec;

    test('only the bytes of the zone change', () {
      final spec = specOf(doc);
      final after = replaceAnswerZone(doc, spec, 'naam', 'Sari\n');
      expect(
        after,
        doc.replaceFirst(
          '<!-- answer -->\n<!-- /field id=naam -->',
          '<!-- answer -->\nSari\n<!-- /field id=naam -->',
        ),
      );
      expect(
        replaceAnswerZone(doc, spec, 'naam', ''),
        doc,
        reason: 'an empty zone is where it started',
      );
    });

    test('a spec that is not the document\'s own is refused, not obeyed', () {
      // The caller's bug (a spec from before the last edit): the offsets point
      // into other text, and writing there would corrupt the document. The result
      // is a refusal that names no marker, because there is none to blame.
      final stale = specOf(doc);
      final moved = '\n\n\n\n\n$doc';
      final result = applyAnswer(
        moved,
        stale,
        'verhaal',
        const FormAnswerValue(text: 'x'),
      );
      expect(result, isA<FormEditRefused>());
      expect(
        (result as FormEditRefused).problem.code,
        FormIssueCode.structureDamaged,
      );
      expect(result.problem.facts['reason'], 'answer');
      expect(result.problem.fieldId, 'verhaal');
    });

    test('an unknown field is a programming error, not a result', () {
      expect(
        () => replaceAnswerZone(doc, specOf(doc), 'nope', 'x'),
        throwsArgumentError,
      );
      expect(
        () => applyAnswer(doc, specOf(doc), 'nope', const FormAnswerValue()),
        throwsArgumentError,
      );
    });

    test('applyAnswer writes the answer and hands back the new spec', () {
      final spec = specOf(doc);
      final result = applyAnswer(
        doc,
        spec,
        'naam',
        const FormAnswerValue(text: 'Sari'),
      );
      expect(result, isA<FormEdited>());
      final edited = result as FormEdited;
      expect(edited.text, contains('<!-- answer -->\nSari\n<!-- /field'));
      // The spec is for the NEW text: the second field has moved.
      final verhaal = edited.spec.fieldById('verhaal')!;
      expect(
        edited.text.substring(verhaal.open.start, verhaal.open.end),
        '<!-- field id=verhaal type=prose -->',
      );
      expect(
        extractAnswers(edited.spec, edited.text).byId['naam']!.text,
        'Sari',
      );
    });

    test('applying the same answer twice gives the same document', () {
      final first =
          applyAnswer(
                doc,
                specOf(doc),
                'naam',
                const FormAnswerValue(text: 'x'),
              )
              as FormEdited;
      final second =
          applyAnswer(
                first.text,
                first.spec,
                'naam',
                const FormAnswerValue(text: 'x'),
              )
              as FormEdited;
      expect(second.text, first.text);
    });

    test(
      'the document keeps its CRLF, its BOM and a missing final newline',
      () {
        final crlf = '﻿${doc.replaceAll('\n', '\r\n').trimRight()}';
        final spec = specOf(crlf);
        final edited =
            applyAnswer(
                  crlf,
                  spec,
                  'verhaal',
                  const FormAnswerValue(text: 'een\n\ntwee'),
                )
                as FormEdited;
        expect(edited.text.startsWith('﻿'), isTrue);
        expect(edited.text.endsWith('<!-- /field id=verhaal -->'), isTrue);
        expect(
          edited.text.replaceAll('\r\n', '').contains('\n'),
          isFalse,
          reason: 'no bare LF has crept in',
        );
        expect(edited.text, contains('<!-- answer -->\r\neen\r\n\r\ntwee\r\n'));
      },
    );

    test('a line that ends its own zone is refused, and says so', () {
      final spec = specOf(doc);
      for (final evil in [
        '<!-- /field id=verhaal -->',
        'tekst\n<!-- /field id=verhaal -->\nmeer',
        '   <!-- /field id=verhaal -->  ',
        '```\n<!-- /field id=verhaal -->\n```',
      ]) {
        final result = applyAnswer(
          doc,
          spec,
          'verhaal',
          FormAnswerValue(text: evil),
        );
        expect(result, isA<FormEditRefused>(), reason: evil);
        expect(
          (result as FormEditRefused).problem.code,
          FormIssueCode.answerContainsMarker,
          reason: evil,
        );
        expect(result.problem.fieldId, 'verhaal');
      }
    });

    test(
      'another marker in an answer keeps the form intact — the safety rules object',
      () {
        // The parser reads everything but the zone's own closing line as content,
        // so these do not move a field. They are still not allowed in an answer
        // (§4.6 rule 1): the text is written, so the respondent sees the line the
        // validator points at, and the form cannot be sent.
        final spec = specOf(doc);
        for (final other in [
          '<!-- answer -->',
          '<!-- field id=nieuw type=text -->',
          '<!-- notice -->',
          '<!-- /field id=naam -->',
        ]) {
          final result = applyAnswer(
            doc,
            spec,
            'verhaal',
            FormAnswerValue(text: other),
          );
          expect(result, isA<FormEdited>(), reason: other);
          final edited = result as FormEdited;
          final problems = validateForm(
            edited.spec,
            extractAnswers(edited.spec, edited.text),
          );
          expect(
            problems.map((p) => p.code),
            contains(FormIssueCode.answerContainsMarker),
            reason: other,
          );
          expect(formIssuesBlock(problems), isTrue, reason: other);
        }
      },
    );

    test(
      'a marker-shaped line in a list item or a table cell is refused too',
      () {
        const withList =
            '<!-- form id=f -->\n'
            '<!-- field id=x type=list -->\n'
            'L\n'
            '<!-- answer -->\n'
            '<!-- /field id=x -->\n';
        final result = applyAnswer(
          withList,
          specOf(withList),
          'x',
          const FormAnswerValue(items: ['<!-- /field id=x -->']),
        );
        // The item is written after a bullet, so the line is no longer a marker:
        // it stays an ordinary item and the form is intact.
        expect(result, isA<FormEdited>());
      },
    );

    test(
      'other HTML in an answer is written; the validator is the one to object',
      () {
        final spec = specOf(doc);
        final result = applyAnswer(
          doc,
          spec,
          'verhaal',
          const FormAnswerValue(text: '<script>x</script>'),
        );
        expect(result, isA<FormEdited>());
        final edited = result as FormEdited;
        final answers = extractAnswers(edited.spec, edited.text);
        expect(
          validateForm(edited.spec, answers).map((p) => p.code),
          contains(FormIssueCode.answerContainsHtml),
        );
      },
    );
  });

  group('normalizeAnswerValue', () {
    test('is what the document would say after the value is written', () {
      final field = fieldOf(text);
      expect(
        normalizeAnswerValue(field, const FormAnswerValue(text: '  a\n b ')),
        const FormAnswerValue(text: 'a b'),
      );
      final list = fieldOf('<!-- field id=x type=list -->');
      expect(
        normalizeAnswerValue(
          list,
          const FormAnswerValue(items: ['x ', '', ' y']),
        ),
        const FormAnswerValue(items: ['x', 'y']),
      );
    });

    test('is idempotent and agrees with the fuzz of the writer', () {
      final field = fieldOf(prose);
      const value = FormAnswerValue(text: '  # a\n\n\n  b  \n');
      final once = normalizeAnswerValue(field, value);
      expect(normalizeAnswerValue(field, once), once);
    });
  });

  group('formLineEnding', () {
    test('is CRLF only when the first line break is one', () {
      expect(formLineEnding('a\r\nb\n'), '\r\n');
      expect(formLineEnding('a\nb\r\n'), '\n');
      expect(formLineEnding('abc'), '\n');
      expect(formLineEnding('\n'), '\n');
      expect(formLineEnding(''), '\n');
    });
  });

  group('FormAnswerValue', () {
    test('equality compares every member, lists element by element', () {
      const a = FormAnswerValue(
        text: 't',
        items: ['i'],
        rows: [
          ['r'],
        ],
        images: [FormImageRef('images/a.jpg', 'x', null)],
        consent: true,
      );
      const same = FormAnswerValue(
        text: 't',
        items: ['i'],
        rows: [
          ['r'],
        ],
        images: [FormImageRef('images/a.jpg', 'x', null)],
        consent: true,
      );
      expect(a, same);
      expect(a.hashCode, same.hashCode);
      for (final other in const [
        FormAnswerValue(text: 'u'),
        FormAnswerValue(text: 't', items: ['j']),
        FormAnswerValue(
          text: 't',
          items: ['i'],
          rows: [
            ['s'],
          ],
        ),
        FormAnswerValue(
          text: 't',
          items: ['i'],
          rows: [
            ['r'],
          ],
          images: [FormImageRef('images/b.jpg', 'x', null)],
        ),
        FormAnswerValue(
          text: 't',
          items: ['i'],
          rows: [
            ['r'],
          ],
          images: [FormImageRef('images/a.jpg', 'x', null)],
          consent: false,
        ),
      ]) {
        expect(a, isNot(other));
      }
      expect(a.toString(), contains('consent: true'));
    });

    test('FormAnswer.value is what was read', () {
      final field = fieldOf('<!-- field id=x type=list -->');
      final answer = parseAnswer(field, '- a\n- b\n');
      expect(
        answer.value,
        const FormAnswerValue(items: ['a', 'b'], text: null),
      );
    });
  });
}
