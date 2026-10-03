import 'package:ocideck_form_core/src/form_blocks.dart';
import 'package:test/test.dart';

FoundMarker found(String line) {
  final scan = scanMarkerLine(line);
  expect(scan, isA<FoundMarker>(), reason: line);
  return scan as FoundMarker;
}

BadMarker bad(String line) {
  final scan = scanMarkerLine(line);
  expect(scan, isA<BadMarker>(), reason: line);
  return scan as BadMarker;
}

void main() {
  group('names', () {
    test('the six marker names are recognised, and nothing else', () {
      expect(found('<!-- form id=x -->').name, FormMarkerName.form);
      expect(found('<!-- field id=x type=text -->').name, FormMarkerName.field);
      expect(found('<!-- answer -->').name, FormMarkerName.answer);
      expect(found('<!-- /field id=x -->').name, FormMarkerName.fieldEnd);
      expect(found('<!-- notice -->').name, FormMarkerName.notice);
      expect(found('<!-- /notice -->').name, FormMarkerName.noticeEnd);
    });

    test('wire names are the spelling on disk', () {
      expect(FormMarkerName.fieldEnd.wire, '/field');
      expect(FormMarkerName.noticeEnd.wire, '/notice');
      expect(FormMarkerName.values.map((n) => n.wire).toSet(), {
        'form',
        'field',
        'answer',
        '/field',
        'notice',
        '/notice',
      });
    });

    test('other comments are not markers', () {
      for (final line in [
        '<!-- toc -->',
        '<!-- finding -->',
        '<!-- timeline -->',
        '<!-- a comment -->',
        '<!-- formatting note -->',
        '<!-- form-letter -->',
        '<!-- fields -->',
        '<!-- answers -->',
        '<!-- ocideck_field id=x -->',
        '<!---->',
        '<!--  -->',
        'plain text',
        '',
        '# <!-- form -->',
        '- <!-- form -->',
        '> <!-- form -->',
      ]) {
        expect(scanMarkerLine(line), isA<NoMarker>(), reason: line);
      }
    });

    test(
      'names are case-sensitive; a miscased one is reported, not ignored',
      () {
        for (final entry in {
          '<!-- Form id=x -->': 'Form',
          '<!-- FIELD id=x type=text -->': 'FIELD',
          '<!-- Answer -->': 'Answer',
          '<!-- /Field id=x -->': '/Field',
          '<!-- Notice -->': 'Notice',
        }.entries) {
          final scan = scanMarkerLine(entry.key);
          expect(scan, isA<MiscasedMarker>(), reason: entry.key);
          expect((scan as MiscasedMarker).given, entry.value);
        }
      },
    );

    test(
      'a colon (the old style) or other punctuation is malformed, not ignored',
      () {
        for (final line in [
          '<!-- field: id=x type=text -->',
          '<!-- form: id=x -->',
          '<!-- answer: -->',
          '<!-- /field: id=x -->',
          '<!-- notice. -->',
        ]) {
          expect(bad(line).reason, 'punctuation-after-name', reason: line);
        }
      },
    );
  });

  group('line shape', () {
    test('up to three leading blanks are allowed, four are a code block', () {
      expect(found('<!-- answer -->'), isA<FoundMarker>());
      expect(found('   <!-- answer -->'), isA<FoundMarker>());
      expect(found('\t<!-- answer -->'), isA<FoundMarker>());
      expect(scanMarkerLine('    <!-- answer -->'), isA<NoMarker>());
    });

    test('trailing blanks are allowed, trailing text is not', () {
      expect(found('<!-- answer -->   '), isA<FoundMarker>());
      expect(found('<!-- answer -->\t'), isA<FoundMarker>());
      expect(bad('<!-- answer --> and more').reason, 'trailing-text');
      expect(
        scanMarkerLine('<!-- other --> and more'),
        isA<NoMarker>(),
        reason:
            'an unrelated comment with text after it is none of our business',
      );
    });

    test('spacing inside the comment is flexible', () {
      expect(found('<!--answer-->').name, FormMarkerName.answer);
      expect(found('<!--   answer   -->').name, FormMarkerName.answer);
      expect(found('<!--field id=x type=text-->').attr('type'), 'text');
      expect(found('<!--\tform\tid=x\t-->').attr('id'), 'x');
    });

    test('a comment that does not close on the same line is malformed', () {
      expect(bad('<!-- field id=x type=text').reason, 'not-single-line');
      expect(bad('<!-- answer').reason, 'not-single-line');
      expect(scanMarkerLine('<!-- just a note'), isA<NoMarker>());
    });

    test('--> inside is the end of the comment, nothing after it counts', () {
      expect(bad('<!-- answer --> <!-- other -->').reason, 'trailing-text');
    });
  });

  group('attributes', () {
    test('keys, values, quoted values and flags', () {
      final m = found(
        '<!-- field id=naam type=text required max-chars=80 label="a b" -->',
      );
      expect(m.attr('id'), 'naam');
      expect(m.attr('type'), 'text');
      expect(m.attr('max-chars'), '80');
      expect(m.attr('label'), 'a b');
      expect(m.hasFlag('required'), isTrue);
      expect(m.attr('required'), isNull, reason: 'a flag has no value');
      expect(m.has('required'), isTrue);
      expect(m.has('nope'), isFalse);
      expect(m.attrs.map((a) => a.key), [
        'id',
        'type',
        'required',
        'max-chars',
        'label',
      ]);
    });

    test(
      'quoted values may contain pipes, commas, equals signs and unicode',
      () {
        final m = found(
          '<!-- field id=x type=choice options="Quick Fix|Weekend=2|Zoet é" -->',
        );
        expect(m.attr('options'), 'Quick Fix|Weekend=2|Zoet é');
      },
    );

    test('an empty quoted value is syntactically fine', () {
      expect(found('<!-- form id=x lang="" -->').attr('lang'), '');
    });

    test(
      'a bare value runs to the next blank and may hold dots and dashes',
      () {
        expect(
          found('<!-- field id=x words=150..300 -->').attr('words'),
          '150..300',
        );
        expect(
          found('<!-- form id=x closes=2027-01-31 -->').attr('closes'),
          '2027-01-31',
        );
      },
    );

    test('keys are lower-case kebab', () {
      for (final line in [
        '<!-- field Id=x -->',
        '<!-- field 1id=x -->',
        '<!-- field id_x=x -->',
        '<!-- field =x -->',
        '<!-- field id=x ; -->',
      ]) {
        expect(bad(line).reason, 'bad-attribute-key', reason: line);
      }
    });

    test('empty and broken values are malformed', () {
      expect(bad('<!-- field id= type=text -->').reason, 'empty-value');
      expect(bad('<!-- field id= -->').reason, 'empty-value');
      expect(
        bad('<!-- field id="x type=text -->').reason,
        'unterminated-quote',
      );
      expect(bad('<!-- field id="x"y -->').reason, 'junk-after-quote');
      expect(bad('<!-- field id=a=b -->').reason, 'bad-bare-value');
      expect(bad('<!-- field id=a"b -->').reason, 'bad-bare-value');
    });

    test('the same key twice is malformed', () {
      final b = bad('<!-- field id=x id=y type=text -->');
      expect(b.reason, 'duplicate-attribute');
      expect(b.facts['key'], 'id');
    });

    test('the last-seen name is carried on a malformed marker', () {
      expect(bad('<!-- field id= -->').name, FormMarkerName.field);
      expect(bad('<!-- answer --> x').name, FormMarkerName.answer);
    });
  });

  group('marker-specific attribute rules', () {
    test('answer, notice and /notice take no attributes', () {
      expect(bad('<!-- answer x -->').reason, 'unexpected-attributes');
      expect(bad('<!-- notice id=x -->').reason, 'unexpected-attributes');
      expect(bad('<!-- /notice x -->').reason, 'unexpected-attributes');
    });

    test('/field carries exactly an id', () {
      expect(found('<!-- /field id=naam -->').attr('id'), 'naam');
      expect(bad('<!-- /field -->').reason, 'missing-id');
      expect(bad('<!-- /field id -->').reason, 'missing-id');
      expect(bad('<!-- /field naam -->').reason, 'missing-id');
      expect(
        bad('<!-- /field id=a other=b -->').reason,
        'unexpected-attributes',
      );
    });

    test('form and field accept any well-formed attributes', () {
      expect(found('<!-- form -->').attrs, isEmpty);
      expect(found('<!-- field -->').attrs, isEmpty);
      expect(found('<!-- form x-y=1 any-thing -->').attrs.length, 2);
    });
  });
}
