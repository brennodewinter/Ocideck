import 'package:ocideck_form_core/ocideck_form_core.dart';
import 'package:test/test.dart';

const String published = '''<!-- form id=kook version=1 -->
# Inzending

<!-- field id=naam type=text required -->
**Naam**
<!-- answer -->
<!-- /field id=naam -->

<!-- field id=rol type=text -->
**Rol**
<!-- answer -->
<!-- /field id=rol -->

<!-- field id=soort type=choice options="Zoet|Hartig" -->
**Soort**
<!-- answer -->
<!-- /field id=soort -->

<!-- field id=getal type=number -->
**Getal**
<!-- answer -->
<!-- /field id=getal -->

<!-- field id=datum type=date -->
**Datum**
<!-- answer -->
<!-- /field id=datum -->

<!-- field id=dieet type=multichoice options="Vegan|Halal|Glutenvrij" -->
**Dieet**
<!-- answer -->
- [ ] Vegan
- [ ] Halal
- [ ] Glutenvrij
<!-- /field id=dieet -->

<!-- field id=verhaal type=prose -->
**Verhaal**
<!-- answer -->
<!-- /field id=verhaal -->

<!-- field id=stappen type=list ordered -->
**Stappen**
<!-- answer -->
<!-- /field id=stappen -->

<!-- field id=tabel type=table columns="Ingrediënt|Hoeveelheid" -->
**Tabel**
<!-- answer -->
<!-- /field id=tabel -->

<!-- field id=foto type=image count=0..3 -->
**Foto**
<!-- answer -->
<!-- /field id=foto -->

<!-- field id=akkoord type=consent required -->
Ik ga akkoord.
<!-- answer -->
- [ ]
<!-- /field id=akkoord -->
''';

FormSpec get spec => (parseForm(published) as ParsedForm).spec;

/// A submission: the answers of [zones] (field id → zone text) filled into the form.
FormAnswers answers(Map<String, String> zones) {
  var text = published;
  zones.forEach((id, zone) {
    text = text.replaceFirstMapped(
      RegExp(
        '(<!-- field id=$id [^>]*-->(?:(?!<!-- field)[\\s\\S])*?)<!-- answer -->\n[\\s\\S]*?<!-- /field id=$id -->',
      ),
      (m) => '${m[1]}<!-- answer -->\n$zone\n<!-- /field id=$id -->',
    );
  });
  return extractAnswers(spec, text);
}

RenderedChapter render(
  String template,
  Map<String, String> zones, {
  String sid = 'abcdefghijklmnopqrstuvwxya',
}) => renderChapter(
  template: ChapterTemplate(template),
  spec: spec,
  answers: answers(zones),
  sid: sid,
);

CompileSubmission sub(
  String sid,
  Map<String, String> zones, {
  bool withdrawn = false,
}) =>
    CompileSubmission(sid: sid, answers: answers(zones), withdrawn: withdrawn);

String sidOf(int n) => 'abcdefghijklmnopqrstuvwxy${'abcdefg'[n]}';

