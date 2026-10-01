import 'package:ocideck_form_core/src/form_issue.dart';
import 'package:ocideck_form_core/src/form_template_text.dart';
import 'package:test/test.dart';

const String published = '''<!-- form id=f version=1 -->
# Formulier

Welkom bij het formulier.

<!-- notice -->
We bewaren je gegevens 6 maanden.
<!-- /notice -->

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->

<!-- /field id=naam -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord met publicatie van mijn bijdrage.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->

Tot slot: bedankt!
''';

/// [published] with the answers filled in.
String filled({String naam = 'Sari', String akkoord = '- [x]'}) => published
    .replaceFirst('<!-- answer -->\n\n', '<!-- answer -->\n$naam\n')
    .replaceFirst('<!-- answer -->\n- [ ]', '<!-- answer -->\n$akkoord');

List<FormProblem> diff(String submission) =>
    templateTextIssues(published, submission);

void main() {
  test('answers filled in, nothing else changed: no issue', () {
    expect(diff(filled()), isEmpty);
    expect(diff(published), isEmpty);
  });

  test('answers of any length and content are exempt', () {
    final long = List.filled(500, 'regel').join('\n');
    expect(diff(filled(naam: long, akkoord: '- [x]')), isEmpty);
    expect(diff(filled(naam: '<!-- notice -->\n# kop\n---')), isEmpty);
  });

  test('line endings and a BOM do not count', () {
    expect(diff(filled().replaceAll('\n', '\r\n')), isEmpty);
    expect(diff('﻿${filled()}'), isEmpty);
    expect(templateTextIssues(published, filled()), isEmpty);
    expect(
      templateTextIssues('﻿${published.replaceAll('\n', '\r\n')}', filled()),
      isEmpty,
    );
  });

  group('template-owned text that was changed', () {
    List<FormProblem> altered(String from, String to) =>
        diff(filled().replaceFirst(from, to));

    test('the consent text, the one that matters most', () {
      final i = altered(
        'Ik ga akkoord met publicatie van mijn bijdrage.',
        'Ik ga akkoord, behalve met publicatie van mijn foto.',
      );
      expect(i.map((p) => p.code), [FormIssueCode.templateTextAltered]);
      expect(i.single.facts['region'], 'akkoord');
      expect(i.single.fieldId, 'akkoord');
      expect(i.single.line, 17);
    });

    test('a label', () {
      final i = altered('**Naam**', '**Je naam**');
      expect(i.single.facts['region'], 'naam');
    });

    test('a rule in a marker: the rules are template-owned too', () {
      final i = altered(
        '<!-- field id=naam type=text required -->',
        '<!-- field id=naam type=text -->',
      );
      expect(i.single.code, FormIssueCode.templateTextAltered);
      expect(i.single.facts['region'], 'naam');
    });

    test('the form marker itself', () {
      final i = altered('version=1', 'version=1 rules=1');
      expect(i.single.facts['region'], 'outside-fields');
      expect(i.single.line, 1);
    });

    test('the introduction and the closing text', () {
      expect(
        altered('Welkom bij', 'Welkom terug bij').single.facts['region'],
        'outside-fields',
      );
      expect(
        altered('bedankt!', 'bedankt!!').single.facts['region'],
        'outside-fields',
      );
    });

    test('the notice', () {
      final i = altered('6 maanden', '60 jaar');
      expect(i.single.facts['region'], 'notice');
    });

    test('an answer marker moved, deleted or added is not a quiet change', () {
      expect(
        altered('<!-- answer -->\n- [x]', '- [x]\n<!-- answer -->'),
        isNotEmpty,
      );
    });

    test('the answer marker and the closing marker are template text too', () {
      final a = altered('<!-- answer -->\n- [x]', '<!--  answer -->\n- [x]');
      expect(a.single.facts['region'], 'akkoord');
      expect(a.single.line, 18);
      final c = altered(
        '<!-- /field id=akkoord -->',
        '<!--  /field id=akkoord -->',
      );
      expect(c.single.facts['region'], 'akkoord');
      expect(c.single.line, 20);
    });

    test('a trailing space that is in the published text counts as well', () {
      final spaced = published.replaceFirst('**Naam**', '**Naam** ');
      expect(
        templateTextIssues(spaced, filled()).single.code,
        FormIssueCode.templateTextAltered,
      );
    });

    test('a submission cut short: the line after its last one is named', () {
      final i = diff(filled().replaceFirst('\nTot slot: bedankt!\n', ''));
      expect(i.single.code, FormIssueCode.templateTextAltered);
      expect(i.single.line, 22);
    });

    test('whitespace counts: a trailing space is a change', () {
      expect(
        altered('**Naam**', '**Naam** ').single.code,
        FormIssueCode.templateTextAltered,
      );
    });

    test('a line added outside a zone', () {
      final i = altered('Tot slot', 'Extra regel\nTot slot');
      expect(i.single.facts['region'], 'outside-fields');
    });

    test('a line removed outside a zone', () {
      final i = diff(
        filled().replaceFirst('Welkom bij het formulier.\n\n', ''),
      );
      expect(i.single.code, FormIssueCode.templateTextAltered);
    });

    test('text appended after the last field', () {
      final i = diff('${filled()}\nEen heel nieuwe alinea.\n');
      expect(i.single.facts['region'], 'outside-fields');
    });

    test(
      'only the first difference is reported, with how many lines differ',
      () {
        final i = diff(
          filled()
              .replaceFirst('**Naam**', '**X**')
              .replaceFirst('bedankt!', 'dank!'),
        );
        expect(i, hasLength(1));
        expect(i.single.facts['differing'], 2);
        expect(i.single.facts['region'], 'naam', reason: 'the first one');
      },
    );
  });

  group('structure', () {
    test('a submission that is not a form is damaged', () {
      final i = diff('# Gewoon een document\n');
      expect(i.single.code, FormIssueCode.structureDamaged);
      expect(i.single.facts['reason'], 'not-a-form');
    });

    test('a broken submission is damaged and says where', () {
      final i = diff(filled().replaceFirst('<!-- /field id=naam -->\n', ''));
      expect(i.single.code, FormIssueCode.structureDamaged);
      expect(i.single.facts['reason'], 'broken');
    });

    test(
      'a field deleted from the submission is a change of template text',
      () {
        final i = diff(
          filled().replaceFirst(
            RegExp(
              r'<!-- field id=naam.*?<!-- /field id=naam -->\n',
              dotAll: true,
            ),
            '',
          ),
        );
        expect(i.single.code, FormIssueCode.templateTextAltered);
      },
    );

    test('an unreadable published template is reported, not crashed on', () {
      final i = templateTextIssues('# no form', filled());
      expect(i.single.code, FormIssueCode.structureDamaged);
      expect(i.single.facts['reason'], 'published-form');
    });

    test('a published template that needs newer rules is not compared', () {
      final i = templateTextIssues(
        published.replaceFirst('version=1', 'version=1 rules=9'),
        filled(),
      );
      expect(i.single.facts['reason'], 'published-form');
    });
  });

  test(
    'an answer zone containing a marker line is zone text, not a difference',
    () {
      expect(diff(filled(naam: 'a\n<!-- answer -->\nb')), isEmpty);
    },
  );
}
