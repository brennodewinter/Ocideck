import 'package:ocideck_form_core/src/form_source.dart';
import 'package:test/test.dart';

void main() {
  group('FormSource lines', () {
    test('splits on LF and keeps offsets of the original string', () {
      final src = FormSource('ab\ncd\n\nef');
      expect(src.lines.map((l) => l.text), ['ab', 'cd', '', 'ef']);
      expect(src.lines.map((l) => l.number), [1, 2, 3, 4]);
      expect(src.lines.map((l) => l.start), [0, 3, 6, 7]);
      expect(src.lines.map((l) => l.end), [2, 5, 6, 9]);
      expect(src.lines.map((l) => l.nextStart), [3, 6, 7, 9]);
    });

    test('CRLF: the CR belongs to the line ending, not to the line', () {
      final src = FormSource('ab\r\ncd\r\n');
      expect(src.lines.map((l) => l.text), ['ab', 'cd', '']);
      expect(src.lines[0].end, 2, reason: 'just past the b');
      expect(src.text.substring(src.lines[0].start, src.lines[0].end), 'ab');
      expect(src.lines[0].nextStart, 4);
      expect(
        src.text.substring(src.lines[0].start, src.lines[0].nextStart),
        'ab\r\n',
      );
    });

    test('a final line without newline ends at the string length', () {
      final src = FormSource('only');
      expect(src.lines.single.end, 4);
      expect(src.lines.single.nextStart, 4);
    });

    test('an empty string is one empty line', () {
      final src = FormSource('');
      expect(src.lines.single.text, '');
      expect(src.bodyStartIndex, 0);
    });

    test('a BOM is not part of line 1 but still counts in the offsets', () {
      final src = FormSource('﻿<!-- form -->\nx');
      expect(src.lines[0].text, '<!-- form -->');
      expect(src.lines[0].start, 0);
      expect(src.lines[0].end, 14);
      expect(src.lines[1].start, 15);
    });

    test('a lone CR is not a line break', () {
      expect(FormSource('a\rb').lines.single.text, 'a\rb');
    });

    test('every offset slices back to the original string', () {
      const text = 'x\r\n\r\néè\n\u{1F336}\nlast';
      final src = FormSource(text);
      final rebuilt = StringBuffer();
      for (final l in src.lines) {
        rebuilt.write(text.substring(l.start, l.nextStart));
      }
      expect(rebuilt.toString(), text, reason: 'lines tile the source exactly');
    });
  });

  group('front matter', () {
    int body(String s) => FormSource(s).bodyStartIndex;

    test('a well-formed block is skipped, with the blanks after it', () {
      expect(body('---\ntheme: x\n---\n\n\n<!-- form -->\n'), 5);
    });

    test('works with CRLF and with a BOM', () {
      expect(body('---\r\ntheme: x\r\n---\r\n<!-- form -->'), 3);
      expect(body('﻿---\ntheme: x\n---\nbody'), 3);
    });

    test('a leading --- with no closing fence is a rule, not front matter', () {
      expect(body('---\n<!-- form -->\n'), 0);
    });

    test('--- … --- around prose is two rules, not front matter', () {
      expect(body('---\n# Heading\n---\nbody'), 0);
    });

    test('front matter must open with a YAML key', () {
      expect(body('---\n\n  \nkey: v\n---\nb'), 5);
      expect(body('---\njust text\n---\nb'), 0);
    });

    test('--- that is not the first line is no front matter', () {
      expect(body('\n---\ntheme: x\n---\nb'), 0);
    });

    test('an empty block is not front matter', () {
      expect(body('---\n---\nb'), 0);
    });
  });

  group('fences', () {
    test('formFenceOpen sees ``` and ~~~ runs of three or more', () {
      expect(formFenceOpen('```')?.char, '`');
      expect(formFenceOpen('````dart')?.length, 4);
      expect(formFenceOpen('~~~')?.char, '~');
      expect(formFenceOpen('``'), isNull);
      expect(formFenceOpen('text ```'), isNull);
      expect(formFenceOpen(''), isNull);
    });

    test('a fence closes only on the same character, long enough', () {
      final f = formFenceOpen('````')!;
      expect(f.closes('````'), isTrue);
      expect(f.closes('`````'), isTrue);
      expect(f.closes('```'), isFalse);
      expect(f.closes('~~~~'), isFalse);
      expect(f.closes('```` x'), isFalse, reason: 'nothing may follow');
      expect(f.closes('````  '), isTrue, reason: 'trailing blanks are fine');
    });

    test('the tracker reports fence lines and their content as code', () {
      final t = FormFenceTracker();
      expect(t.isCode('text'), isFalse);
      expect(t.isCode('```'), isTrue);
      expect(t.inFence, isTrue);
      expect(t.isCode('<!-- field -->'), isTrue);
      expect(
        t.isCode('~~~'),
        isTrue,
        reason: 'a different char does not close',
      );
      expect(t.inFence, isTrue);
      expect(t.isCode('```'), isTrue);
      expect(t.inFence, isFalse);
      expect(t.isCode('after'), isFalse);
    });

    test('an indented fence is still a fence (leading blanks are trimmed)', () {
      final t = FormFenceTracker();
      expect(t.isCode('   ```'), isTrue);
      expect(t.inFence, isTrue);
    });
  });
}
