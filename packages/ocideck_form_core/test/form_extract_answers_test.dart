import 'package:ocideck_form_core/src/form_answers.dart';
import 'package:ocideck_form_core/src/form_issue.dart';
import 'package:ocideck_form_core/src/form_parser.dart';
import 'package:ocideck_form_core/src/form_spec.dart';
import 'package:test/test.dart';

/// A published template with one field of several kinds, answers empty.
String template({
  String naam = '',
  String keuze = '',
  String akkoord = '- [ ]',
}) =>
    '''<!-- form id=f version=2 -->
# Formulier

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
$naam
<!-- /field id=naam -->

<!-- field id=keuze type=multichoice options="A|B|C" count=1..2 -->
**Keuze**
<!-- answer -->
$keuze
<!-- /field id=keuze -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord met publicatie.
<!-- answer -->
$akkoord
<!-- /field id=akkoord -->
''';

FormSpec published() => (parseForm(template()) as ParsedForm).spec;

void main() {
  test('answers come back by field id, typed, with the line to edit', () {
    final submission = template(
      naam: 'Sari Voorbeeld',
      keuze: '- [x] A\n- [ ] B\n- [x] C',
      akkoord: '- [x]',
    );
    final r = extractAnswers(published(), submission);
    expect(r.structure, isEmpty);
    expect(r.byId.keys, ['naam', 'keuze', 'akkoord']);
    expect(r.byId['naam']!.text, 'Sari Voorbeeld');
    expect(r.byId['keuze']!.items, ['A', 'C']);
    expect(r.byId['akkoord']!.consent, isTrue);
    expect(r.byId['naam']!.type, 'text');
    // The zone of "naam" starts on the line after its answer marker.
    final lines = submission.split('\n');
    expect(lines[r.byId['naam']!.firstLine - 1], 'Sari Voorbeeld');
    expect(lines[r.byId['akkoord']!.firstLine - 1], '- [x]');
  });

  test('an unanswered template reads as empty answers, not as an error', () {
    final r = extractAnswers(published(), template());
    expect(r.structure, isEmpty);
    expect(r.byId['naam']!.isEmpty, isTrue);
    expect(r.byId['keuze']!.isEmpty, isTrue);
    expect(r.byId['akkoord']!.consent, isFalse);
  });

  test('CRLF documents read the same', () {
    final r = extractAnswers(
      published(),
      template(
        naam: 'Sari',
        keuze: '- [x] B',
        akkoord: '- [x]',
      ).replaceAll('\n', '\r\n'),
    );
    expect(r.structure, isEmpty);
    expect(r.byId['naam']!.text, 'Sari');
    expect(r.byId['keuze']!.items, ['B']);
  });

  test('a BOM and front matter above the form do not matter', () {
    final text = '﻿---\ntheme: pro\n---\n${template(naam: 'Sari')}';
    final r = extractAnswers(published(), text);
    expect(r.structure, isEmpty);
    expect(r.byId['naam']!.text, 'Sari');
  });

  group('the published form decides, not the submission', () {
    test('rules and types written in the submission are ignored', () {
      // The submission claims `naam` is a multichoice and has no `required`.
      final tampered = template(
        naam: '- [x] A',
      ).replaceFirst('type=text required', 'type=multichoice options="A"');
      final r = extractAnswers(published(), tampered);
      expect(r.structure, isEmpty);
      expect(
        r.byId['naam']!.type,
        'text',
        reason: 'the published type is used',
      );
      expect(r.byId['naam']!.items, isEmpty);
      expect(r.byId['naam']!.text, '- [x] A');
    });

    test('a submission whose header names another form is damaged', () {
      final other = template().replaceFirst('id=f ', 'id=g ');
      final r = extractAnswers(published(), other);
      expect(r.byId, isEmpty);
      expect(r.structure.single.code, FormIssueCode.structureDamaged);
      expect(r.structure.single.facts['reason'], 'form-id');
      expect(r.structure.single.facts['published'], 'f');
      expect(r.structure.single.facts['submission'], 'g');
    });

    test('another version is a warning, and the answers are still read', () {
      final older = template(
        naam: 'Sari',
      ).replaceFirst('version=2', 'version=1');
      final r = extractAnswers(published(), older);
      final warning = r.structure.single;
      expect(warning.code, FormIssueCode.formVersionMismatch);
      expect(warning.severity, FormSeverity.warning);
      expect(warning.facts, {'published': 2, 'submission': 1});
      expect(r.byId['naam']!.text, 'Sari');
    });
  });

  group('structure', () {
    test('a field the submission lacks is reported and has no answer', () {
      final text = template().replaceFirst(
        RegExp(
          r'<!-- field id=keuze.*?<!-- /field id=keuze -->\n',
          dotAll: true,
        ),
        '',
      );
      final r = extractAnswers(published(), text);
      expect(r.structure.map((p) => p.code), [FormIssueCode.fieldMissing]);
      expect(r.structure.single.fieldId, 'keuze');
      expect(r.byId.keys, ['naam', 'akkoord']);
    });

    test('a field the form does not have is reported at its line', () {
      final text =
          '${template()}\n<!-- field id=extra type=text -->\nL\n<!-- answer -->\n<!-- /field id=extra -->\n';
      final r = extractAnswers(published(), text);
      expect(r.structure.map((p) => p.code), [FormIssueCode.fieldNotInForm]);
      expect(r.structure.single.fieldId, 'extra');
      expect(r.structure.single.line, greaterThan(20));
      expect(r.byId.keys, ['naam', 'keuze', 'akkoord']);
    });

    test(
      'answers follow the published order whatever the submission order',
      () {
        final text = '''<!-- form id=f version=2 -->
<!-- field id=akkoord type=consent -->
x
<!-- answer -->
- [x]
<!-- /field id=akkoord -->
<!-- field id=keuze type=multichoice options="A" -->
x
<!-- answer -->
- [x] A
<!-- /field id=keuze -->
<!-- field id=naam type=text -->
x
<!-- answer -->
Sari
<!-- /field id=naam -->
''';
        final r = extractAnswers(published(), text);
        expect(r.byId.keys, ['naam', 'keuze', 'akkoord']);
        expect(r.byId['naam']!.text, 'Sari');
      },
    );

    test('not a form at all is structure-damaged, not an exception', () {
      final r = extractAnswers(published(), '# Gewoon een document\n');
      expect(r.byId, isEmpty);
      expect(r.structure.single.code, FormIssueCode.structureDamaged);
      expect(r.structure.single.facts['reason'], 'not-a-form');
    });

    test('a broken form says what is broken and where', () {
      final r = extractAnswers(
        published(),
        template().replaceFirst('<!-- /field id=naam -->\n', ''),
      );
      expect(r.byId, isEmpty);
      final p = r.structure.single;
      expect(p.code, FormIssueCode.structureDamaged);
      expect(p.facts['reason'], 'broken');
      expect(p.facts['problems'], contains('unpaired-marker'));
      expect(p.facts['line'], isNotNull);
    });

    test('a submission that needs newer rules is not read', () {
      final r = extractAnswers(
        published(),
        template().replaceFirst('version=2', 'version=2 rules=9'),
      );
      expect(r.byId, isEmpty);
      expect(r.structure.single.facts['reason'], 'rules-too-new');
    });

    test(
      'a marker line pasted into an answer is answer text, not structure',
      () {
        final r = extractAnswers(
          published(),
          template(naam: 'a\n<!-- notice -->\nb'),
        );
        expect(r.structure, isEmpty);
        expect(r.byId['naam']!.raw, contains('<!-- notice -->'));
      },
    );
  });

  test('shape problems of an answer travel with it', () {
    final r = extractAnswers(
      published(),
      template(naam: 'een\ntwee', akkoord: 'ja'),
    );
    expect(r.byId['naam']!.shape.single.facts['reason'], 'one-line');
    expect(r.byId['akkoord']!.shape.single.facts['reason'], 'consent-box');
    expect(r.structure, isEmpty);
  });
}
