import 'package:ocideck_form_core/src/form_blocks.dart';
import 'package:ocideck_form_core/src/form_parser.dart';
import 'package:ocideck_form_core/src/form_spec.dart';
import 'package:test/test.dart';

/// The block boundary is what OciDeck's own surfaces (the reader, the visual
/// editor) hang an atomic embed on, so it must agree with `parseForm` about where
/// a field starts and ends (FORM_INTAKE.md §4.9, first row of the chain).
int? length(List<String> lines) =>
    formBlockLength((i) => i < lines.length ? lines[i] : null);

void main() {
  splitTests();
  group('formBlockKind', () {
    test('the three kinds that start a block', () {
      expect(formBlockKind('<!-- form id=f -->'), FormBlockKind.header);
      expect(
        formBlockKind('<!-- field id=a type=text -->'),
        FormBlockKind.field,
      );
      expect(formBlockKind('<!-- notice -->'), FormBlockKind.notice);
    });

    test('everything else starts none', () {
      for (final line in [
        '<!-- answer -->',
        '<!-- /field id=a -->',
        '<!-- /notice -->',
        '<!-- toc -->',
        '# kop',
        '',
        '    <!-- field id=a type=text -->',
        '<!-- Field id=a type=text -->',
        '<!-- field: id=a -->',
      ]) {
        expect(formBlockKind(line), isNull, reason: line);
      }
    });

    test('a CR at the end of the line is tolerated', () {
      expect(formBlockKind('<!-- notice -->\r'), FormBlockKind.notice);
    });
  });

  group('formBlockLength', () {
    test('a form marker is one line', () {
      expect(length(['<!-- form id=f -->', 'tekst']), 1);
      expect(length(['<!-- form id=f -->']), 1);
    });

    test('a field runs to its own closing marker, inclusive', () {
      expect(
        length([
          '<!-- field id=a type=text -->',
          'Label',
          '<!-- answer -->',
          'antwoord',
          '<!-- /field id=a -->',
          'daarna',
        ]),
        5,
      );
    });

    test('an empty answer and a field with no label', () {
      expect(
        length([
          '<!-- field id=a type=text -->',
          '<!-- answer -->',
          '<!-- /field id=a -->',
        ]),
        3,
      );
    });

    test('a close for another id does not end it; only its own does', () {
      expect(
        length([
          '<!-- field id=a type=text -->',
          '<!-- answer -->',
          '<!-- /field id=b -->',
          'x',
          '<!-- /field id=a -->',
        ]),
        5,
      );
    });

    test('markers and fences inside the zone do not end it', () {
      expect(
        length([
          '<!-- field id=a type=prose -->',
          '<!-- answer -->',
          '```',
          '<!-- /field id=a -->',
        ]),
        4,
        reason: 'the zone ends at the matching close even inside a fence',
      );
    });

    test('a field that never closes is not a block', () {
      expect(
        length(['<!-- field id=a type=text -->', 'Label', '<!-- answer -->']),
        isNull,
      );
      expect(length(['<!-- field id=a type=text -->']), isNull);
    });

    test(
      'a field with no usable id cannot be paired, so it is not a block',
      () {
        expect(
          length([
            '<!-- field type=text -->',
            '<!-- answer -->',
            '<!-- /field id=a -->',
          ]),
          isNull,
        );
        expect(
          length([
            '<!-- field id="" type=text -->',
            '<!-- answer -->',
            '<!-- /field id="" -->',
          ]),
          isNull,
        );
      },
    );

    test('a notice runs to /notice', () {
      expect(length(['<!-- notice -->', 'tekst', '<!-- /notice -->', 'x']), 3);
      expect(length(['<!-- notice -->', 'tekst']), isNull);
    });

    test('a line that starts no block has no length', () {
      expect(length(['gewoon tekst']), isNull);
      expect(length([]), isNull);
    });

    test('the look-ahead is bounded', () {
      final lines = [
        '<!-- field id=a type=text -->',
        ...List.filled(100, 'x'),
        '<!-- /field id=a -->',
      ];
      expect(
        formBlockLength(
          (i) => i < lines.length ? lines[i] : null,
          maxLines: 50,
        ),
        isNull,
      );
      expect(
        formBlockLength(
          (i) => i < lines.length ? lines[i] : null,
          maxLines: 200,
        ),
        102,
      );
    });

    test('CRLF lines are tolerated', () {
      expect(
        length([
          '<!-- field id=a type=text -->\r',
          '<!-- answer -->\r',
          '<!-- /field id=a -->\r',
        ]),
        3,
      );
    });
  });

  group('agrees with parseForm about where a field starts and ends', () {
    void expectAgreement(String text) {
      final r = parseForm(text);
      expect(
        r,
        isA<ParsedForm>(),
        reason: r is BrokenForm ? '${r.problems}' : '',
      );
      final lines = text.split('\n');
      final spec = (r as ParsedForm).spec;
      expect(
        formBlockLength((i) => i < lines.length ? lines[i] : null),
        1,
        reason: 'the form marker is the first line',
      );
      for (final f in spec.fields) {
        final at = f.open.line - 1;
        final n = formBlockLength(
          (i) => at + i < lines.length ? lines[at + i] : null,
        );
        expect(n, f.close.line - f.open.line + 1, reason: f.id);
      }
      final notice = spec.notice;
      if (notice != null) {
        final at = notice.open.line - 1;
        expect(
          formBlockLength((i) => at + i < lines.length ? lines[at + i] : null),
          notice.close.line - notice.open.line + 1,
        );
      }
    }

    test('a plain form', () {
      expectAgreement('''<!-- form id=f -->
# Titel
<!-- notice -->
tekst
<!-- /notice -->
<!-- field id=a type=text -->
Label
<!-- answer -->
x
<!-- /field id=a -->

<!-- field id=b type=prose -->
Label
<!-- answer -->

<!-- /field id=b -->
''');
    });

    test('markers and fences in the template-owned text and in the zones', () {
      expectAgreement('''<!-- form id=f -->
```
<!-- field id=ghost type=text -->
```
<!-- field id=a type=prose -->
```
<!-- answer -->
```
<!-- answer -->
tekst met <!-- notice --> en
<!-- answer -->
```
<!-- /field id=a -->
```
<!-- field id=b type=text -->
Label
<!-- answer -->
<!-- /field id=b -->
''');
    });

    test('many generated fields', () {
      final b = StringBuffer('<!-- form id=f -->\n');
      for (var i = 0; i < 200; i++) {
        b.write('<!-- field id=f$i type=prose -->\nL$i\n<!-- answer -->\n');
        for (var k = 0; k < i % 5; k++) {
          b.write('regel $k\n');
        }
        b.write('<!-- /field id=f$i -->\n');
      }
      expectAgreement(b.toString());
    });
  });
}