void main() {
  group('a chapter template', () {
    test('lists its placeholders in order of first use, once each', () {
      final t = ChapterTemplate('# {naam}\n\n{verhaal} en {naam}\n{rol}\n');
      expect(t.placeholders, ['naam', 'verhaal', 'rol']);
    });

    test('does not count what stands in a fenced block', () {
      final t = ChapterTemplate(
        '{naam}\n```\n{niets}\n```\n~~~\n{ook-niets}\n~~~\n{rol}',
      );
      expect(t.placeholders, ['naam', 'rol']);
    });

    test('names the placeholders the form does not have', () {
      final t = ChapterTemplate('{naam} {typo} {rol} {nog-een}');
      expect(t.unknownIn(spec), ['typo', 'nog-een']);
      expect(ChapterTemplate('{naam}').unknownIn(spec), isEmpty);
    });

    test('only a field id counts as a placeholder', () {
      final t = ChapterTemplate('{Naam} { naam } {1x} {x_y} {} {naam}');
      expect(t.placeholders, ['naam']);
    });
  });

  group('one chapter', () {
    test('puts a one-line answer where the placeholder is, as written', () {
      final c = render('# {naam}\n*{rol}*\n{soort} {getal} {datum}', {
        'naam': 'Sari',
        'rol': 'Kok',
        'soort': 'Zoet',
        'getal': '2,5',
        'datum': '2026-11-01',
      });
      expect(c.markdown, '# Sari\n*Kok*\nZoet 2,5 2026-11-01');
    });

    test('a long story is inserted whole, paragraphs and all', () {
      final story = List.generate(2000, (i) => 'Woord$i').join(' ');
      final c = render('{verhaal}', {
        'verhaal':
            '$story\n\nTweede alinea met *nadruk* en [een link](https://x.org).',
      });
      expect(c.markdown, startsWith(story));
      expect(
        c.markdown,
        contains(
          '\n\nTweede alinea met *nadruk* en [een link](https://x.org).',
        ),
      );
      expect(c.markdown.length, greaterThan(4096), reason: 'nothing is cut');
    });

    test(
      'Markdown in an answer stays Markdown: not escaped, not flattened',
      () {
        final c = render('{verhaal}', {
          'verhaal': '**vet** `code` _schuin_ | pijp\n- a\n- b',
        });
        expect(c.markdown, '**vet** `code` _schuin_ | pijp\n- a\n- b');
      },
    );

    test('chosen options go on one line', () {
      expect(
        render('Dieet: {dieet}', {
          'dieet': '- [x] Vegan\n- [ ] Halal\n- [x] Glutenvrij',
        }).markdown,
        'Dieet: Vegan, Glutenvrij',
      );
    });

    test('a list and a table are inserted as they are', () {
      final c = render('{stappen}\n\n{tabel}', {
        'stappen': '1. Snijd\n2. Kook',
        'tabel':
            '| Ingrediënt | Hoeveelheid |\n| --- | --- |\n| Rijst | 1 kg |',
      });
      expect(
        c.markdown,
        '1. Snijd\n2. Kook\n\n| Ingrediënt | Hoeveelheid |\n| --- | --- |\n| Rijst | 1 kg |',
      );
    });

    test('a photo gets a path of the book and its credit and description', () {
      final c = render('{foto}', {
        'foto':
            '![Rendang in de pan](images/foto-1.jpg "Foto: Sari")\n![](images/foto-2.png)\n![Klaar](images/foto-3.webp)',
      });
      expect(
        c.markdown,
        '![Rendang in de pan](images/abcdefghijklmnopqrstuvwxya-foto-1.jpg "Foto: Sari")\n\n'
        '![](images/abcdefghijklmnopqrstuvwxya-foto-2.png)\n\n'
        '![Klaar](images/abcdefghijklmnopqrstuvwxya-foto-3.webp)',
      );
      expect(
        c.images.map((i) => (i.from, i.to, i.alt, i.credit, i.fieldId, i.sid)),
        [
          (
            'images/foto-1.jpg',
            'images/abcdefghijklmnopqrstuvwxya-foto-1.jpg',
            'Rendang in de pan',
            'Foto: Sari',
            'foto',
            'abcdefghijklmnopqrstuvwxya',
          ),
          (
            'images/foto-2.png',
            'images/abcdefghijklmnopqrstuvwxya-foto-2.png',
            '',
            null,
            'foto',
            'abcdefghijklmnopqrstuvwxya',
          ),
          (
            'images/foto-3.webp',
            'images/abcdefghijklmnopqrstuvwxya-foto-3.webp',
            'Klaar',
            null,
            'foto',
            'abcdefghijklmnopqrstuvwxya',
          ),
        ],
      );
    });

    test('a photo of one submission never takes the name of another', () {
      final a = render('{foto}', {
        'foto': '![](images/foto-1.jpg)',
      }, sid: sidOf(0));
      final b = render('{foto}', {
        'foto': '![](images/foto-1.jpg)',
      }, sid: sidOf(1));
      expect(a.images.single.to, isNot(b.images.single.to));
    });

    test('the consent is not text for a book', () {
      final c = render('# {naam}\n{akkoord}\nEinde', {
        'naam': 'Sari',
        'akkoord': '- [x]',
      });
      expect(c.markdown, '# Sari\nEinde');
    });

    test('an answer that is not there is empty, not a crash', () {
      final c = renderChapter(
        template: ChapterTemplate('# {naam}\n{rol}'),
        spec: spec,
        answers: const FormAnswers({}, []),
        sid: sidOf(0),
      );
      expect(c.markdown, '');
    });

    test('a CRLF template comes out with LF and no trailing blank lines', () {
      expect(
        render('# {naam}\r\n\r\n{rol}\r\n\r\n\r\n', {
          'naam': 'Sari',
          'rol': 'Kok',
        }).markdown,
        '# Sari\n\nKok',
      );
    });
  });

  group('empty lines', () {
    test('a line of nothing but empty placeholders is dropped', () {
      final c = render('# {naam}\n{rol}\n{rol} {soort}\nEinde', {
        'naam': 'Sari',
      });
      expect(c.markdown, '# Sari\nEinde');
    });

    test('so is a line that would leave only markup behind', () {
      for (final line in [
        '## {rol}',
        '*{rol}*',
        '**{rol}**',
        '_{rol}_',
        '- {rol}',
        '> {rol}',
        '1. {rol}'.replaceFirst('1.', '+'),
      ]) {
        expect(render('A\n$line\nB', {}).markdown, 'A\nB', reason: line);
      }
    });

    test('a line with words of its own keeps them', () {
      expect(render('Rol: {rol}\nA', {}).markdown, 'Rol: \nA');
      expect(
        render('*{naam} — {rol}*', {'naam': 'Sari'}).markdown,
        '*Sari — *',
      );
    });

    test('a line with one filled placeholder is kept and filled', () {
      expect(render('{naam} {rol}', {'rol': 'Kok'}).markdown, ' Kok');
    });

    test('a blank line in the template is a blank line in the chapter', () {
      expect(
        render('{naam}\n\n{rol}', {'naam': 'A', 'rol': 'B'}).markdown,
        'A\n\nB',
      );
    });

    test('a line without placeholders is never dropped', () {
      expect(render('---\n***\n> \n#', {}).markdown, '---\n***\n> \n#');
    });
  });

  group('code fences', () {
    test(
      'an answer that leaves a fence open is closed, so it cannot swallow what follows',
      () {
        final c = render('{verhaal}\n\nVolgende alinea', {
          'verhaal': 'tekst\n```\ncode zonder einde',
        });
        expect(
          c.markdown,
          'tekst\n```\ncode zonder einde\n```\n\nVolgende alinea',
        );
      },
    );

    test('with tildes too', () {
      final c = render('{verhaal}\nEinde', {'verhaal': '~~~\nx'});
      expect(c.markdown, '~~~\nx\n~~~\nEinde');
    });

    test('a balanced fence is left alone', () {
      final c = render('{verhaal}', {'verhaal': '```\ncode\n```\nna'});
      expect(c.markdown, '```\ncode\n```\nna');
    });

    test('a fence indented up to three spaces is a fence', () {
      final c = render('{naam}\n  ```\n  {naam}\n  ```\n{rol}', {
        'naam': 'Sari',
        'rol': 'Kok',
      });
      expect(c.markdown, 'Sari\n  ```\n  {naam}\n  ```\nKok');
      final open = render('{verhaal}', {'verhaal': 'tekst\n   ```\nx'});
      expect(open.markdown, 'tekst\n   ```\nx\n```');
    });

    test('a fence of the other kind inside a fence does not close it', () {
      final c = render('{verhaal}', {'verhaal': '```\n~~~\nx'});
      expect(c.markdown, '```\n~~~\nx\n```');
    });

    test('the template\'s own fences and what is in them stay as they are', () {
      final c = render('{naam}\n```\n{naam}\n```\n{rol}', {
        'naam': 'Sari',
        'rol': 'Kok',
      });
      expect(c.markdown, 'Sari\n```\n{naam}\n```\nKok');
    });
  });

  group('the book', () {
    const template = '# {naam}\n*{rol}*\n{verhaal}';

    BookCompiled book(
      List<CompileSubmission> subs, {
      String? orderBy,
      String? groupBy,
      String t = template,
    }) =>
        compileBook(
              template: ChapterTemplate(t),
              spec: spec,
              submissions: subs,
              orderBy: orderBy,
              groupBy: groupBy,
            )
            as BookCompiled;

    test('joins the chapters with a blank line and ends with one newline', () {
      final b = book([
        sub(sidOf(0), {'naam': 'A', 'verhaal': 'x'}),
        sub(sidOf(1), {'naam': 'B', 'verhaal': 'y'}),
      ]);
      expect(b.markdown, '# A\nx\n\n# B\ny\n');
      expect(b.included, [sidOf(0), sidOf(1)]);
      expect(b.withdrawn, isEmpty);
    });

    test('an unknown placeholder refuses the whole book, naming it', () {
      final r = compileBook(
        template: ChapterTemplate('{naam} {fout}'),
        spec: spec,
        submissions: [
          sub(sidOf(0), {'naam': 'A'}),
        ],
      );
      expect(r, isA<BookRefused>());
      expect((r as BookRefused).unknown, ['fout']);
    });

    test('a withdrawn submission is never in the book, and is said', () {
      final b = book([
        sub(sidOf(0), {'naam': 'A'}),
        sub(sidOf(1), {'naam': 'B'}, withdrawn: true),
        sub(sidOf(2), {'naam': 'C'}),
      ]);
      expect(b.included, [sidOf(0), sidOf(2)]);
      expect(b.withdrawn, [sidOf(1)]);
      expect(b.markdown, isNot(contains('# B')));
    });

    test('a withdrawn submission leaves no photos behind either', () {
      final b = book([
        sub(sidOf(0), {'naam': 'A', 'foto': '![](images/foto-1.jpg)'}),
        sub(sidOf(1), {
          'naam': 'B',
          'foto': '![](images/foto-1.jpg)',
        }, withdrawn: true),
      ], t: '# {naam}\n{foto}');
      expect(b.images.map((i) => i.sid), [sidOf(0)]);
    });

    test('orders by one field, as lower-case text, an empty value last', () {
      final b = book([
        sub(sidOf(0), {'naam': 'Zoë'}),
        sub(sidOf(1), {}),
        sub(sidOf(2), {'naam': 'adi'}),
        sub(sidOf(3), {'naam': 'Beer'}),
      ], orderBy: 'naam');
      expect(b.included, [sidOf(2), sidOf(3), sidOf(0), sidOf(1)]);
    });

    test('a tie keeps the order the submissions came in', () {
      final b = book([
        sub(sidOf(0), {'naam': 'A', 'rol': 'x'}),
        sub(sidOf(1), {'naam': 'B', 'rol': 'x'}),
        sub(sidOf(2), {'naam': 'C', 'rol': 'x'}),
      ], orderBy: 'rol');
      expect(b.included, [sidOf(0), sidOf(1), sidOf(2)]);
    });

    test(
      'a long list of ties keeps its order too (a sort is not stable by itself)',
      () {
        final subs = [
          for (var i = 0; i < 100; i++)
            CompileSubmission(sid: 'sid$i', answers: answers({'rol': 'x'})),
        ];
        final b = book(subs, orderBy: 'rol');
        expect(b.included, [for (var i = 0; i < 100; i++) 'sid$i']);
      },
    );

    test('orders by the chosen options of a multiple choice', () {
      final b = book([
        sub(sidOf(0), {
          'naam': 'A',
          'dieet': '- [x] Vegan\n- [ ] Halal\n- [ ] Glutenvrij',
        }),
        sub(sidOf(1), {
          'naam': 'B',
          'dieet': '- [ ] Vegan\n- [ ] Halal\n- [x] Glutenvrij',
        }),
        sub(sidOf(2), {
          'naam': 'C',
          'dieet': '- [ ] Vegan\n- [x] Halal\n- [ ] Glutenvrij',
        }),
      ], orderBy: 'dieet');
      expect(b.included, [sidOf(1), sidOf(2), sidOf(0)]);
    });

    test('without an order the register\'s order stands', () {
      final b = book([
        sub(sidOf(0), {'naam': 'Z'}),
        sub(sidOf(1), {'naam': 'A'}),
      ]);
      expect(b.included, [sidOf(0), sidOf(1)]);
    });

    test('an order by something that is no field is not an order', () {
      final b = book([
        sub(sidOf(0), {'naam': 'Z'}),
        sub(sidOf(1), {'naam': 'A'}),
      ], orderBy: 'bestaatniet');
      expect(b.included, [sidOf(0), sidOf(1)]);
    });

    test('groups by a field: a heading before each run', () {
      final b = book(
        [
          sub(sidOf(0), {'naam': 'A', 'soort': 'Zoet'}),
          sub(sidOf(1), {'naam': 'B', 'soort': 'Hartig'}),
          sub(sidOf(2), {'naam': 'C', 'soort': 'Zoet'}),
        ],
        orderBy: 'soort',
        groupBy: 'soort',
        t: '# {naam}',
      );
      expect(b.markdown, '## Hartig\n\n# B\n\n## Zoet\n\n# A\n\n# C\n');
    });

    test(
      'a submission with no value for the group gets no heading, and a later group still does',
      () {
        final b = book(
          [
            sub(sidOf(0), {'naam': 'A', 'soort': 'Zoet'}),
            sub(sidOf(1), {'naam': 'B'}),
            sub(sidOf(2), {'naam': 'C', 'soort': 'Zoet'}),
          ],
          groupBy: 'soort',
          t: '# {naam}',
        );
        expect(b.markdown, '## Zoet\n\n# A\n\n# B\n\n## Zoet\n\n# C\n');
      },
    );

    test('a group by something that is no field is not a grouping', () {
      final b = book(
        [
          sub(sidOf(0), {'naam': 'A'}),
        ],
        groupBy: 'bestaatniet',
        t: '# {naam}',
      );
      expect(b.markdown, '# A\n');
    });

    test('no submissions, no book', () {
      final b = book(const []);
      expect(b.markdown, '');
      expect(b.included, isEmpty);
    });

    test(
      'a book is made of chapters, each chapter a string, and nothing is evaluated',
      () {
        final b = book([
          sub(sidOf(0), {'naam': r'$1 ${rol} {naam} \n'}),
        ], t: '{naam}');
        expect(
          b.markdown,
          r'$1 ${rol} {naam} \n'
          '\n',
        );
      },
    );
  });
}
