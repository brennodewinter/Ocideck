import 'package:ocideck_form_core/src/form_issue.dart';
import 'package:ocideck_form_core/src/form_parser.dart';
import 'package:ocideck_form_core/src/form_spec.dart';
import 'package:test/test.dart';

/// A complete, consistent template: FORM_INTAKE.md §4.2 with the fields that its
/// `overview=` attribute names (the document shows an excerpt).
const String kTemplate =
    '''<!-- form id=kookboek-inzending version=1 rules=1 lang=nl controller="Indo IT Kookboek-team" contact="kookboek@example.org" retain-unused="6 maanden na sluiting" closes=2027-01-31 overview="naam,gerecht,categorie" -->
# Inzending Indo IT Kookboek

Kook jij een gerecht met een verhaal? Dit formulier kost ongeveer 45 minuten.

<!-- notice -->
Je gegevens worden alleen gebruikt voor het Indo IT Kookboek.
<!-- /notice -->

## A. Contact en profiel

<!-- field id=naam type=text required max-chars=80 -->
**Volledige naam**
<!-- answer -->
Sari Voorbeeld
<!-- /field id=naam -->

<!-- field id=gerecht type=text required -->
**Naam van het gerecht**
<!-- answer -->

<!-- /field id=gerecht -->

<!-- field id=categorie type=choice required options="Quick Fix|Weekend Project|Legacy Recipe" -->
**Categorie**
<!-- answer -->
Quick Fix
<!-- /field id=categorie -->

<!-- field id=verhaal type=prose required words=150..300 -->
## Het verhaal
> Wie ben je, wat verbindt je met dit gerecht?
<!-- answer -->

<!-- /field id=verhaal -->
''';

FormParseResult parse(String s) => parseForm(s);

ParsedForm parsed(String s) {
  final r = parse(s);
  expect(
    r,
    isA<ParsedForm>(),
    reason: r is BrokenForm ? '${r.problems}' : '$r',
  );
  return r as ParsedForm;
}

BrokenForm broken(String s) {
  final r = parse(s);
  expect(r, isA<BrokenForm>(), reason: r is ParsedForm ? '${r.notes}' : '$r');
  return r as BrokenForm;
}

/// The wire names of a problem list, for compact assertions.
List<String> codes(List<FormProblem> ps) => [
  for (final p in ps) p.code.wireName,
];

/// A template with one field built from [fieldMarker], for rule tests.
String one(String fieldMarker, {String id = 'x'}) =>
    '<!-- form id=f version=1 -->\n'
    '$fieldMarker\n**Label**\n<!-- answer -->\n<!-- /field id=$id -->\n';