void splitTests() {
  group('splitFieldBlock', () {
    test('label and answer, without the three marker lines', () {
      final parts = splitFieldBlock(
        '<!-- field id=a type=prose -->\n**Naam**\n> uitleg\n<!-- answer -->\nregel een\n\nregel twee\n<!-- /field id=a -->',
      );
      expect(parts.label, '**Naam**\n> uitleg');
      expect(parts.answer, 'regel een\n\nregel twee');
    });

    test('an empty answer and an empty label', () {
      final a = splitFieldBlock(
        '<!-- field id=a type=text -->\nL\n<!-- answer -->\n<!-- /field id=a -->',
      );
      expect(a.label, 'L');
      expect(a.answer, '');
      final b = splitFieldBlock(
        '<!-- field id=a type=text -->\n<!-- answer -->\nx\n<!-- /field id=a -->',
      );
      expect(b.label, '');
      expect(b.answer, 'x');
    });

    test('an answer marker inside a fence in the label is label text', () {
      final parts = splitFieldBlock(
        '<!-- field id=a type=text -->\n```\n<!-- answer -->\n```\n<!-- answer -->\nx\n<!-- /field id=a -->',
      );
      expect(parts.label, '```\n<!-- answer -->\n```');
      expect(parts.answer, 'x');
    });

    test('markers inside the answer stay in the answer', () {
      final parts = splitFieldBlock(
        '<!-- field id=a type=prose -->\nL\n<!-- answer -->\na\n<!-- answer -->\nb\n<!-- /field id=a -->',
      );
      expect(parts.answer, 'a\n<!-- answer -->\nb');
    });

    test('no answer marker: everything between the markers is label', () {
      final parts = splitFieldBlock(
        '<!-- field id=a type=text -->\nL\n<!-- /field id=a -->',
      );
      expect(parts.label, 'L');
      expect(parts.answer, '');
    });

    test(
      'a block without a closing marker still splits, and nothing throws',
      () {
        final parts = splitFieldBlock(
          '<!-- field id=a type=text -->\nL\n<!-- answer -->\nx',
        );
        expect(parts.label, 'L');
        expect(parts.answer, 'x');
        expect(splitFieldBlock('').label, '');
        expect(splitFieldBlock('<!-- field id=a type=text -->').answer, '');
      },
    );

    test('CRLF', () {
      final parts = splitFieldBlock(
        '<!-- field id=a type=text -->\r\nL\r\n<!-- answer -->\r\nx\r\n<!-- /field id=a -->',
      );
      expect(parts.answer, 'x\r');
    });
  });
}
