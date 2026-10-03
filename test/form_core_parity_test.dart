import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/document_front_matter.dart';
import 'package:ocideck/utils/markdown_blocks.dart';
import 'package:ocideck_form_core/ocideck_form_core.dart';

/// Keeps `packages/ocideck_form_core` in step with the things it deliberately
/// does *not* import, because a Flutter-free package cannot see the app:
///
///   * the fence predicate (`markdownFenceOpen`) — a form block must agree with the
///     reader that renders it about what is code;
///   * front-matter detection (`splitDocumentFrontMatter`) — a form must survive a
///     document style being chosen, which writes front matter above it;
///   * the design document — the issue codes (§4.11) and the field types (§4.5) the
///     engine knows must be the ones the document promises.
///
/// A copy that nothing compares against drifts; these tests are the comparison.
void main() {
  group('fence predicate parity with markdownFenceOpen', () {
    const openers = [
      '```',
      '````',
      '`````dart',
      '~~~',
      '~~~~~',
      '~~~yaml',
      '``` extra words',
      '``',
      '~~',
      'text',
      '',
      '`~`',
      '```` ',
      '~~~```',
    ];
    const closers = [
      '```',
      '````',
      '`````',
      '~~~',
      '~~~~',
      '``` ',
      '```x',
      '``',
      '',
      '```\t',
      '~~~ ~~~',
    ];

    test('both see the same fence on every opener', () {
      for (final line in openers) {
        final app = markdownFenceOpen(line);
        final form = formFenceOpen(line);
        expect(form == null, app == null, reason: '"$line"');
        if (app != null) {
          expect(form!.char, app.marker, reason: '"$line"');
          expect(form.length, app.length, reason: '"$line"');
        }
      }
    });

    test('both close it on the same lines', () {
      for (final open in openers) {
        final app = markdownFenceOpen(open);
        final form = formFenceOpen(open);
        if (app == null) continue;
        for (final close in closers) {
          expect(
            form!.closes(close),
            app.closes(close),
            reason: 'open "$open", close "$close"',
          );
        }
      }
    });
  });

  group('front-matter parity with splitDocumentFrontMatter', () {
    const sources = [
      '',
      'plain\n',
      '---\ntheme: x\n---\nbody\n',
      '---\ntheme: x\n---\n\n\nbody\n',
      '---\ntheme: x\n---',
      '---\ntheme: x\n---\n',
      '---\r\ntheme: x\r\n---\r\n\r\nbody\r\n',
      '---\n# Heading\n---\nbody\n',
      '---\nbody only\n',
      '---\n',
      '---',
      '---\n---\nb\n',
      '---\n\n  \nkey: v\n---\nb\n',
      '---\njust text\n---\nb\n',
      '\n---\ntheme: x\n---\nb\n',
      '---\nkey: v\n---\n---\nmore\n',
      '---\nkey: v\n--- \nafter\n',
      '---\n12:30\n---\nb\n',
      '---\nfirst: 1\nsecond: 2\n---\n# Doc\n',
    ];

    test('both end the block at the same offset', () {
      for (final source in sources) {
        final app = splitDocumentFrontMatter(source).block.length;
        final form = FormSource(source);
        final offset = form.bodyStartIndex < form.lines.length
            ? form.lines[form.bodyStartIndex].start
            : source.length;
        expect(offset, app, reason: source.replaceAll('\n', r'\n'));
      }
    });
  });

  group('the design document and the engine agree', () {
    late String doc;

    setUpAll(() {
      doc = File('docs/design/FORM_INTAKE.md').readAsStringSync();
    });

    String between(String from, String to) {
      final start = doc.indexOf(from);
      expect(start, isNonNegative, reason: 'the document lost "$from"');
      final end = doc.indexOf(to, start);
      expect(end, greaterThan(start), reason: 'the document lost "$to"');
      return doc.substring(start, end);
    }

    test('every issue code in §4.11 exists, and every code is documented', () {
      final section = between('**Issue codes**', '**Severity:**');
      final documented = {
        for (final m in RegExp(
          r'`([a-z]+(?:-[a-z]+)+|[a-z]+)`',
        ).allMatches(section))
          m.group(1)!,
      };
      final implemented = {for (final c in FormIssueCode.values) c.wireName};
      expect(
        documented.difference(implemented),
        isEmpty,
        reason: 'documented in FORM_INTAKE.md §4.11 but not in FormIssueCode',
      );
      expect(
        implemented.difference(documented),
        isEmpty,
        reason: 'in FormIssueCode but not documented in FORM_INTAKE.md §4.11',
      );
    });

    test('the field types of §4.5 are the registry, in the same order', () {
      final table = between('### 4.5 Field types', '### 4.6');
      final documented = [
        for (final m in RegExp(
          r'^\| `([a-z]+)` \|',
          multiLine: true,
        ).allMatches(table))
          m.group(1)!,
      ];
      // The header row is `| `type` | Answer is | … |`.
      expect(documented.first, 'type');
      expect(documented.skip(1).toList(), kFormFieldTypes.keys.toList());
    });

    test('every marker name of §4.3 is a FormMarkerName', () {
      final grammar = between('### 4.3 Marker grammar', '### 4.4');
      final line = RegExp(r'name\s+:= (.+)').firstMatch(grammar)!.group(1)!;
      final documented = {
        for (final m in RegExp(
          r'"(/?[a-z]+)"',
        ).allMatches(grammar.substring(grammar.indexOf('name       :='))))
          m.group(1)!,
      };
      expect(line, contains('form'));
      expect(documented, {for (final n in FormMarkerName.values) n.wire});
    });
  });
}