void main() {
  group('not a form', () {
    test('plain text and ordinary comments', () {
      for (final s in [
        '',
        '# Title\n\nSome text.\n',
        '<!-- toc -->\n# Doc\n',
        '<!-- a note -->\ntext',
        '﻿# Title',
        '---\ntheme: x\n---\n# Doc\n',
      ]) {
        expect(parse(s), isA<NotAForm>(), reason: s);
      }
    });

    test('a notice marker alone does not make a form', () {
      expect(
        parse('<!-- notice -->\ntext\n<!-- /notice -->\n'),
        isA<NotAForm>(),
      );
    });

    test(
      'markers inside fenced code are content, so a README is not a form',
      () {
        const readme = '''# How to write a form

```markdown
<!-- form id=x version=1 -->
<!-- field id=a type=text -->
<!-- answer -->
<!-- /field id=a -->
```
''';
        expect(parse(readme), isA<NotAForm>());
      },
    );

    test(
      'an indented marker (a code block) and an inline mention are not markers',
      () {
        expect(parse('    <!-- form id=x -->\n'), isA<NotAForm>());
        expect(parse('Use `<!-- form id=x -->` first.\n'), isA<NotAForm>());
        expect(parse('- <!-- form id=x -->\n'), isA<NotAForm>());
      },
    );

    test('front-matter lines are not markers', () {
      expect(
        parse('---\nnote: "<!-- form id=x -->"\n---\n# Doc\n'),
        isA<NotAForm>(),
      );
    });
  });

  group('the template of §4.2', () {
    test('parses into a spec with the form attributes', () {
      final f = parsed(kTemplate).spec;
      expect(f.id, 'kookboek-inzending');
      expect(f.version, 1);
      expect(f.rules, 1);
      expect(f.lang, 'nl');
      expect(f.controller, 'Indo IT Kookboek-team');
      expect(f.contact, 'kookboek@example.org');
      expect(f.retainUnused, '6 maanden na sluiting');
      expect(f.closes, '2027-01-31');
      expect(f.overview, ['naam', 'gerecht', 'categorie']);
      expect(f.states, isEmpty);
      expect(f.keepRecord, isEmpty);
      expect(f.extraAttributes, isEmpty);
    });

    test('and no problems at all', () {
      expect(parsed(kTemplate).notes, isEmpty);
    });

    test('fields come in document order with their types and rules', () {
      final f = parsed(kTemplate).spec;
      expect(f.fields.map((x) => x.id), [
        'naam',
        'gerecht',
        'categorie',
        'verhaal',
      ]);
      expect(f.fields.map((x) => x.type), ['text', 'text', 'choice', 'prose']);
      expect(f.fields.map((x) => x.required), [true, true, true, true]);
      expect(f.fieldById('naam')!.intRule('max-chars'), 80);
      expect(f.fieldById('categorie')!.list('options'), [
        'Quick Fix',
        'Weekend Project',
        'Legacy Recipe',
      ]);
      final words = f.fieldById('verhaal')!.range('words')!;
      expect((words.min, words.max), (150, 300));
      expect(f.fieldById('nope'), isNull);
    });

    test('regions slice back to the exact text of the source', () {
      final text = kTemplate;
      final f = parsed(text).spec;
      final naam = f.fieldById('naam')!;
      expect(
        text.substring(naam.open.start, naam.open.end),
        '<!-- field id=naam type=text required max-chars=80 -->',
      );
      expect(
        text.substring(naam.label.start, naam.label.end),
        '**Volledige naam**\n',
      );
      expect(
        text.substring(naam.zone.start, naam.zone.end),
        'Sari Voorbeeld\n',
      );
      expect(
        text.substring(naam.close.start, naam.close.end),
        '<!-- /field id=naam -->',
      );
      final gerecht = f.fieldById('gerecht')!;
      expect(
        text.substring(gerecht.zone.start, gerecht.zone.end),
        '\n',
        reason: 'an empty answer is one blank line here',
      );
      final verhaal = f.fieldById('verhaal')!;
      expect(
        text.substring(verhaal.label.start, verhaal.label.end),
        '## Het verhaal\n> Wie ben je, wat verbindt je met dit gerecht?\n',
      );
    });

    test('the notice region and the introduction are located', () {
      final text = kTemplate;
      final f = parsed(text).spec;
      expect(
        text.substring(f.notice!.content.start, f.notice!.content.end),
        'Je gegevens worden alleen gebruikt voor het Indo IT Kookboek.\n',
      );
      final intro = text.substring(f.intro.start, f.intro.end);
      expect(intro, startsWith('# Inzending Indo IT Kookboek'));
      expect(intro, contains('45 minuten'));
      expect(intro, isNot(contains('field id=naam')));
    });

    test('line numbers are 1-based and point at the markers', () {
      final f = parsed(kTemplate).spec;
      expect(f.formMarker.line, 1);
      expect(f.fieldById('naam')!.open.line, 12);
      expect(f.fieldById('naam')!.answer.line, 14);
      expect(f.fieldById('naam')!.close.line, 16);
    });

    test('is deterministic', () {
      final a = parsed(kTemplate).spec;
      final b = parsed(kTemplate).spec;
      expect(a.fields.map((x) => x.id), b.fields.map((x) => x.id));
      expect(a.intro.end, b.intro.end);
    });
  });

  group('surroundings of the file', () {
    test('a BOM before the form marker is fine and offsets still slice', () {
      final text = '﻿$kTemplate';
      final f = parsed(text).spec;
      final naam = f.fieldById('naam')!;
      expect(
        text.substring(naam.zone.start, naam.zone.end),
        'Sari Voorbeeld\n',
      );
    });

    test('CRLF files parse the same; the CR belongs to the line it ends', () {
      final text = kTemplate.replaceAll('\n', '\r\n');
      final f = parsed(text).spec;
      expect(f.fields.length, 4);
      final naam = f.fieldById('naam')!;
      expect(
        text.substring(naam.zone.start, naam.zone.end),
        'Sari Voorbeeld\r\n',
      );
      expect(
        text.substring(naam.open.start, naam.open.end),
        '<!-- field id=naam type=text required max-chars=80 -->',
      );
    });

    test(
      'front matter above the form is skipped (a document style was chosen)',
      () {
        final text = '---\ntheme: pro\n---\n\n$kTemplate';
        final f = parsed(text).spec;
        expect(f.id, 'kookboek-inzending');
        expect(f.formMarker.line, 5);
      },
    );

    test('a leading --- that is a page break does not hide the form', () {
      final text = '---\n$kTemplate';
      expect(parsed(text).spec.fields.length, 4);
    });

    test('front matter that mentions a marker does not count as the form', () {
      final text =
          '---\nnote: "<!-- form id=zzz version=1 -->"\n---\n$kTemplate';
      expect(parsed(text).spec.id, 'kookboek-inzending');
    });

    test('no final newline is fine', () {
      final f = parsed(kTemplate.trimRight()).spec;
      final v = f.fieldById('verhaal')!;
      expect(v.close.nextStart, kTemplate.trimRight().length);
    });
  });

  group('the form marker', () {
    test('must come first among the markers', () {
      final p = broken(
        '<!-- notice -->\nx\n<!-- /notice -->\n<!-- form id=f -->\n',
      );
      expect(codes(p.problems), contains('marker-misplaced'));
      expect(
        p.problems
            .firstWhere((x) => x.code == FormIssueCode.markerMisplaced)
            .facts['reason'],
        'form-not-first',
      );
    });

    test('there is at most one', () {
      final p = broken('<!-- form id=a -->\n<!-- form id=b -->\n');
      final prob = p.problems.firstWhere(
        (x) => x.code == FormIssueCode.markerMisplaced,
      );
      expect(prob.facts['reason'], 'second-form');
      expect(prob.line, 2);
    });

    test('a field before any form marker is a broken form, not no form', () {
      final p = broken(
        '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n',
      );
      expect(p.problems.first.code, FormIssueCode.markerMisplaced);
      expect(p.problems.first.facts['reason'], 'form-missing');
    });

    test('an id is required and must be a slug', () {
      expect(
        codes(broken('<!-- form -->\n').problems),
        contains('marker-malformed'),
      );
      expect(broken('<!-- form -->\n').problems.first.facts['attribute'], 'id');
      for (final bad in ['Form', '1x', 'a_b', 'a b']) {
        expect(
          codes(broken('<!-- form id="$bad" -->\n').problems),
          contains('marker-malformed'),
          reason: bad,
        );
      }
    });

    test('version and rules default to 1 and must be positive integers', () {
      final f = parsed('<!-- form id=f -->\n').spec;
      expect((f.version, f.rules), (1, 1));
      for (final attr in [
        'version=0',
        'version=x',
        'rules=0',
        'rules=-1',
        'rules=1.5',
      ]) {
        final p = broken('<!-- form id=f $attr -->\n');
        expect(
          p.problems.first.code,
          FormIssueCode.ruleMalformed,
          reason: attr,
        );
        expect(p.problems.first.facts['rule'], attr.split('=').first);
      }
    });

    test('an attribute that needs a value is malformed as a bare flag', () {
      for (final key in [
        'version',
        'rules',
        'lang',
        'controller',
        'contact',
        'closes',
        'overview',
        'states',
        'keep-record',
        'retain-unused',
      ]) {
        final p = broken('<!-- form id=f $key -->\n');
        expect(p.problems.first.code, FormIssueCode.ruleMalformed, reason: key);
        expect(p.problems.first.facts['reason'], 'value-required', reason: key);
      }
    });

    test('lang, controller, contact and retain-unused may not be empty', () {
      for (final key in ['lang', 'controller', 'contact', 'retain-unused']) {
        for (final empty in ['""', '"  "']) {
          final p = broken('<!-- form id=f $key=$empty -->\n');
          expect(
            p.problems.first.code,
            FormIssueCode.ruleMalformed,
            reason: key,
          );
          expect(p.problems.first.facts['reason'], 'empty', reason: key);
          expect(p.problems.first.facts['rule'], key);
        }
      }
    });

    test('closes must be a real date', () {
      expect(
        broken(
          '<!-- form id=f closes=2027-02-30 -->\n',
        ).problems.first.facts['rule'],
        'closes',
      );
      expect(
        broken('<!-- form id=f closes=31-01-2027 -->\n').problems.first.code,
        FormIssueCode.ruleMalformed,
      );
    });

    test('states is a pipe list of distinct words', () {
      final f = parsed(
        '<!-- form id=f states="received|edited|laid-out" -->\n',
      ).spec;
      expect(f.states, ['received', 'edited', 'laid-out']);
      expect(
        broken(
          '<!-- form id=f states="a||b" -->\n',
        ).problems.first.facts['reason'],
        'empty-item',
      );
      expect(
        broken(
          '<!-- form id=f states="a|a" -->\n',
        ).problems.first.facts['reason'],
        'duplicate-item',
      );
    });

    test('overview and keep-record name fields that must exist', () {
      final ok = parsed(
        one('<!-- field id=x type=text -->').replaceFirst(
          'id=f version=1',
          'id=f version=1 overview=x keep-record=x',
        ),
      ).spec;
      expect(ok.overview, ['x']);
      expect(ok.keepRecord, ['x']);
      final p = broken(
        one(
          '<!-- field id=x type=text -->',
        ).replaceFirst('id=f version=1', 'id=f version=1 overview="x,nope"'),
      );
      expect(p.problems.single.code, FormIssueCode.ruleMalformed);
      expect(p.problems.single.facts, containsPair('reason', 'unknown-field'));
      expect(p.problems.single.facts['field'], 'nope');
      final q = broken(
        one(
          '<!-- field id=x type=text -->',
        ).replaceFirst('id=f version=1', 'id=f version=1 keep-record="ghost"'),
      );
      expect(q.problems.single.facts['rule'], 'keep-record');
    });

    test('overview and keep-record may not list a field twice', () {
      final p = broken(
        one(
          '<!-- field id=x type=text -->',
        ).replaceFirst('id=f version=1', 'id=f version=1 overview="x,x"'),
      );
      expect(p.problems.single.facts['reason'], 'duplicate-item');
    });

    test('unknown attributes are preserved and reported as info', () {
      final r = parsed('<!-- form id=f flavour=sweet beta -->\n');
      expect(r.spec.extraAttributes, {'flavour': 'sweet', 'beta': null});
      final infos = r.notes
          .where((n) => n.code == FormIssueCode.unknownRule)
          .toList();
      expect(infos.length, 2);
      expect(infos.every((n) => n.severity == FormSeverity.info), isTrue);
    });
  });

  group('rules newer than this engine (§4.8)', () {
    test('refuses to judge: a spec with the header only, plus rules-too-new', () {
      final text =
          '<!-- form id=f version=3 rules=2 -->\n'
          '<!-- field id=a type=hologram wild=1 -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n';
      final r = parsed(text);
      expect(r.spec.rules, 2);
      expect(
        r.spec.fields,
        isEmpty,
        reason: 'new types and rules cannot be judged by an older client',
      );
      expect(codes(r.notes), ['rules-too-new']);
      expect(r.notes.single.isError, isTrue);
      expect(r.notes.single.facts, containsPair('declared', 2));
      expect(r.notes.single.facts, containsPair('supported', 1));
    });

    test('a malformed header is still malformed whatever the version', () {
      expect(
        broken('<!-- form id=f rules=9 version=x -->\n').problems.first.code,
        FormIssueCode.ruleMalformed,
      );
    });

    test('rules=1 and a missing rules are both the current semantics', () {
      expect(parsed('<!-- form id=f rules=1 -->\n').spec.rules, 1);
      expect(
        codes(parsed('<!-- form id=f -->\n').notes),
        isNot(contains('rules-too-new')),
      );
    });
  });

  group('field structure', () {
    test('an unknown type is an author error', () {
      final p = broken(one('<!-- field id=x type=hologram -->'));
      expect(p.problems.single.code, FormIssueCode.unknownType);
      expect(p.problems.single.facts, containsPair('type', 'hologram'));
      expect(p.problems.single.fieldId, 'x');
    });

    test('there is no scale type any more', () {
      expect(
        broken(one('<!-- field id=x type=scale -->')).problems.single.code,
        FormIssueCode.unknownType,
      );
    });

    test('id and type are required, and the id is a slug', () {
      for (final entry in {
        '<!-- field type=text -->': 'id',
        '<!-- field id=x -->': 'type',
      }.entries) {
        final p = broken(one(entry.key));
        expect(
          p.problems.first.code,
          FormIssueCode.markerMalformed,
          reason: entry.key,
        );
        expect(p.problems.first.facts['attribute'], entry.value);
      }
      expect(
        codes(broken(one('<!-- field id=A type=text -->', id: 'A')).problems),
        contains('marker-malformed'),
      );
    });

    test('a duplicate id is reported at the second field', () {
      final text =
          '<!-- form id=f -->\n'
          '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n'
          '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n';
      final p = broken(text);
      expect(p.problems.single.code, FormIssueCode.duplicateFieldId);
      expect(p.problems.single.line, 6);
      expect(p.problems.single.facts['first'], 2);
    });

    test('a field with no label text is allowed', () {
      final text =
          '<!-- form id=f -->\n'
          '<!-- field id=a type=text -->\n<!-- answer -->\n<!-- /field id=a -->\n';
      final a = parsed(text).spec.fieldById('a')!;
      expect(a.label.start, a.label.end);
      expect(a.zone.start, a.zone.end);
    });

    test('an answer of any size lives between answer and close', () {
      final body = List.generate(200, (i) => 'line $i').join('\n');
      final text =
          '<!-- form id=f -->\n<!-- field id=a type=prose -->\nL\n<!-- answer -->\n$body\n<!-- /field id=a -->\n';
      final a = parsed(text).spec.fieldById('a')!;
      expect(text.substring(a.zone.start, a.zone.end), '$body\n');
    });

    test('fields do not nest', () {
      final text =
          '<!-- form id=f -->\n'
          '<!-- field id=a type=text -->\nL\n'
          '<!-- field id=b type=text -->\nL\n<!-- answer -->\n<!-- /field id=b -->\n';
      final p = broken(text);
      expect(p.problems.first.code, FormIssueCode.unpairedMarker);
      expect(p.problems.first.facts['reason'], 'missing-answer-marker');
      expect(p.problems.first.fieldId, 'a');
    });

    test('an answer marker with no open field', () {
      final p = broken('<!-- form id=f -->\n<!-- answer -->\n');
      expect(p.problems.single.code, FormIssueCode.unpairedMarker);
      expect(p.problems.single.facts['reason'], 'answer-outside-field');
      expect(p.problems.single.line, 2);
    });

    test('a close marker with no open field', () {
      final p = broken('<!-- form id=f -->\n<!-- /field id=a -->\n');
      expect(p.problems.single.facts['reason'], 'close-without-open');
    });

    test('a field closed before its answer marker', () {
      final p = broken(
        '<!-- form id=f -->\n<!-- field id=a type=text -->\nL\n<!-- /field id=a -->\n',
      );
      expect(p.problems.first.facts['reason'], 'missing-answer-marker');
    });

    test('a field never closed is reported at the field, not at the end', () {
      final text =
          '<!-- form id=f -->\n<!-- field id=a type=text -->\nL\n<!-- answer -->\nsome answer\n';
      final p = broken(text);
      expect(p.problems.single.code, FormIssueCode.unpairedMarker);
      expect(p.problems.single.facts['reason'], 'unclosed-field');
      expect(p.problems.single.fieldId, 'a');
      expect(p.problems.single.line, 2);
    });

    test(
      'a close for the wrong id does not end the zone, and says what it saw',
      () {
        final text =
            '<!-- form id=f -->\n<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=b -->\n';
        final p = broken(text);
        expect(p.problems.single.facts['reason'], 'unclosed-field');
        expect(p.problems.single.facts['foundClosers'], 'b@5');
      },
    );

    test(
      'a deleted close swallows the next field into the zone and is named',
      () {
        final text =
            '<!-- form id=f -->\n'
            '<!-- field id=a type=text -->\nL\n<!-- answer -->\n'
            '<!-- field id=b type=text -->\nL\n<!-- answer -->\n<!-- /field id=b -->\n';
        final p = broken(text);
        expect(p.problems.single.fieldId, 'a');
        expect(p.problems.single.facts['reason'], 'unclosed-field');
        expect(p.problems.single.facts['markersInZone'], 3);
      },
    );
  });

  group('fences (§4.3, §4.6)', () {
    test(
      'a marker-shaped line inside a fence in template-owned text is content',
      () {
        final text =
            '<!-- form id=f -->\n```\n<!-- field id=ghost type=text -->\n```\n'
            '<!-- field id=a type=text -->\n```\n<!-- answer -->\n```\n<!-- answer -->\n<!-- /field id=a -->\n';
        final spec = parsed(text).spec;
        expect(spec.fields.map((x) => x.id), ['a']);
        final a = spec.fieldById('a')!;
        expect(
          text.substring(a.label.start, a.label.end),
          '```\n<!-- answer -->\n```\n',
          reason: 'the answer marker inside the fence is just label text',
        );
      },
    );

    test(
      'an unclosed fence in the label swallows the answer marker: structure error',
      () {
        final text =
            '<!-- form id=f -->\n<!-- field id=a type=text -->\n```\nL\n<!-- answer -->\n<!-- /field id=a -->\n';
        final p = broken(text);
        expect(p.problems.first.facts['reason'], 'missing-answer-marker');
      },
    );

    test('the zone ends at the matching close even inside a fence', () {
      final text =
          '<!-- form id=f -->\n<!-- field id=a type=prose -->\nL\n<!-- answer -->\n'
          '```\ncode\n<!-- /field id=a -->\n';
      final a = parsed(text).spec.fieldById('a')!;
      expect(text.substring(a.zone.start, a.zone.end), '```\ncode\n');
    });

    test('fences do not leak across the answer zone into the next field', () {
      final text =
          '<!-- form id=f -->\n'
          '<!-- field id=a type=prose -->\nL\n<!-- answer -->\n```\n<!-- /field id=a -->\n'
          '<!-- field id=b type=text -->\nL\n<!-- answer -->\n<!-- /field id=b -->\n';
      expect(parsed(text).spec.fields.map((x) => x.id), ['a', 'b']);
    });

    test(
      'foreign marker lines in a zone are zone text (flagged later, at validation)',
      () {
        final text =
            '<!-- form id=f -->\n<!-- field id=a type=prose -->\nL\n<!-- answer -->\n'
            'before\n<!-- notice -->\n<!-- answer -->\nafter\n<!-- /field id=a -->\n';
        final a = parsed(text).spec.fieldById('a')!;
        expect(
          text.substring(a.zone.start, a.zone.end),
          'before\n<!-- notice -->\n<!-- answer -->\nafter\n',
        );
      },
    );
  });

  group('the notice region', () {
    test('is optional (a warning, not an error)', () {
      final n = parsed(
        '<!-- form id=f controller=x contact=y retain-unused=z -->\n',
      ).notes;
      expect(codes(n), ['notice-missing']);
      expect(n.single.severity, FormSeverity.warning);
    });

    test('the controller, contact and retention are each asked for', () {
      final n = parsed('<!-- form id=f -->\n').notes;
      final missing = [
        for (final p in n)
          if (p.code == FormIssueCode.formAttributeMissing)
            p.facts['attribute'],
      ];
      expect(missing, ['controller', 'contact', 'retain-unused']);
      expect(n.every((p) => p.severity == FormSeverity.warning), isTrue);
    });

    test('must close, and does not nest with fields', () {
      expect(
        broken(
          '<!-- form id=f -->\n<!-- notice -->\ntext\n',
        ).problems.single.facts['reason'],
        'notice-not-closed',
      );
      expect(
        broken(
          '<!-- form id=f -->\n<!-- /notice -->\n',
        ).problems.single.facts['reason'],
        'close-without-open',
      );
      final p = broken(
        '<!-- form id=f -->\n<!-- notice -->\n<!-- field id=a type=text -->\n',
      );
      expect(p.problems.first.facts['reason'], 'notice-not-closed');
    });

    test('a second notice is refused', () {
      final p = broken(
        '<!-- form id=f -->\n<!-- notice -->\n<!-- /notice -->\n<!-- notice -->\n<!-- /notice -->\n',
      );
      expect(p.problems.single.code, FormIssueCode.markerMisplaced);
      expect(p.problems.single.facts['reason'], 'second-notice');
    });
  });

  group('rules on a field', () {
    ParsedForm ok(String marker) => parsed(one(marker));

    test('required is a flag, known to every type', () {
      expect(
        ok(
          '<!-- field id=x type=consent required -->',
        ).spec.fieldById('x')!.required,
        isTrue,
      );
      expect(
        ok('<!-- field id=x type=consent -->').spec.fieldById('x')!.required,
        isFalse,
      );
      expect(
        broken(
          one('<!-- field id=x type=text required=yes -->'),
        ).problems.single.facts['reason'],
        'flag-takes-no-value',
      );
    });

    test('every type of the registry parses with representative rules', () {
      for (final marker in [
        '<!-- field id=x type=text min-chars=2 max-chars=80 pattern=email -->',
        '<!-- field id=x type=prose words=..100 max-chars=2000 -->',
        '<!-- field id=x type=number min=0 max=10,5 step=0.5 -->',
        '<!-- field id=x type=date min=2026-01-01 max=2027-01-01 -->',
        '<!-- field id=x type=choice options="A|B" other -->',
        '<!-- field id=x type=multichoice options="A|B|C" count=1..2 -->',
        '<!-- field id=x type=list items=3.. ordered item-words=..12 -->',
        '<!-- field id=x type=table columns="Hoeveelheid|Ingrediënt" rows=3.. -->',
        '<!-- field id=x type=image count=0..5 min-width=2000 strict max-bytes=26214400 formats=jpg,png,heic alt credit faces=0 -->',
        '<!-- field id=x type=consent required -->',
      ]) {
        expect(ok(marker).spec.fields.single.id, 'x', reason: marker);
      }
    });

    test('rule values are stored typed and reachable by accessors', () {
      final f = ok(
        '<!-- field id=x type=image count=0..5 min-width=2000 formats=jpg,heic alt faces=1 -->',
      ).spec.fieldById('x')!;
      expect(f.range('count')!.max, 5);
      expect(f.intRule('min-width'), 2000);
      expect(f.list('formats'), ['jpg', 'heic']);
      expect(f.flag('alt'), isTrue);
      expect(f.flag('credit'), isFalse);
      expect(f.range('faces')!.min, 1);
      expect(f.intRule('max-bytes'), isNull);
    });

    test('malformed rules block publishing, each with its rule and reason', () {
      for (final entry in {
        '<!-- field id=x type=prose words=150-300 -->': ('words', 'bad-range'),
        '<!-- field id=x type=prose words=300..150 -->': ('words', 'bad-range'),
        '<!-- field id=x type=prose words=150…300 -->': ('words', 'bad-range'),
        '<!-- field id=x type=prose words -->': ('words', 'value-required'),
        '<!-- field id=x type=text max-chars=0 -->': (
          'max-chars',
          'not-a-positive-integer',
        ),
        '<!-- field id=x type=text pattern=.* -->': (
          'pattern',
          'unknown-value',
        ),
        '<!-- field id=x type=number min=0x10 -->': ('min', 'bad-number'),
        '<!-- field id=x type=date min=2026-02-30 -->': ('min', 'bad-date'),
        '<!-- field id=x type=choice options="A||B" -->': (
          'options',
          'empty-item',
        ),
        '<!-- field id=x type=choice options="A|A" -->': (
          'options',
          'duplicate-item',
        ),
        '<!-- field id=x type=image formats=gif -->': (
          'formats',
          'unknown-value',
        ),
        '<!-- field id=x type=choice other=yes options="A" -->': (
          'other',
          'flag-takes-no-value',
        ),
      }.entries) {
        final p = broken(one(entry.key));
        expect(
          p.problems.single.code,
          FormIssueCode.ruleMalformed,
          reason: entry.key,
        );
        expect(
          p.problems.single.facts['rule'],
          entry.value.$1,
          reason: entry.key,
        );
        expect(
          p.problems.single.facts['reason'],
          entry.value.$2,
          reason: entry.key,
        );
        expect(p.problems.single.fieldId, 'x');
        expect(p.problems.single.line, 2, reason: 'the field marker line');
      }
    });

    test('a missing required rule is reported', () {
      final p = broken(one('<!-- field id=x type=choice -->'));
      expect(p.problems.single.code, FormIssueCode.ruleMalformed);
      expect(p.problems.single.facts, containsPair('reason', 'missing'));
      expect(p.problems.single.facts['rule'], 'options');
      expect(
        broken(
          one('<!-- field id=x type=table -->'),
        ).problems.single.facts['rule'],
        'columns',
      );
    });

    test('contradictory rules are reported', () {
      final p = broken(
        one('<!-- field id=x type=text min-chars=9 max-chars=3 -->'),
      );
      expect(p.problems.single.facts, containsPair('rule', 'min-chars'));
      expect(
        p.problems.single.facts,
        containsPair('reason', 'exceeds-max-chars'),
      );
      expect(
        broken(
          one('<!-- field id=x type=image strict -->'),
        ).problems.single.facts['reason'],
        'requires-min-width',
      );
    });

    test('every problem of a field is reported, not just the first', () {
      final p = broken(
        one('<!-- field id=x type=prose words=bad max-chars=0 -->'),
      );
      expect(p.problems.map((x) => x.facts['rule']), ['words', 'max-chars']);
    });

    test('problems across fields are all collected', () {
      final text =
          '<!-- form id=f -->\n'
          '<!-- field id=a type=prose words=x -->\nL\n<!-- answer -->\n<!-- /field id=a -->\n'
          '<!-- field id=b type=nope -->\nL\n<!-- answer -->\n<!-- /field id=b -->\n';
      final p = broken(text);
      expect(codes(p.problems), ['rule-malformed', 'unknown-type']);
      expect(p.problems.map((x) => x.line), [2, 6]);
    });

    test(
      'an unknown rule on a known type is preserved and reported as info',
      () {
        final r = ok('<!-- field id=x type=text colour=red -->');
        expect(r.spec.fieldById('x')!.extraAttributes, {'colour': 'red'});
        final note = r.notes.singleWhere(
          (n) => n.code == FormIssueCode.unknownRule,
        );
        expect(note.fieldId, 'x');
        expect(note.facts['rule'], 'colour');
        expect(note.severity, FormSeverity.info);
      },
    );

    test('a rule of another type is unknown here, not silently applied', () {
      final r = ok('<!-- field id=x type=text words=1..2 -->');
      expect(r.spec.fieldById('x')!.range('words'), isNull);
      expect(r.spec.fieldById('x')!.extraAttributes, {'words': '1..2'});
    });

    test('the sensitive flag no longer exists: it is just an unknown rule', () {
      final r = ok('<!-- field id=x type=prose sensitive -->');
      expect(
        r.spec.fieldById('x')!.extraAttributes.containsKey('sensitive'),
        isTrue,
      );
    });
  });

  group('malformed and miscased markers', () {
    test('a malformed marker is reported with its line, never ignored', () {
      final p = broken('<!-- form id=f -->\n<!-- field id= -->\n');
      final prob = p.problems.firstWhere(
        (x) => x.code == FormIssueCode.markerMalformed,
      );
      expect(prob.line, 2);
      expect(prob.facts['reason'], 'empty-value');
      expect(prob.facts['marker'], 'field');
    });

    test('the old colon style is called out', () {
      final p = broken('<!-- form: id=f -->\n');
      expect(p.problems.first.code, FormIssueCode.markerMalformed);
      expect(p.problems.first.facts['reason'], 'punctuation-after-name');
    });

    test(
      'a miscased form marker alone is a broken form, so the typo is visible',
      () {
        final p = broken('<!-- Form id=f -->\n# Doc\n');
        expect(p.problems.single.code, FormIssueCode.unknownMarker);
        expect(p.problems.single.facts['given'], 'Form');
        expect(p.problems.single.facts['expected'], 'form');
      },
    );

    test('a miscased marker inside a real form is a warning in the notes', () {
      final text = kTemplate.replaceFirst(
        '<!-- answer -->\nSari',
        '<!-- Answer -->\n<!-- answer -->\nSari',
      );
      final r = parsed(text);
      final note = r.notes.singleWhere(
        (n) => n.code == FormIssueCode.unknownMarker,
      );
      expect(note.severity, FormSeverity.warning);
      expect(note.facts['given'], 'Answer');
    });

    test('a miscased marker in a fence is just text', () {
      final text = '$kTemplate\n```\n<!-- Field id=x -->\n```\n';
      expect(parsed(text).notes, isEmpty);
    });
  });

  group('robustness', () {
    test(
      'never throws, and every spec it returns has ordered, in-range regions',
      () {
        final pieces = [
          '<!-- form id=f -->',
          '<!-- form id=f version=1 rules=1 overview="a" -->',
          '<!-- field id=a type=text -->',
          '<!-- field id=b type=prose words=1..3 -->',
          '<!-- field id=a type=choice options="x|y" -->',
          '<!-- answer -->',
          '<!-- /field id=a -->',
          '<!-- /field id=b -->',
          '<!-- notice -->',
          '<!-- /notice -->',
          '<!-- field id= -->',
          '<!-- Field id=a -->',
          '<!-- field id=a type=text',
          '```',
          '~~~',
          '---',
          'text',
          '',
          '﻿',
          '    <!-- answer -->',
          '<!-- answer --> x',
        ];
        var seed = 20261001;
        int next() {
          seed = (seed * 1103515245 + 12345) & 0x7fffffff;
          return seed;
        }

        for (var round = 0; round < 3000; round++) {
          final n = next() % 14;
          final lines = [
            for (var i = 0; i < n; i++) pieces[next() % pieces.length],
          ];
          final eol = round.isEven ? '\n' : '\r\n';
          final text = lines.join(eol);
          final FormParseResult r;
          try {
            r = parse(text);
          } catch (e, st) {
            fail('threw on ${lines.map((l) => '"$l"').toList()}: $e\n$st');
          }
          if (r is ParsedForm) {
            var last = 0;
            for (final f in r.spec.fields) {
              expect(
                f.open.start,
                greaterThanOrEqualTo(last),
                reason: '$lines',
              );
              expect(f.open.start <= f.open.end, isTrue);
              expect(
                f.open.nextStart <= f.answer.start,
                isTrue,
                reason: '$lines',
              );
              expect(
                f.answer.nextStart <= f.close.start,
                isTrue,
                reason: '$lines',
              );
              expect(
                f.close.nextStart <= text.length,
                isTrue,
                reason: '$lines',
              );
              expect(f.label.start <= f.label.end, isTrue);
              expect(f.zone.start <= f.zone.end, isTrue);
              last = f.close.nextStart;
            }
            expect(
              r.spec.intro.start <= r.spec.intro.end,
              isTrue,
              reason: '$lines',
            );
          } else if (r is BrokenForm) {
            expect(r.problems, isNotEmpty, reason: '$lines');
          }
        }
      },
    );

    test('a few thousand fields parse quickly', () {
      final b = StringBuffer('<!-- form id=big -->\n');
      for (var i = 0; i < 5000; i++) {
        b.write(
          '<!-- field id=f$i type=text max-chars=80 -->\nLabel $i\n<!-- answer -->\nanswer\n<!-- /field id=f$i -->\n\n',
        );
      }
      final sw = Stopwatch()..start();
      final r = parsed(b.toString());
      sw.stop();
      expect(r.spec.fields.length, 5000);
      expect(sw.elapsedMilliseconds, lessThan(3000));
    });

    test('problem output is bounded however broken the input is', () {
      final text =
          '<!-- form id=f -->\n${List.filled(5000, '<!-- answer -->').join('\n')}\n';
      expect(broken(text).problems.length, lessThanOrEqualTo(100));
    });
  });
}
