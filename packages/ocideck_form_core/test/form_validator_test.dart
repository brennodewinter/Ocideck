import 'package:ocideck_form_core/src/form_answers.dart';
import 'package:ocideck_form_core/src/form_issue.dart';
import 'package:ocideck_form_core/src/form_parser.dart';
import 'package:ocideck_form_core/src/form_spec.dart';
import 'package:ocideck_form_core/src/form_validator.dart';
import 'package:test/test.dart';

FormFieldSpec fieldOf(String marker) {
  final r = parseForm(
    '<!-- form id=f -->\n$marker\nL\n<!-- answer -->\n<!-- /field id=x -->\n',
  );
  expect(r, isA<ParsedForm>(), reason: r is BrokenForm ? '${r.problems}' : '');
  return (r as ParsedForm).spec.fieldById('x')!;
}

/// The wire names of the issues for [zone] in a field built from [marker].
List<String> check(
  String marker,
  String zone, {
  Map<String, FormImageFact>? facts,
}) {
  final field = fieldOf(marker);
  final answer = parseAnswer(field, zone, firstLine: 10);
  return [
    for (final i in validateAnswer(field, answer, imageFacts: facts))
      i.code.wireName,
  ];
}

List<FormProblem> issues(
  String marker,
  String zone, {
  Map<String, FormImageFact>? facts,
}) {
  final field = fieldOf(marker);
  return validateAnswer(
    field,
    parseAnswer(field, zone, firstLine: 10),
    imageFacts: facts,
  );
}

String words(int n) => List.filled(n, 'woord').join(' ');

