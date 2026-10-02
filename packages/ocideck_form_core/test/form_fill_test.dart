import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

/// A small recipe form: a title, an introduction, a notice, two sections, one
/// field with a heading in its own label, and a closing remark.
const form = '''<!-- form id=kookboek version=2 -->
# Inzending Kookboek

Kook je graag? Dit kost zo'n 45 minuten.

<!-- notice -->
We bewaren je gegevens tot de oproep sluit.
<!-- /notice -->

## A. Jij

Vul je gegevens in.

<!-- field id=naam type=text required max-chars=20 -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord met publicatie.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->

## B. Het recept

<!-- field id=verhaal type=prose required words=3..6 -->
## Het verhaal
> vertel
<!-- answer -->
<!-- /field id=verhaal -->

Tot slot: bedankt!
''';

FormFill open(String text, {FormImageFacts facts = const {}}) {
  final result = FormFill.open(text, imageFacts: facts);
  expect(result, isA<FormFillReady>());
  return (result as FormFillReady).fill;
}

FormFill answer(FormFill fill, String id, FormAnswerValue value) {
  final step = fill.setAnswer(id, value);
  expect(step, isA<FormFillChanged>());
  return (step as FormFillChanged).fill;
}

void main() {
  group('open', () {
    test('a form is ready, with its title and notice', () {
      final fill = open(form);
      expect(fill.title, 'Inzending Kookboek');
      expect(fill.notice, 'We bewaren je gegevens tot de oproep sluit.');
      expect(fill.spec.id, 'kookboek');
      expect(fill.text, form);
    });

    test('an ordinary document is unavailable, and says not-a-form', () {
      final result = FormFill.open('# Een gewoon document\n');
      expect(result, isA<FormFillUnavailable>());
      final problem = (result as FormFillUnavailable).problem;
      expect(problem.code, FormIssueCode.structureDamaged);
      expect(problem.facts['reason'], 'not-a-form');
    });

    test('a broken form is unavailable, and names what is wrong', () {
      final result = FormFill.open(
        '<!-- form id=f -->\n<!-- field id=a type=text -->\nL\n',
      );
      final problem = (result as FormFillUnavailable).problem;
      expect(problem.facts['reason'], 'broken');
      expect(problem.facts['problems'], contains('unpaired-marker'));
      expect(problem.facts['line'], isA<int>());
    });

    test('a form that needs newer rules is unavailable', () {
      final result = FormFill.open(
        '<!-- form id=f rules=999 -->\n<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n',
      );
      expect(
        (result as FormFillUnavailable).problem.facts['reason'],
        'rules-too-new',
      );
    });

    test('a form with no fields opens, with nothing to answer', () {
      final fill = open('<!-- form id=f -->\n# Titel\n\nAlleen tekst.\n');
      expect(fill.spec.fields, isEmpty);
      expect(fill.openCount, 0);
      expect(fill.canSend, isTrue);
      expect(fill.notice, isNull);
      expect(fill.items.map((i) => (i as FormTextItem).markdown), [
        'Alleen tekst.',
      ]);
    });

    test('without a level-1 heading the title is the form id', () {
      final fill = open(
        '<!-- form id=kook -->\n<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n',
      );
      expect(fill.title, 'kook');
    });
  });

  group('the page', () {
    test('items follow the document: text, notice, headings, fields', () {
      final kinds = [
        for (final item in open(form).items)
          switch (item) {
            FormTextItem(:final markdown) =>
              'text:${markdown.split('\n').first}',
            FormNoticeItem() => 'notice',
            FormHeadingItem(:final title) => 'heading:$title',
            FormFieldItem(:final fieldId) => 'field:$fieldId',
          },
      ];
      expect(kinds, [
        "text:Kook je graag? Dit kost zo'n 45 minuten.",
        'notice',
        'heading:A. Jij',
        'text:Vul je gegevens in.',
        'field:naam',
        'field:akkoord',
        'heading:B. Het recept',
        'field:verhaal',
        'text:Tot slot: bedankt!',
      ]);
    });

    test('a heading inside a field is part of its label, not a section', () {
      final headings = open(form).sections.map((s) => s.title);
      expect(headings, ['A. Jij', 'B. Het recept']);
    });

    test('a section knows the fields under it', () {
      final sections = open(form).sections;
      expect(sections[0].fieldIds, ['naam', 'akkoord']);
      expect(sections[1].fieldIds, ['verhaal']);
    });

    test('a heading inside a fence is code, not a section', () {
      final fill = open(
        '<!-- form id=f -->\n'
        'Uitleg:\n'
        '```\n'
        '## geen kop\n'
        '```\n'
        '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n',
      );
      expect(fill.sections, isEmpty);
      expect(
        (fill.items.first as FormTextItem).markdown,
        contains('## geen kop'),
      );
    });

    test('the title is not an item; a later level-1 heading is a section', () {
      final fill = open(
        '<!-- form id=f -->\n# Titel\n# Tweede\n<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n',
      );
      expect(fill.title, 'Titel');
      expect(fill.sections.single.title, 'Tweede');
      expect(fill.sections.single.level, 1);
    });

    test('only a level-1 heading before the first field is the title', () {
      // A level-2 heading first is a section; the title is then the form id.
      final fill = open(
        '<!-- form id=kook -->\n## A. Jij\n'
        '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n',
      );
      expect(fill.title, 'kook');
      expect(fill.sections.single.title, 'A. Jij');
    });

    test('a level-1 heading after the first field is a section, not the title', () {
      final fill = open(
        '<!-- form id=kook -->\n'
        '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n'
        '# Deel B\n'
        '<!-- field id=b type=text -->\nL\n<!-- answer -->\n<!-- /field id=b -->\n',
      );
      expect(fill.title, 'kook');
      expect(fill.sections.single.title, 'Deel B');
      expect(fill.sections.single.fieldIds, ['b']);
    });

    test('a heading with trailing hashes and blanks is its text only', () {
      final fill = open(
        '<!-- form id=kook -->\n## Deel A ##  \n'
        '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n',
      );
      expect(fill.sections.single.title, 'Deel A');
    });

    test('fields before the first heading belong to no heading', () {
      final fill = open(
        '<!-- form id=f -->\n'
        '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n'
        '## Daarna\n'
        '<!-- field id=b type=text -->\nL\n<!-- answer -->\n<!-- /field id=b -->\n',
      );
      expect(fill.sections.single.fieldIds, ['b']);
      expect(fill.items.first, isA<FormFieldItem>());
    });
  });

  group('state', () {
    test('required fields start open; the others do not', () {
      final fill = open(form);
      expect(fill.openFieldIds, ['naam', 'akkoord', 'verhaal']);
      expect(fill.openCount, 3);
      expect(fill.canSend, isFalse);
      expect(fill.problemsOf('naam').single.code, FormIssueCode.requiredEmpty);
    });

    test('a section counts its own open fields', () {
      final fill = open(form);
      expect(fill.openIn(fill.sections[0]), 2);
      expect(fill.openIn(fill.sections[1]), 1);
      final done = answer(fill, 'naam', const FormAnswerValue(text: 'Sari'));
      expect(done.openIn(done.sections[0]), 1);
    });

    test('answering every field makes the form sendable', () {
      var fill = open(form);
      fill = answer(fill, 'naam', const FormAnswerValue(text: 'Sari'));
      fill = answer(fill, 'akkoord', const FormAnswerValue(consent: true));
      fill = answer(
        fill,
        'verhaal',
        const FormAnswerValue(text: 'een twee drie vier'),
      );
      expect(fill.openCount, 0);
      expect(fill.canSend, isTrue);
      expect(fill.allProblems, isEmpty);
      expect(fill.gateIssues(), isEmpty);
    });

    test('a problem points at the first line of its zone', () {
      final fill = answer(
        open(form),
        'verhaal',
        const FormAnswerValue(text: 'een twee'),
      );
      final lines = fill.text.split('\n');
      final zoneLine = lines.indexOf('een twee') + 1; // 1-based
      expect(fill.problemsOf('verhaal').single.line, zoneLine);
    });

    test('a rule that is broken keeps the field open and says which', () {
      final fill = answer(
        open(form),
        'verhaal',
        const FormAnswerValue(text: 'een twee'),
      );
      expect(fill.problemsOf('verhaal').single.code, FormIssueCode.tooFewWords);
      expect(fill.openFieldIds, contains('verhaal'));
      final long = answer(
        fill,
        'naam',
        const FormAnswerValue(text: 'een veel te lange naam voor dit veld'),
      );
      expect(long.problemsOf('naam').single.code, FormIssueCode.tooLong);
    });

    test('answerOf and countsOf read the current answer', () {
      final fill = answer(
        open(form),
        'verhaal',
        const FormAnswerValue(text: 'een twee drie'),
      );
      expect(fill.answerOf('verhaal').text, 'een twee drie');
      expect(fill.countsOf('verhaal'), [
        const FormCount(FormCountUnit.words, 3, min: 3, max: 6),
      ]);
      expect(fill.countsOf('akkoord'), isEmpty);
      expect(fill.fieldOf('verhaal').type, 'prose');
    });

    test('a warning does not close the way to sending', () {
      const withImage =
          '<!-- form id=f -->\n'
          '<!-- field id=foto type=image min-width=2000 -->\nL\n'
          '<!-- answer -->\n'
          '![x](images/foto-1.jpg)\n'
          '<!-- /field id=foto -->\n';
      final fill = open(
        withImage,
        facts: {
          'images/foto-1.jpg': const FormImageFact(
            displayedWidth: 1600,
            format: 'jpg',
          ),
        },
      );
      expect(fill.problemsOf('foto').map((p) => p.code), [
        FormIssueCode.imageTooSmall,
      ]);
      expect(fill.problemsOf('foto').single.severity, FormSeverity.warning);
      expect(fill.canSend, isTrue);
    });
  });

  group('setAnswer', () {
    test('only the zone changes; the rest of the document is byte-equal', () {
      final fill = open(form);
      final next = answer(fill, 'naam', const FormAnswerValue(text: 'Sari'));
      expect(
        next.text,
        form.replaceFirst(
          '<!-- answer -->\n<!-- /field id=naam -->',
          '<!-- answer -->\nSari\n<!-- /field id=naam -->',
        ),
      );
      expect(fill.text, form, reason: 'the old fill is untouched');
    });

    test('the next fill is parsed from its own text', () {
      final next = answer(
        open(form),
        'naam',
        const FormAnswerValue(text: 'Sari'),
      );
      final verhaal = next.fieldOf('verhaal');
      expect(
        next.text.substring(verhaal.open.start, verhaal.open.end),
        '<!-- field id=verhaal type=prose required words=3..6 -->',
      );
      expect(next.answerOf('naam').text, 'Sari');
    });

    test('an answer that would end its own zone is refused', () {
      final step = open(form).setAnswer(
        'verhaal',
        const FormAnswerValue(text: '<!-- /field id=verhaal -->'),
      );
      expect(step, isA<FormFillRefused>());
      expect(
        (step as FormFillRefused).problem.code,
        FormIssueCode.answerContainsMarker,
      );
    });

    test('an unknown field is a programming error', () {
      expect(
        () => open(form).setAnswer('nope', const FormAnswerValue()),
        throwsArgumentError,
      );
    });

    test('clearing an answer gives back the skeleton and the open state', () {
      var fill = answer(
        open(form),
        'naam',
        const FormAnswerValue(text: 'Sari'),
      );
      expect(fill.openFieldIds, isNot(contains('naam')));
      fill = answer(fill, 'naam', const FormAnswerValue());
      expect(fill.openFieldIds, contains('naam'));
    });
  });

  group('image facts', () {
    const doc =
        '<!-- form id=f -->\n'
        '<!-- field id=foto type=image required -->\nL\n'
        '<!-- answer -->\n'
        '![x](images/foto-1.jpg)\n'
        '<!-- /field id=foto -->\n'
        '<!-- field id=naam type=text required -->\nL\n<!-- answer -->\n'
        '<!-- /field id=naam -->\n';

    test('without a fact an image is unchecked, and that blocks', () {
      final fill = open(doc);
      expect(fill.problemsOf('foto').map((p) => p.code), [
        FormIssueCode.imageUnchecked,
      ]);
      expect(fill.openFieldIds, contains('foto'));
    });

    test('new facts judge the image fields again and no others', () {
      final fill = open(doc);
      final checked = fill.withImageFacts({
        'images/foto-1.jpg': const FormImageFact(format: 'jpg'),
      });
      expect(checked.problemsOf('foto'), isEmpty);
      expect(checked.imageFacts, hasLength(1));
      // The text field was not judged again: it is the same list.
      expect(
        identical(checked.problemsOf('naam'), fill.problemsOf('naam')),
        isTrue,
      );
      expect(checked.text, fill.text);
    });

    test('facts survive an edit', () {
      final fill = open(
        doc,
        facts: {'images/foto-1.jpg': const FormImageFact(format: 'jpg')},
      );
      final next = answer(fill, 'naam', const FormAnswerValue(text: 'Sari'));
      expect(next.problemsOf('foto'), isEmpty);
      expect(next.imageFacts, isNotEmpty);
    });
  });

  group('gateIssues', () {
    test('compares the text outside the answers with the published form', () {
      final fill = answer(
        open(form),
        'naam',
        const FormAnswerValue(text: 'Sari'),
      );
      expect(
        fill.gateIssues(published: form).map((p) => p.code),
        isNot(contains(FormIssueCode.templateTextAltered)),
      );
      final tampered = fill.text.replaceFirst(
        'Ik ga akkoord met publicatie.',
        'Ik ga akkoord met alles.',
      );
      final bad = open(tampered);
      expect(
        bad.gateIssues(published: form).map((p) => p.code),
        contains(FormIssueCode.templateTextAltered),
      );
      expect(
        bad.gateIssues().map((p) => p.code),
        isNot(contains(FormIssueCode.templateTextAltered)),
        reason: 'without a published form there is nothing to compare with',
      );
    });
  });
}
