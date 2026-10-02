import 'dart:typed_data';

import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

import 'support/image_fixtures.dart';
import 'support/manifest_fixtures.dart';

const String published =
    '''<!-- form id=kook version=1 overview="naam,soort,diensten" -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=soort type=choice options="Zoet|Hartig" -->
**Soort**
<!-- answer -->
<!-- /field id=soort -->

<!-- field id=diensten type=multichoice options="Vegan|Halal|Glutenvrij" -->
**Diensten**
<!-- answer -->
- [ ] Vegan
- [ ] Halal
- [ ] Glutenvrij
<!-- /field id=diensten -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->
''';

FormSpec specOf(String text) => (parseForm(text) as ParsedForm).spec;

String fill({
  String naam = 'Sari',
  String? soort = 'Zoet',
  List<String> diensten = const ['Vegan', 'Halal'],
  bool akkoord = true,
  String from = published,
}) {
  var text = from
      .replaceFirst(
        '<!-- answer -->\n<!-- /field id=naam -->',
        '<!-- answer -->\n$naam\n<!-- /field id=naam -->',
      )
      .replaceFirst(
        '<!-- answer -->\n<!-- /field id=soort -->',
        '<!-- answer -->\n${soort ?? ''}\n<!-- /field id=soort -->',
      );
  for (final d in ['Vegan', 'Halal', 'Glutenvrij']) {
    if (diensten.contains(d)) text = text.replaceFirst('- [ ] $d', '- [x] $d');
  }
  return text.replaceFirst(
    '- [ ]\n<!-- /field id=akkoord',
    akkoord ? '- [x]\n<!-- /field id=akkoord' : '- [ ]\n<!-- /field id=akkoord',
  );
}

String sidOf(int n) => 'abcdefghijklmnopqrstuvwxy${'abcdefg'[n]}';

FormReview reviewOf({
  String? submission,
  int n = 0,
  String from = published,
  DateTime? created,
  Map<String, Uint8List> images = const {},
}) {
  final bytes = buildFormPackage(
    submission: submission ?? fill(from: from),
    template: from,
    spec: specOf(from),
    images: images,
    submissionId: sidOf(n),
    created: created ?? DateTime.utc(2026, 10, 4),
    clientRules: kFormRulesVersion,
  );
  return reviewFormPackage(readFormPackage(bytes) as FormPackageOpened, [from]);
}

FormRegister emptyRegister([String from = published]) =>
    FormRegister.empty(specOf(from));

FormRegister parsed(String markdown) =>
    (FormRegister.parse(markdown) as FormRegisterParsed).register;

FormRegisterDamaged damaged(String markdown) =>
    FormRegister.parse(markdown) as FormRegisterDamaged;