void main() {
  group('required and empty', () {
    test('a required empty field is required-empty, whatever the type', () {
      for (final type in [
        'text',
        'prose',
        'number',
        'date',
        'choice options="A"',
        'multichoice options="A"',
        'list',
        'table columns="A|B"',
        'image',
      ]) {
        expect(check('<!-- field id=x type=$type required -->', ''), [
          'required-empty',
        ], reason: type);
      }
    });

    test('a field that is not required may be empty: no rule is applied', () {
      for (final marker in [
        '<!-- field id=x type=text min-chars=5 -->',
        '<!-- field id=x type=prose words=150..300 -->',
        '<!-- field id=x type=number min=1 -->',
        '<!-- field id=x type=list items=3.. -->',
        '<!-- field id=x type=image count=2..5 min-width=2000 -->',
        '<!-- field id=x type=multichoice options="A|B" count=2 -->',
      ]) {
        expect(check(marker, ''), isEmpty, reason: marker);
      }
    });

    test('required-empty points at the line of the empty zone', () {
      expect(
        issues('<!-- field id=x type=text required -->', '').single.line,
        10,
      );
    });

    test('an unchecked multichoice and an empty table count as empty', () {
      expect(
        check(
          '<!-- field id=x type=multichoice options="A" required -->',
          '- [ ] A',
        ),
        ['required-empty'],
      );
      expect(
        check(
          '<!-- field id=x type=table columns="A|B" required -->',
          '| A | B |\n|---|---|\n',
        ),
        ['required-empty'],
      );
    });
  });

  group('text', () {
    const marker = '<!-- field id=x type=text min-chars=3 max-chars=5 -->';

    test('length in characters, inclusive at both ends', () {
      expect(check(marker, 'ab'), ['too-short']);
      expect(check(marker, 'abc'), isEmpty);
      expect(check(marker, 'abcde'), isEmpty);
      expect(check(marker, 'abcdef'), ['too-long']);
    });

    test('characters are graphemes, not code units', () {
      expect(
        check('<!-- field id=x type=text max-chars=4 -->', 'René'),
        isEmpty,
      );
      expect(
        check('<!-- field id=x type=text max-chars=1 -->', '\u{1F336}'),
        isEmpty,
      );
      expect(
        check(
          '<!-- field id=x type=text max-chars=1 -->',
          '\u{1F336}\u{1F336}',
        ),
        ['too-long'],
      );
    });

    test('facts say what was wrong', () {
      final i = issues(marker, 'abcdef').single;
      expect(i.facts, {'min': 3, 'max': 5, 'actual': 6});
      expect(i.fieldId, 'x');
      expect(i.line, 10);
    });

    test('named patterns', () {
      expect(
        check('<!-- field id=x type=text pattern=email -->', 'a@b.nl'),
        isEmpty,
      );
      expect(check('<!-- field id=x type=text pattern=email -->', 'a@b'), [
        'bad-pattern',
      ]);
      expect(
        issues(
          '<!-- field id=x type=text pattern=phone -->',
          'abc',
        ).single.facts['pattern'],
        'phone',
      );
    });

    test('a pattern and a length are both checked', () {
      expect(
        check(
          '<!-- field id=x type=text pattern=email max-chars=3 -->',
          'a@bcd',
        ),
        ['too-long', 'bad-pattern'],
      );
    });
  });

  group('prose', () {
    const marker = '<!-- field id=x type=prose required words=150..300 -->';

    test('words, inclusive at both ends (149 / 150 / 300 / 301)', () {
      expect(check(marker, words(149)), ['too-few-words']);
      expect(check(marker, words(150)), isEmpty);
      expect(check(marker, words(300)), isEmpty);
      expect(check(marker, words(301)), ['too-many-words']);
    });

    test('open-ended ranges', () {
      expect(
        check('<!-- field id=x type=prose words=..100 -->', words(100)),
        isEmpty,
      );
      expect(check('<!-- field id=x type=prose words=..100 -->', words(101)), [
        'too-many-words',
      ]);
      expect(check('<!-- field id=x type=prose words=5.. -->', words(4)), [
        'too-few-words',
      ]);
      expect(
        check('<!-- field id=x type=prose words=5.. -->', words(5000)),
        isEmpty,
      );
    });

    test(
      'list markers and task boxes are not words (the counter of the vectors)',
      () {
        final zone = '${words(148)}\n1. een\n- [x] twee';
        // 148 + 2 real words = 150, not 153.
        expect(check(marker, zone), isEmpty);
      },
    );

    test('the facts carry the numbers a message needs', () {
      final i = issues(marker, words(132)).single;
      expect(i.facts, {'min': 150, 'max': 300, 'actual': 132});
    });

    test('max-chars applies as well', () {
      expect(
        check('<!-- field id=x type=prose max-chars=10 -->', 'abcdefghijk'),
        ['too-long'],
      );
    });
  });

  group('number', () {
    test('a number must be a number', () {
      for (final bad in ['0x10', '1e3', '2,5,1', 'abc', '1 2']) {
        expect(check('<!-- field id=x type=number -->', bad), [
          'bad-number',
        ], reason: bad);
      }
      for (final ok in ['0', '25', '-3', '2,5', '2.5']) {
        expect(
          check('<!-- field id=x type=number -->', ok),
          isEmpty,
          reason: ok,
        );
      }
    });

    test('min and max, inclusive, compared by value', () {
      const m = '<!-- field id=x type=number min=1 max=10,5 -->';
      expect(check(m, '0,9'), ['number-out-of-range']);
      expect(check(m, '1'), isEmpty);
      expect(check(m, '10.5'), isEmpty);
      expect(check(m, '10,51'), ['number-out-of-range']);
      expect(
        check(m, '9'),
        isEmpty,
        reason: '9 < 10.5 although "9" > "10.5" as text',
      );
    });

    test('step is exact decimal arithmetic, counted from min (or zero)', () {
      expect(check('<!-- field id=x type=number step=0,1 -->', '0,3'), isEmpty);
      expect(check('<!-- field id=x type=number step=0,1 -->', '0,35'), [
        'number-out-of-range',
      ]);
      expect(
        check('<!-- field id=x type=number min=1 step=2 -->', '5'),
        isEmpty,
      );
      expect(check('<!-- field id=x type=number min=1 step=2 -->', '4'), [
        'number-out-of-range',
      ]);
      expect(check('<!-- field id=x type=number step=5 -->', '-10'), isEmpty);
      expect(check('<!-- field id=x type=number step=5 -->', '-12'), [
        'number-out-of-range',
      ]);
      expect(
        issues(
          '<!-- field id=x type=number step=2 -->',
          '3',
        ).single.facts['reason'],
        'step',
      );
    });

    test('a number that is not a number is not also out of range', () {
      expect(check('<!-- field id=x type=number min=1 -->', 'abc'), [
        'bad-number',
      ]);
    });
  });

  group('date', () {
    test('a real calendar date', () {
      for (final bad in ['2026-02-30', '2026-13-01', '20261101', '1-1-2026']) {
        expect(check('<!-- field id=x type=date -->', bad), [
          'bad-date',
        ], reason: bad);
      }
      expect(check('<!-- field id=x type=date -->', '2026-11-01'), isEmpty);
    });

    test('min and max, inclusive', () {
      const m = '<!-- field id=x type=date min=2026-01-01 max=2026-12-31 -->';
      expect(check(m, '2025-12-31'), ['bad-date']);
      expect(check(m, '2026-01-01'), isEmpty);
      expect(check(m, '2026-12-31'), isEmpty);
      expect(check(m, '2027-01-01'), ['bad-date']);
      expect(issues(m, '2027-01-01').single.facts['reason'], 'after-max');
      expect(issues(m, '2025-12-31').single.facts['reason'], 'before-min');
    });
  });

  group('choice', () {
    test('one of the options, exactly', () {
      const m = '<!-- field id=x type=choice options="Quick Fix|Zoet" -->';
      expect(check(m, 'Quick Fix'), isEmpty);
      expect(check(m, 'quick fix'), ['not-an-option']);
      expect(check(m, 'Hartig'), ['not-an-option']);
      expect(issues(m, 'Hartig').single.facts['value'], 'Hartig');
    });

    test('with other, any single line is fine', () {
      expect(
        check(
          '<!-- field id=x type=choice options="A|B" other -->',
          'Iets anders',
        ),
        isEmpty,
      );
    });
  });

  group('multichoice', () {
    const m = '<!-- field id=x type=multichoice options="A|B|C" count=1..2 -->';

    test('the number of checked options, inclusive', () {
      expect(check(m, '- [x] A'), isEmpty);
      expect(check(m, '- [x] A\n- [x] B'), isEmpty);
      expect(check(m, '- [x] A\n- [x] B\n- [x] C'), ['count-out-of-range']);
      expect(issues(m, '- [x] A\n- [x] B\n- [x] C').single.facts, {
        'min': 1,
        'max': 2,
        'actual': 3,
      });
    });

    test('every checked option must be listed, one issue per stray', () {
      expect(check(m, '- [x] A\n- [x] Z'), ['not-an-option']);
      expect(check(m, '- [x] Y\n- [x] Z'), ['not-an-option', 'not-an-option']);
    });

    test('with other, own text is accepted', () {
      expect(
        check(
          '<!-- field id=x type=multichoice options="A" other -->',
          '- [x] A\n- [x] Iets anders',
        ),
        isEmpty,
      );
    });
  });

  group('list', () {
    const m = '<!-- field id=x type=list items=2..3 item-words=..3 -->';

    test('the number of items, inclusive', () {
      expect(check(m, '- een'), ['count-out-of-range']);
      expect(check(m, '- een\n- twee'), isEmpty);
      expect(check(m, '- een\n- twee\n- drie'), isEmpty);
      expect(check(m, '- een\n- twee\n- drie\n- vier'), ['count-out-of-range']);
    });

    test('words per item, naming the item', () {
      final i = issues(m, '- een\n- een twee drie vier');
      expect(i.map((x) => x.code.wireName), ['too-many-words']);
      expect(i.single.facts['item'], 2);
      expect(i.single.facts['actual'], 4);
    });

    test('item-words counts words, not the list marker', () {
      expect(
        check(
          '<!-- field id=x type=list ordered item-words=1..1 -->',
          '1. ui\n2. knoflook',
        ),
        isEmpty,
      );
    });

    test('too few words in an item', () {
      expect(check('<!-- field id=x type=list item-words=2.. -->', '- een'), [
        'too-few-words',
      ]);
    });
  });

  group('table', () {
    const m = '<!-- field id=x type=table columns="A|B" rows=2..3 -->';
    const head = '| A | B |\n|---|---|\n';

    test('the number of rows, inclusive', () {
      expect(check(m, '$head| 1 | 2 |'), ['count-out-of-range']);
      expect(check(m, '$head| 1 | 2 |\n| 3 | 4 |'), isEmpty);
      expect(check(m, '$head| 1 | 2 |\n| 3 | 4 |\n| 5 | 6 |\n| 7 | 8 |'), [
        'count-out-of-range',
      ]);
    });

    test('says that it counted rows', () {
      expect(issues(m, '$head| 1 | 2 |').single.facts['what'], 'rows');
    });
  });

  group('consent', () {
    const m = '<!-- field id=x type=consent required -->';

    test('required: the box must be checked', () {
      expect(check(m, '- [ ]'), ['consent-not-given']);
      expect(check(m, '- [x]'), isEmpty);
    });

    test('not required: an unchecked box is fine', () {
      expect(check('<!-- field id=x type=consent -->', '- [ ]'), isEmpty);
    });

    test('a damaged box is malformed, not "not given" as well', () {
      expect(check(m, 'ja'), ['answer-malformed']);
      expect(check(m, ''), ['answer-malformed']);
    });
  });

  group('images', () {
    const m =
        '<!-- field id=x type=image count=1..2 min-width=2000 max-bytes=1000 alt -->';
    const one = '![portret](images/portret-1.jpg)';

    FormImageFact fact({
      int width = 2400,
      int bytes = 500,
      String format = 'jpg',
    }) => FormImageFact(displayedWidth: width, bytes: bytes, format: format);

    test('without facts nothing is checked, and that is not a pass', () {
      expect(check(m, one), ['image-unchecked']);
      expect(check(m, one, facts: null), ['image-unchecked']);
    });

    test('with good facts it passes', () {
      expect(check(m, one, facts: {'images/portret-1.jpg': fact()}), isEmpty);
    });

    test('a missing fact for one path is unchecked for that path', () {
      final two = '$one\n![gerecht](images/gerecht-1.jpg)';
      final i = issues(m, two, facts: {'images/portret-1.jpg': fact()});
      expect(i.map((x) => x.code.wireName), ['image-unchecked']);
      expect(i.single.facts['path'], 'images/gerecht-1.jpg');
    });

    test('count, inclusive', () {
      final f = {
        for (final n in ['a-1', 'a-2', 'a-3']) 'images/$n.jpg': fact(),
      };
      expect(
        check(m, '![a](images/a-1.jpg)\n![a](images/a-2.jpg)', facts: f),
        isEmpty,
      );
      expect(
        check(
          m,
          '![a](images/a-1.jpg)\n![a](images/a-2.jpg)\n![a](images/a-3.jpg)',
          facts: f,
        ),
        ['count-out-of-range'],
      );
    });

    test('a file that is not there', () {
      expect(
        check(
          m,
          one,
          facts: {'images/portret-1.jpg': const FormImageFact(exists: false)},
        ),
        ['image-missing-file'],
      );
    });

    test(
      'too wide is fine, too narrow is a warning, 2000 exactly is enough',
      () {
        expect(
          check(m, one, facts: {'images/portret-1.jpg': fact(width: 2000)}),
          isEmpty,
        );
        final i = issues(
          m,
          one,
          facts: {'images/portret-1.jpg': fact(width: 1999)},
        );
        expect(i.map((x) => x.code.wireName), ['image-too-small']);
        expect(i.single.severity, FormSeverity.warning);
        expect(i.single.facts, {
          'min': 2000,
          'actual': 1999,
          'path': 'images/portret-1.jpg',
        });
      },
    );

    test('strict makes too narrow an error', () {
      final i = issues(
        '<!-- field id=x type=image min-width=2000 strict -->',
        one,
        facts: {'images/portret-1.jpg': fact(width: 1000)},
      );
      expect(i.single.code, FormIssueCode.imageTooSmall);
      expect(i.single.severity, FormSeverity.error);
    });

    test('max-bytes, inclusive', () {
      expect(
        check(m, one, facts: {'images/portret-1.jpg': fact(bytes: 1000)}),
        isEmpty,
      );
      expect(
        check(m, one, facts: {'images/portret-1.jpg': fact(bytes: 1001)}),
        ['image-too-large'],
      );
    });

    test('the formats rule, by extension', () {
      const png = '<!-- field id=x type=image formats=png -->';
      expect(check(png, one, facts: {'images/portret-1.jpg': fact()}), [
        'image-format',
      ]);
      expect(
        check(
          png,
          '![a](images/a-1.png)',
          facts: {'images/a-1.png': fact(format: 'png')},
        ),
        isEmpty,
      );
    });

    test('a file whose content is not what its name says', () {
      expect(
        check(
          '<!-- field id=x type=image -->',
          one,
          facts: {'images/portret-1.jpg': fact(format: 'png')},
        ),
        ['image-format'],
      );
    });

    test('alt text, when the field asks for it', () {
      expect(
        check(
          m,
          '![](images/portret-1.jpg)',
          facts: {'images/portret-1.jpg': fact()},
        ),
        ['image-missing-alt'],
      );
      expect(
        check(
          '<!-- field id=x type=image -->',
          '![](images/portret-1.jpg)',
          facts: {'images/portret-1.jpg': fact()},
        ),
        isEmpty,
        reason: 'without the alt rule an empty alt is fine',
      );
    });

    test('a credit, when the field asks for it', () {
      const c = '<!-- field id=x type=image credit -->';
      final f = {'images/a-1.jpg': fact()};
      expect(check(c, '![a](images/a-1.jpg)', facts: f), [
        'image-missing-credit',
      ]);
      expect(check(c, '![a](images/a-1.jpg "Foto: Sari")', facts: f), isEmpty);
    });

    test('faces: only a deviation is reported, and only as information', () {
      const fm = '<!-- field id=x type=image faces=1 -->';
      final ok = FormImageFact(
        displayedWidth: 3000,
        bytes: 1,
        format: 'jpg',
        faces: 1,
      );
      final off = FormImageFact(
        displayedWidth: 3000,
        bytes: 1,
        format: 'jpg',
        faces: 3,
      );
      expect(check(fm, one, facts: {'images/portret-1.jpg': ok}), isEmpty);
      final i = issues(fm, one, facts: {'images/portret-1.jpg': off});
      expect(i.single.code, FormIssueCode.imageUnexpectedFaces);
      expect(i.single.severity, FormSeverity.info);
      expect(
        check(
          fm,
          one,
          facts: {
            'images/portret-1.jpg': FormImageFact(
              displayedWidth: 3000,
              bytes: 1,
              format: 'jpg',
            ),
          },
        ),
        isEmpty,
        reason:
            'no face count known (web, or the scan is off): nothing to compare',
      );
    });

    test(
      'a HEIC kept as it is: a warning, not a block, and no width to judge',
      () {
        const hm = '<!-- field id=x type=image min-width=2000 -->';
        final i = issues(
          hm,
          '![a](images/a-1.heic)',
          facts: {
            'images/a-1.heic': const FormImageFact(
              unverified: true,
              bytes: 5000,
            ),
          },
        );
        expect(i.map((x) => x.code.wireName), ['image-heic-unverified']);
        expect(i.single.severity, FormSeverity.warning);
      },
    );

    test('an unverified fact on anything but HEIC is still unchecked', () {
      expect(
        check(
          '<!-- field id=x type=image -->',
          one,
          facts: {
            'images/portret-1.jpg': const FormImageFact(unverified: true),
          },
        ),
        ['image-unchecked'],
      );
    });

    test('a HEIC with no facts at all is unchecked', () {
      expect(check('<!-- field id=x type=image -->', '![a](images/a-1.heic)'), [
        'image-unchecked',
      ]);
    });
  });

  group('shape and safety come before rules', () {
    test('a malformed answer reports its shape and no rule', () {
      expect(
        check('<!-- field id=x type=text max-chars=2 -->', 'een\ntwee drie'),
        ['answer-malformed'],
      );
    });

    test('safety problems are reported next to rule problems', () {
      expect(
        check(
          '<!-- field id=x type=prose words=..1 -->',
          'twee woorden <b>x</b>',
        ),
        ['answer-contains-html', 'too-many-words'],
      );
    });

    test('an image the safety rules refuse is not also unchecked', () {
      expect(check('<!-- field id=x type=image -->', '![a](http://x/1.png)'), [
        'answer-bad-image',
      ]);
    });

    test('safety problems keep their own line numbers', () {
      final i = issues('<!-- field id=x type=prose -->', 'a\n<b>');
      expect(i.single.line, 11);
    });

    test('a required field with only unsafe content is not "empty"', () {
      expect(check('<!-- field id=x type=prose required -->', '<b>x</b>'), [
        'answer-contains-html',
      ]);
    });
  });

  group('validateForm', () {
    FormSpec spec() =>
        (parseForm('''<!-- form id=f -->
<!-- field id=a type=text required -->
A
<!-- answer -->
<!-- /field id=a -->
<!-- field id=b type=prose words=2.. -->
B
<!-- answer -->
<!-- /field id=b -->
''')
                as ParsedForm)
            .spec;

    String doc(String a, String b) =>
        '''<!-- form id=f -->
<!-- field id=a type=text required -->
A
<!-- answer -->
$a
<!-- /field id=a -->
<!-- field id=b type=prose words=2.. -->
B
<!-- answer -->
$b
<!-- /field id=b -->
''';

    test('a complete submission has no issues', () {
      final s = spec();
      expect(
        validateForm(s, extractAnswers(s, doc('Sari', 'twee woorden'))),
        isEmpty,
      );
    });

    test('issues come in field order, structure first', () {
      final s = spec();
      final text = doc('', 'een').replaceFirst('version', 'version');
      final issues = validateForm(s, extractAnswers(s, text));
      expect(issues.map((i) => '${i.fieldId}:${i.code.wireName}'), [
        'a:required-empty',
        'b:too-few-words',
      ]);
    });

    test('structure problems are included', () {
      final s = spec();
      final issues = validateForm(s, extractAnswers(s, '# Niets\n'));
      expect(issues.map((i) => i.code), [FormIssueCode.structureDamaged]);
    });

    test('a missing field is reported once, not also as required-empty', () {
      final s = spec();
      final text = doc(
        'Sari',
        'x y',
      ).replaceFirst(RegExp(r'<!-- field id=b.*', dotAll: true), '');
      final issues = validateForm(s, extractAnswers(s, text));
      expect(issues.map((i) => '${i.fieldId}:${i.code.wireName}'), [
        'b:field-missing',
      ]);
    });

    test('image facts are passed through to the fields that need them', () {
      final s =
          (parseForm('''<!-- form id=f -->
<!-- field id=p type=image -->
P
<!-- answer -->
<!-- /field id=p -->
''')
                  as ParsedForm)
              .spec;
      const text = '''<!-- form id=f -->
<!-- field id=p type=image -->
P
<!-- answer -->
![a](images/a-1.jpg)
<!-- /field id=p -->
''';
      final answers = extractAnswers(s, text);
      expect(validateForm(s, answers).map((i) => i.code), [
        FormIssueCode.imageUnchecked,
      ]);
      expect(
        validateForm(
          s,
          answers,
          imageFacts: {
            'images/a-1.jpg': const FormImageFact(
              displayedWidth: 1,
              bytes: 1,
              format: 'jpg',
            ),
          },
        ),
        isEmpty,
      );
    });

    test('hasErrors tells whether sending is blocked', () {
      final s = spec();
      final bad = validateForm(s, extractAnswers(s, doc('', 'een')));
      expect(formIssuesBlock(bad), isTrue);
      expect(formIssuesBlock(const []), isFalse);
      expect(
        formIssuesBlock([FormProblem(FormIssueCode.imageTooSmall)]),
        isFalse,
        reason: 'a warning asks for confirmation; it does not block',
      );
    });
  });
}
