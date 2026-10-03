import 'package:ocideck_form_core/src/form_answers.dart';
import 'package:ocideck_form_core/src/form_issue.dart';
import 'package:ocideck_form_core/src/form_parser.dart';
import 'package:ocideck_form_core/src/form_spec.dart';
import 'package:test/test.dart';

/// The spec of a one-field form, so a test can say which field it needs.
FormFieldSpec fieldOf(String marker) {
  final r = parseForm(
    '<!-- form id=f -->\n$marker\nL\n<!-- answer -->\n<!-- /field id=x -->\n',
  );
  expect(r, isA<ParsedForm>(), reason: r is BrokenForm ? '${r.problems}' : '');
  return (r as ParsedForm).spec.fieldById('x')!;
}

FormAnswer read(String marker, String zone, {int firstLine = 1}) =>
    parseAnswer(fieldOf(marker), zone, firstLine: firstLine);

List<String> shape(FormAnswer a) => [
  for (final p in a.shape) '${p.facts['reason']}',
];

void main() {
  group('text, number, date', () {
    test('a single line, trimmed', () {
      final a = read('<!-- field id=x type=text -->', '  Sari Voorbeeld  \n');
      expect(a.text, 'Sari Voorbeeld');
      expect(a.isEmpty, isFalse);
      expect(a.shape, isEmpty);
    });

    test('blank means empty, whatever the blanks', () {
      for (final zone in ['', '\n', '  \n\t\n', '\r\n']) {
        final a = read('<!-- field id=x type=text -->', zone);
        expect(a.isEmpty, isTrue, reason: '"$zone"');
        expect(a.text, '');
      }
    });

    test('more than one non-blank line is not one line', () {
      for (final type in ['text', 'number', 'date']) {
        final a = read('<!-- field id=x type=$type -->', 'een\ntwee');
        expect(shape(a), ['one-line'], reason: type);
        expect(a.shape.single.code, FormIssueCode.answerMalformed);
      }
    });

    test('blank lines around one line are fine', () {
      expect(
        read('<!-- field id=x type=number -->', '\n\n25\n\n').shape,
        isEmpty,
      );
    });

    test('number and date keep their text untouched', () {
      expect(read('<!-- field id=x type=number -->', '2,5').text, '2,5');
      expect(
        read('<!-- field id=x type=date -->', '2026-11-01').text,
        '2026-11-01',
      );
    });

    test('CRLF is handled like LF', () {
      final a = read('<!-- field id=x type=text -->', 'abc\r\n');
      expect(a.text, 'abc');
      expect(a.shape, isEmpty);
    });
  });

  group('prose', () {
    test('the trimmed text, however many paragraphs', () {
      final a = read('<!-- field id=x type=prose -->', '\nEen.\n\nTwee.\n\n');
      expect(a.text, 'Een.\n\nTwee.');
      expect(a.isEmpty, isFalse);
      expect(a.shape, isEmpty);
    });

    test('empty when blank', () {
      expect(read('<!-- field id=x type=prose -->', ' \n ').isEmpty, isTrue);
    });

    test(
      'line endings are normalised in the text, so lengths cannot differ',
      () {
        final a = read(
          '<!-- field id=x type=prose -->',
          'Een.\r\n\r\nTwee.\r\n',
        );
        expect(a.text, 'Een.\n\nTwee.');
      },
    );

    test('the raw zone and its first line are kept for the editor', () {
      final a = read(
        '<!-- field id=x type=prose -->',
        '\n x \n',
        firstLine: 14,
      );
      expect(a.raw, '\n x \n');
      expect(a.firstLine, 14);
      expect(a.fieldId, 'x');
      expect(a.type, 'prose');
    });
  });

  group('choice', () {
    const marker = '<!-- field id=x type=choice options="A|B" other -->';

    test('one line, trimmed', () {
      expect(read(marker, ' A \n').text, 'A');
    });

    test('two lines are not a choice', () {
      expect(shape(read(marker, 'A\nB')), ['one-line']);
    });

    test('empty when blank', () {
      expect(read(marker, '').isEmpty, isTrue);
    });
  });

  group('multichoice', () {
    const marker = '<!-- field id=x type=multichoice options="A|B|C" -->';

    test('the checked items of a task list', () {
      final a = read(marker, '- [x] A\n- [ ] B\n- [X] C\n');
      expect(a.items, ['A', 'C']);
      expect(a.isEmpty, isFalse);
      expect(a.shape, isEmpty);
    });

    test('nothing checked is empty', () {
      final a = read(marker, '- [ ] A\n- [ ] B\n');
      expect(a.items, isEmpty);
      expect(a.isEmpty, isTrue);
      expect(read(marker, '').isEmpty, isTrue);
    });

    test('other bullet characters and extra blanks', () {
      expect(read(marker, '* [x] A\n+ [x]   B\n').items, ['A', 'B']);
    });

    test('a checked item twice counts once', () {
      expect(read(marker, '- [x] A\n- [x] A\n').items, ['A']);
    });

    test('a line that is not a task item is malformed', () {
      expect(shape(read(marker, '- [x] A\nzomaar tekst')), ['not-a-task-list']);
      expect(shape(read(marker, '- A')), ['not-a-task-list']);
      expect(shape(read(marker, '- [y] A')), ['not-a-task-list']);
      expect(shape(read(marker, '[x] A')), ['not-a-task-list']);
    });

    test('the malformed line is named', () {
      final a = read(marker, '- [x] A\nfout', firstLine: 20);
      expect(a.shape.single.line, 21);
    });
  });

  group('list', () {
    const bullets = '<!-- field id=x type=list -->';
    const numbered = '<!-- field id=x type=list ordered -->';

    test('bullet items', () {
      final a = read(bullets, '- een\n- twee\n* drie\n');
      expect(a.items, ['een', 'twee', 'drie']);
      expect(a.shape, isEmpty);
    });

    test('numbered items for an ordered list', () {
      expect(read(numbered, '1. een\n2. twee\n3) drie').items, [
        'een',
        'twee',
        'drie',
      ]);
    });

    test(
      'numbers where bullets are expected, and bullets where numbers are, are malformed',
      () {
        expect(shape(read(bullets, '1. een')), ['ordered-item']);
        expect(shape(read(numbered, '- een')), ['unordered-item']);
      },
    );

    test('an indented line continues the item above', () {
      final a = read(bullets, '- een\n  vervolg\n- twee\n\tnog een\n');
      expect(a.items, ['een\nvervolg', 'twee\nnog een']);
    });

    test('an indented line under an empty item becomes that item', () {
      expect(read(bullets, '-\n  vervolg').items, ['vervolg']);
    });

    test('an empty item is not an item', () {
      final a = read(bullets, '- een\n-\n- \n- twee');
      expect(a.items, ['een', 'twee']);
    });

    test('text that is not a list is malformed', () {
      expect(shape(read(bullets, 'gewoon tekst')), ['not-a-list']);
      expect(shape(read(bullets, '- een\nzomaar')), ['not-a-list']);
    });

    test('an indented line with nothing above it is not a list', () {
      expect(shape(read(bullets, '  vervolg')), ['not-a-list']);
    });

    test('empty when there are no items', () {
      expect(read(bullets, '').isEmpty, isTrue);
      expect(read(bullets, '-\n-').isEmpty, isTrue);
    });
  });

  group('table', () {
    const marker =
        '<!-- field id=x type=table columns="Hoeveelheid|Ingrediënt" rows=2.. -->';
    const header = '| Hoeveelheid | Ingrediënt |\n|---|---|\n';

    test('data rows under the fixed header', () {
      final a = read(
        marker,
        '$header| 2 el | ketjap manis |\n| 1 tl | sambal |\n',
      );
      expect(a.rows, [
        ['2 el', 'ketjap manis'],
        ['1 tl', 'sambal'],
      ]);
      expect(a.isEmpty, isFalse);
      expect(a.shape, isEmpty);
    });

    test('a header with no rows is empty', () {
      final a = read(marker, header);
      expect(a.rows, isEmpty);
      expect(a.isEmpty, isTrue);
      expect(a.shape, isEmpty);
    });

    test('a row with only empty cells is not a row', () {
      final a = read(marker, '$header| | |\n| 2 el | x |\n|  |  |\n');
      expect(a.rows, [
        ['2 el', 'x'],
      ]);
    });

    test('the header must be the declared columns, exactly', () {
      expect(shape(read(marker, '| A | B |\n|---|---|\n| 1 | 2 |')), [
        'header-mismatch',
      ]);
      expect(shape(read(marker, '| Ingrediënt | Hoeveelheid |\n|---|---|\n')), [
        'header-mismatch',
      ]);
      expect(shape(read(marker, '| Hoeveelheid |\n|---|\n')), [
        'header-mismatch',
      ]);
    });

    test('a cell that ends with an escaped pipe keeps it', () {
      final a = read(marker, '$header x | y \\|\n');
      expect(a.rows, [
        ['x', 'y |'],
      ]);
    });

    test('a rule row needs at least one dash in every cell', () {
      for (final bad in ['| : | : |', '| | |', '|  |  |', '| -- | |']) {
        expect(shape(read(marker, '| Hoeveelheid | Ingrediënt |\n$bad\n')), [
          'rule-row',
        ], reason: bad);
      }
    });

    test(
      'alignment colons in the rule row are fine, other rule rows are not',
      () {
        expect(
          read(marker, '| Hoeveelheid | Ingrediënt |\n|:--|--:|\n').shape,
          isEmpty,
        );
        expect(
          shape(read(marker, '| Hoeveelheid | Ingrediënt |\n| a | b |\n')),
          ['rule-row'],
        );
      },
    );

    test('a row with the wrong number of cells is malformed', () {
      final a = read(marker, '$header| 2 el |\n| 1 | 2 | 3 |\n', firstLine: 10);
      expect(shape(a), ['row-shape', 'row-shape']);
      expect(a.shape.first.line, 12);
    });

    test('text that is not a table is malformed', () {
      expect(shape(read(marker, 'gewoon tekst')), ['not-a-table']);
    });

    test('an escaped pipe stays inside its cell', () {
      final a = read(marker, '$header| a \\| b | c |\n');
      expect(a.rows, [
        ['a | b', 'c'],
      ]);
    });

    test('rows may omit the outer pipes', () {
      final a = read(
        marker,
        'Hoeveelheid | Ingrediënt\n---|---\n2 el | ketjap\n',
      );
      expect(a.rows, [
        ['2 el', 'ketjap'],
      ]);
      expect(a.shape, isEmpty);
    });
  });

  group('image', () {
    const marker = '<!-- field id=x type=image -->';

    test('one image per line, with alt and an optional credit', () {
      final a = read(
        marker,
        '![portret](images/portret-1.jpg)\n![gerecht](images/gerecht-1.png "Foto: Sari")\n',
      );
      expect(a.images.map((i) => i.path), [
        'images/portret-1.jpg',
        'images/gerecht-1.png',
      ]);
      expect(a.images.map((i) => i.alt), ['portret', 'gerecht']);
      expect(a.images.map((i) => i.credit), [null, 'Foto: Sari']);
      expect(a.isEmpty, isFalse);
      expect(a.shape, isEmpty);
    });

    test('several images on one line are all counted', () {
      final a = read(marker, '![a](images/a-1.jpg) ![b](images/b-1.jpg)');
      expect(a.images.length, 2);
      expect(a.shape, isEmpty);
    });

    test('an empty alt is read as empty, not refused here', () {
      expect(read(marker, '![](images/a-1.jpg)').images.single.alt, '');
    });

    test('text in an image field is malformed', () {
      expect(shape(read(marker, 'gewoon tekst')), ['not-an-image']);
      expect(shape(read(marker, '![a](images/a-1.jpg) en tekst')), [
        'not-an-image',
      ]);
    });

    test('a device name is no image, whatever the extension', () {
      final a = read(marker, '![a](images/nul.jpg)\n![b](images/b-1.jpg)');
      expect(a.images.map((i) => i.path), ['images/b-1.jpg']);
    });

    test('a bad image line is left to the safety rules, not counted', () {
      final a = read(marker, '![a](http://x/1.png)\n![b](images/b-1.jpg)');
      expect(a.images.map((i) => i.path), ['images/b-1.jpg']);
      expect(
        a.shape,
        isEmpty,
        reason: 'answer-bad-image is reported by the safety scan',
      );
    });

    test('the same file twice is malformed', () {
      expect(
        shape(read(marker, '![a](images/a-1.jpg)\n![b](images/a-1.jpg)')),
        ['duplicate-image'],
      );
    });

    test('empty when there are no images', () {
      expect(read(marker, '').isEmpty, isTrue);
    });
  });

  group('consent', () {
    const marker = '<!-- field id=x type=consent required -->';

    test('exactly one box', () {
      expect(read(marker, '- [ ]').consent, isFalse);
      expect(read(marker, '- [x]').consent, isTrue);
      expect(read(marker, '- [X]\n').consent, isTrue);
      expect(read(marker, '\n  - [x]  \n').consent, isTrue);
    });

    test(
      'anything else is malformed: the consent text is not the respondent\'s',
      () {
        for (final zone in [
          '- [x] Ik ga akkoord, behalve met foto\'s',
          '* [x]',
          '[x]',
          '- [y]',
          '- [x]\n- [x]',
          'ja',
        ]) {
          final a = read(marker, zone);
          expect(shape(a), ['consent-box'], reason: zone);
          expect(a.consent, isNull, reason: zone);
        }
      },
    );

    test('no box at all is malformed', () {
      final a = read(marker, '');
      expect(shape(a), ['consent-box-missing']);
      expect(a.consent, isNull);
    });
  });

  group('FormImageRef', () {
    test('equality by value', () {
      expect(
        const FormImageRef('images/a-1.jpg', 'x', null),
        const FormImageRef('images/a-1.jpg', 'x', null),
      );
      expect(
        const FormImageRef('images/a-1.jpg', 'x', null),
        isNot(const FormImageRef('images/a-1.jpg', 'y', null)),
      );
    });
  });
}