void main() {
  group('an empty register', () {
    test('has the columns of the form, then the fixed ones', () {
      expect(emptyRegister().columns, [
        'sid',
        'naam',
        'soort',
        'diensten',
        'received',
        'status',
        'consent',
        'withdrawn',
        'delete-after',
      ]);
      expect(
        emptyRegister().toMarkdown(),
        '''| sid | naam | soort | diensten | received | status | consent | withdrawn | delete-after |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
''',
      );
    });

    test('reads back as itself', () {
      final again = parsed(emptyRegister().toMarkdown());
      expect(again.columns, emptyRegister().columns);
      expect(again.rows, isEmpty);
      expect(again.toMarkdown(), emptyRegister().toMarkdown());
    });

    test('a form with no overview has only the fixed columns', () {
      final plain = published.replaceFirst(
        ' overview="naam,soort,diensten"',
        '',
      );
      expect(emptyRegister(plain).columns, [
        'sid',
        'received',
        'status',
        'consent',
        'withdrawn',
        'delete-after',
      ]);
    });
  });

  group('a submission enters the register', () {
    test('as a row of what the organiser needs to see', () {
      final register = emptyRegister().withSubmission(
        reviewOf(),
        received: '2026-10-05',
      )!;
      final row = register.rows.single;
      expect(row.sid, sidOf(0));
      expect(row.valueOf('naam'), 'Sari');
      expect(row.valueOf('soort'), 'Zoet');
      expect(row.valueOf('diensten'), 'Vegan, Halal');
      expect(row.received, '2026-10-05');
      expect(row.status, 'received');
      expect(row.consent, '2026-10-04');
      expect(row.withdrawn, isEmpty);
      expect(row.deleteAfter, isEmpty);
      expect(row.isWithdrawn, isFalse);
      expect(row.isDeleted, isFalse);
    });

    test('in the first state the form names', () {
      final named = published.replaceFirst(
        'overview="naam,soort,diensten"',
        'overview="naam,soort,diensten" states="nieuw|klaar"',
      );
      final register = emptyRegister(
        named,
      ).withSubmission(reviewOf(from: named), received: '2026-10-05')!;
      expect(register.rows.single.status, 'nieuw');
    });

    test('as needs-fixing when the review found an error', () {
      final register = emptyRegister().withSubmission(
        reviewOf(submission: fill(naam: '')),
        received: 'd',
      )!;
      expect(register.rows.single.status, kFormStateNeedsFixing);
      expect(register.rows.single.valueOf('naam'), isEmpty);
      expect(register.rows.single.sid, sidOf(0));
    });

    test('and from there an editor moves it to a state of the form', () {
      final fixing = emptyRegister().withSubmission(
        reviewOf(submission: fill(naam: '')),
        received: 'd',
      )!;
      final moved = fixing.withStatus(sidOf(0), 'edited', kDefaultFormStates)!;
      expect(moved.rows.single.status, 'edited');
    });

    test('a warning alone is not an error', () {
      final photo = published.replaceFirst(
        '<!-- field id=akkoord',
        '<!-- field id=foto type=image count=0..2 min-width=2000 -->\n**Foto**\n<!-- answer -->\n<!-- /field id=foto -->\n\n<!-- field id=akkoord',
      );
      final submission = fill(from: photo).replaceFirst(
        '<!-- answer -->\n<!-- /field id=foto',
        '<!-- answer -->\n![](images/foto-1.jpg)\n<!-- /field id=foto',
      );
      final review = reviewOf(
        from: photo,
        submission: submission,
        images: {'images/foto-1.jpg': jpegClean(width: 640)},
      );
      expect(review.problems.map((p) => p.code), [FormIssueCode.imageTooSmall]);
      final register = emptyRegister(
        photo,
      ).withSubmission(review, received: 'd')!;
      expect(register.rows.single.status, 'received');
    });

    test('with the reminder it is given', () {
      final register = emptyRegister().withSubmission(
        reviewOf(),
        received: '2026-10-05',
        deleteAfter: '2027-04-30',
      )!;
      expect(register.rows.single.deleteAfter, '2027-04-30');
    });

    test('never twice, and never over an existing row', () {
      final once = emptyRegister().withSubmission(reviewOf(), received: 'a')!;
      expect(once.withSubmission(reviewOf(), received: 'b'), isNull);
      expect(once.rows.single.received, 'a');
    });

    test('in the order they arrive', () {
      var register = emptyRegister();
      for (var n = 0; n < 3; n++) {
        register = register.withSubmission(reviewOf(n: n), received: 'd')!;
      }
      expect(
        [for (final r in register.rows) r.sid],
        [sidOf(0), sidOf(1), sidOf(2)],
      );
    });

    test('not when the form was not known', () {
      final unknown = reviewFormPackage(
        (readFormPackage(
              buildFormPackage(
                submission: fill(),
                template: published,
                spec: specOf(published),
                images: const {},
                submissionId: sidOf(0),
                created: DateTime.utc(2026, 10, 4),
                clientRules: kFormRulesVersion,
              ),
            )
            as FormPackageOpened),
        const [],
      );
      expect(emptyRegister().withSubmission(unknown, received: 'd'), isNull);
    });

    test('the consent day is the one the manifest records', () {
      final honest =
          readFormPackage(
                buildFormPackage(
                  submission: fill(),
                  template: published,
                  spec: specOf(published),
                  images: const {},
                  submissionId: sidOf(0),
                  created: DateTime.utc(2026, 10, 4),
                  clientRules: kFormRulesVersion,
                ),
              )
              as FormPackageOpened;
      final consent = honest.manifest.consent.single;
      final other = withManifest(
        honest,
        consent: [
          FormManifestConsent(consent.field, '2026-09-30', consent.textSha256),
        ],
      );
      final review = reviewFormPackage(other, [published]);
      expect(review.problems, isEmpty);
      final register = emptyRegister().withSubmission(review, received: 'd')!;
      expect(register.rows.single.consent, '2026-09-30');
    });

    test('with no consent field, no consent day', () {
      final without = published.replaceAll(
        RegExp(
          r'<!-- field id=akkoord.*?/field id=akkoord -->\n',
          dotAll: true,
        ),
        '',
      );
      final register = emptyRegister(without).withSubmission(
        reviewOf(
          from: without,
          submission: fill(from: without),
        ),
        received: 'd',
      )!;
      expect(register.rows.single.consent, isEmpty);
    });

    test('a long answer shows its first line', () {
      final story = published
          .replaceFirst(
            'overview="naam,soort,diensten"',
            'overview="naam,verhaal"',
          )
          .replaceFirst(
            '<!-- field id=akkoord',
            '<!-- field id=verhaal type=prose -->\n**Verhaal**\n<!-- answer -->\n<!-- /field id=verhaal -->\n\n<!-- field id=akkoord',
          );
      final submission = fill(from: story).replaceFirst(
        '<!-- answer -->\n<!-- /field id=verhaal',
        '<!-- answer -->\nEerste regel\n\nTweede alinea\n<!-- /field id=verhaal',
      );
      final register = emptyRegister(story).withSubmission(
        reviewOf(from: story, submission: submission),
        received: 'd',
      )!;
      expect(register.rows.single.valueOf('verhaal'), 'Eerste regel');
    });

    test('an unanswered overview field is an empty cell', () {
      final register = emptyRegister().withSubmission(
        reviewOf(submission: fill(soort: null, diensten: const [])),
        received: 'd',
      )!;
      expect(register.rows.single.valueOf('soort'), isEmpty);
      expect(register.rows.single.valueOf('diensten'), isEmpty);
    });

    test('adds the overview columns an older register lacks', () {
      final old = parsed(
        '''| sid | received | status | consent | withdrawn | delete-after |
| --- | --- | --- | --- | --- | --- |
| ${sidOf(1)} | 2026-10-01 | received |  |  |  |
''',
      );
      final register = old.withSubmission(reviewOf(), received: 'd')!;
      expect(register.columns.sublist(0, 4), [
        'sid',
        'naam',
        'soort',
        'diensten',
      ]);
      expect(register.row(sidOf(1))!.valueOf('naam'), isEmpty);
      expect(register.row(sidOf(0))!.valueOf('naam'), 'Sari');
    });
  });

  group('what an answer cannot do to the table', () {
    String rowAfter(String naam) => emptyRegister()
        .withSubmission(
          reviewOf(submission: fill(naam: naam)),
          received: 'd',
        )!
        .toMarkdown();

    test('a pipe does not split the cell', () {
      final markdown = rowAfter('Sari | Joe');
      expect(markdown, contains(r'Sari \| Joe'));
      expect(parsed(markdown).rows.single.valueOf('naam'), 'Sari | Joe');
    });

    test(
      'every character Markdown reads is escaped, and read back as it was',
      () {
        const value = r'a\b `c` *d* _e_ [f](http://x.y) <g> !h &i #j ~k';
        final markdown = rowAfter(value);
        expect(markdown, isNot(contains('[f]')));
        expect(markdown, isNot(contains('<g>')));
        expect(markdown, isNot(contains('`c`')));
        expect(parsed(markdown).rows.single.valueOf('naam'), value);
      },
    );

    test('a link or an image in an answer is text in the register', () {
      final markdown = rowAfter('![x](https://spy.example/p.png)');
      expect(markdown, contains(r'\!\[x\]'));
      expect(
        parsed(markdown).rows.single.valueOf('naam'),
        '![x](https://spy.example/p.png)',
      );
    });
  });

  group('reading it back', () {
    test('round-trips, text around the table included', () {
      final register = emptyRegister().withSubmission(
        reviewOf(),
        received: '2026-10-05',
      )!;
      final markdown =
          'Mijn aantekeningen.\n\n${register.toMarkdown()}\nNa de tabel.\n';
      final again = parsed(markdown);
      expect(again.toMarkdown(), markdown);
      expect(again.rows.single.sid, sidOf(0));
    });

    test(
      'accepts hand edits: padding, no outer pipes at the end, other order',
      () {
        final again = parsed(
          '''|status|sid|received|consent|withdrawn|delete-after|notitie|
|:--|--:|---|---|---|---|---|
|  edited  |  ${sidOf(2)}  | 2026-10-01 | | 2026-10-02 | | in de gaten houden
''',
        );
        final row = again.rows.single;
        expect(row.status, 'edited');
        expect(row.sid, sidOf(2));
        expect(row.withdrawn, '2026-10-02');
        expect(row.valueOf('notitie'), 'in de gaten houden');
        expect(again.columns.first, 'status');
      },
    );

    test('a column name with a pipe in it survives', () {
      final base = parsed(
        '''| sid | no\\|tie | received | status | consent | withdrawn | delete-after |
| --- | --- | --- | --- | --- | --- | --- |
| ${sidOf(0)} | x | d | received |  |  |  |
''',
      );
      expect(base.columns[1], 'no|tie');
      expect(base.row(sidOf(0))!.valueOf('no|tie'), 'x');
      expect(parsed(base.toMarkdown()).columns[1], 'no|tie');
    });

    test('a backslash before a letter is a backslash', () {
      final again = parsed(
        '''| sid | notitie | received | status | consent | withdrawn | delete-after |
| --- | --- | --- | --- | --- | --- | --- |
| ${sidOf(0)} | C:\\temp\\bestand | d | received |  |  |  |
''',
      );
      expect(again.row(sidOf(0))!.valueOf('notitie'), r'C:\temp\bestand');
    });

    test('line endings are normalised to LF', () {
      final text = emptyRegister().toMarkdown().replaceAll('\n', '\r\n');
      expect(parsed(text).toMarkdown(), isNot(contains('\r')));
    });

    test('a column a person added is kept through a change', () {
      final base = parsed(
        '''| sid | received | status | consent | withdrawn | delete-after | notitie |
| --- | --- | --- | --- | --- | --- | --- |
| ${sidOf(0)} | d | received |  |  |  | bellen |
''',
      );
      final changed = base.withStatus(sidOf(0), 'edited', kDefaultFormStates)!;
      expect(changed.row(sidOf(0))!.valueOf('notitie'), 'bellen');
      expect(changed.toMarkdown(), contains('bellen'));
    });
  });

  group('a register that cannot be read is damaged, never rewritten', () {
    final header =
        '| sid | received | status | consent | withdrawn | delete-after |\n| --- | --- | --- | --- | --- | --- |\n';
    final good = '| ${sidOf(0)} | d | received |  |  |  |\n';

    test('no table at all', () {
      expect(damaged('Alleen tekst.\n').reason, 'no table');
      expect(damaged('').reason, 'no table');
    });

    test('no delimiter row', () {
      final d = damaged('| sid | status |\n| a | b |\n');
      expect(d.reason, 'no delimiter row');
      expect(d.line, 2);
      expect(damaged('| sid | status |').reason, 'no delimiter row');
    });

    test('a delimiter row needs its pipe like any row of the table', () {
      expect(
        damaged('| sid | status |\n--- | ---\n').reason,
        'no delimiter row',
      );
    });

    test('a missing fixed column, each of them', () {
      for (final name in [
        'sid',
        'received',
        'status',
        'consent',
        'withdrawn',
        'delete-after',
      ]) {
        final cols = [
          for (final c in [
            'sid',
            'received',
            'status',
            'consent',
            'withdrawn',
            'delete-after',
          ])
            if (c != name) c,
        ];
        final text =
            '| ${cols.join(' | ')} |\n| ${cols.map((_) => '---').join(' | ')} |\n';
        final d = damaged(text);
        expect(d.reason, 'no "$name" column');
        expect(d.line, 1);
      }
    });

    test('a column twice', () {
      final d = damaged(
        header
            .replaceFirst('| delete-after |', '| delete-after | sid |')
            .replaceFirst('| --- |\n', '| --- | --- |\n'),
      );
      expect(d.reason, 'a column twice');
    });

    test('a row with the wrong number of cells', () {
      final d = damaged('$header$good| ${sidOf(1)} | d | received |\n');
      expect(d.reason, 'wrong number of cells');
      expect(d.line, 4);
    });

    test('an id outside the grammar', () {
      final d = damaged('$header| nope | d | received |  |  |  |\n');
      expect(d.reason, 'not a submission id');
      expect(d.line, 3);
    });

    test('an id twice', () {
      final d = damaged('$header$good$good');
      expect(d.reason, 'a submission twice');
      expect(d.line, 4);
    });

    test('says why, in a line for a log', () {
      expect(damaged('Alleen tekst.\n').toString(), 'no table');
      expect(
        damaged('$header| nope | d | received |  |  |  |\n').toString(),
        'not a submission id (line 3)',
      );
    });
  });

  group('changing a row', () {
    FormRegister two() {
      var register = emptyRegister();
      for (var n = 0; n < 2; n++) {
        register = register.withSubmission(reviewOf(n: n), received: 'd')!;
      }
      return register;
    }

    test('a status from the closed list', () {
      final next = two().withStatus(sidOf(1), 'edited', kDefaultFormStates)!;
      expect(next.row(sidOf(1))!.status, 'edited');
      expect(next.row(sidOf(0))!.status, 'received');
      expect(next.row(sidOf(1))!.valueOf('naam'), 'Sari');
    });

    test('not one outside it, not for a row that is not there', () {
      expect(two().withStatus(sidOf(0), 'bijna', kDefaultFormStates), isNull);
      expect(two().withStatus(sidOf(6), 'edited', kDefaultFormStates), isNull);
    });

    test('not for a submission that was deleted', () {
      final gone = two().withDeletion(sidOf(0))!;
      expect(gone.withStatus(sidOf(0), 'edited', kDefaultFormStates), isNull);
    });

    test('a withdrawal is a day on the row', () {
      final next = two().withWithdrawal(sidOf(0), '2026-11-02')!;
      expect(next.row(sidOf(0))!.withdrawn, '2026-11-02');
      expect(next.row(sidOf(0))!.isWithdrawn, isTrue);
      expect(next.row(sidOf(1))!.isWithdrawn, isFalse);
      expect(two().withWithdrawal(sidOf(6), '2026-11-02'), isNull);
    });

    test('a withdrawal survives deletion', () {
      final next = two()
          .withWithdrawal(sidOf(0), '2026-11-02')!
          .withDeletion(sidOf(0))!;
      expect(next.row(sidOf(0))!.withdrawn, '2026-11-02');
    });
  });

  group('deleting leaves the minimal record', () {
    final withReminder = emptyRegister().withSubmission(
      reviewOf(),
      received: '2026-10-05',
      deleteAfter: '2027-04-30',
    )!;

    test('the id, the days and the state stay; the person goes', () {
      final row = withReminder.withDeletion(sidOf(0))!.row(sidOf(0))!;
      expect(row.isDeleted, isTrue);
      expect(row.status, kFormStateDeleted);
      expect(row.sid, sidOf(0));
      expect(row.received, '2026-10-05');
      expect(row.consent, '2026-10-04');
      expect(row.valueOf('naam'), isEmpty);
      expect(row.valueOf('soort'), isEmpty);
      expect(row.valueOf('diensten'), isEmpty);
      expect(row.deleteAfter, isEmpty);
    });

    test('what the form declared up front stays', () {
      final row = withReminder
          .withDeletion(sidOf(0), keep: ['naam'])!
          .row(sidOf(0))!;
      expect(row.valueOf('naam'), 'Sari');
      expect(row.valueOf('soort'), isEmpty);
    });

    test('a column a person added is emptied too: it may hold a person', () {
      final base = parsed(
        '''| sid | received | status | consent | withdrawn | delete-after | notitie |
| --- | --- | --- | --- | --- | --- | --- |
| ${sidOf(0)} | d | received |  |  |  | belde haar moeder |
''',
      );
      expect(
        base.withDeletion(sidOf(0))!.row(sidOf(0))!.valueOf('notitie'),
        isEmpty,
      );
    });

    test('the other rows are left alone', () {
      var register = withReminder.withSubmission(
        reviewOf(n: 1),
        received: 'd',
      )!;
      register = register.withDeletion(sidOf(0))!;
      expect(register.row(sidOf(1))!.valueOf('naam'), 'Sari');
      expect(register.withDeletion(sidOf(6)), isNull);
    });
  });

  group('the overview of a form', () {
    test('only adds, before the received column', () {
      final base = parsed(
        '''| sid | notitie | received | status | consent | withdrawn | delete-after |
| --- | --- | --- | --- | --- | --- | --- |
| ${sidOf(0)} | bellen | d | received |  |  |  |
''',
      );
      final next = base.withOverviewOf(specOf(published));
      expect(next.columns, [
        'sid',
        'notitie',
        'naam',
        'soort',
        'diensten',
        'received',
        'status',
        'consent',
        'withdrawn',
        'delete-after',
      ]);
      expect(next.row(sidOf(0))!.valueOf('notitie'), 'bellen');
      expect(next.withOverviewOf(specOf(published)), same(next));
    });

    test('a form that drops a column leaves it where it is', () {
      final next = emptyRegister().withOverviewOf(
        specOf(
          published.replaceFirst(
            'overview="naam,soort,diensten"',
            'overview="naam"',
          ),
        ),
      );
      expect(next.columns, contains('soort'));
    });
  });

  group('states', () {
    test('are the default, or the ones the form names', () {
      expect(formStatesOf(specOf(published)), kDefaultFormStates);
      expect(
        formStatesOf(
          specOf(published.replaceFirst('version=1', 'version=1 states="a|b"')),
        ),
        ['a', 'b'],
      );
    });
  });
}
