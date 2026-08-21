import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/markdown_safety.dart';

void main() {
  group('MarkdownSafetyScanner', () {
    test('clean data-only deck passes', () {
      const md = '''
---
marp: true
title: Kwartaalcijfers
---

# Omzet

- Q1: € 1,2 mln
- Q2: € 1,5 mln

[Bron](https://example.com/report)

![grafiek](images/chart.png)
''';
      expect(MarkdownSafetyScanner.isSafe(md), isTrue);
      expect(MarkdownSafetyScanner.scan(md), isEmpty);
    });

    test('flags a <script> tag with its line', () {
      const md = 'line one\nline two\n<script>steal()</script>\n';
      final findings = MarkdownSafetyScanner.scan(md);
      expect(findings, isNotEmpty);
      expect(findings.first.kind, MarkdownThreat.scriptExecution);
      expect(findings.first.line, 3);
    });

    test('flags an inline event handler', () {
      const md = '![x](images/a.png)\n<img src="x" onerror="alert(1)">';
      final findings = MarkdownSafetyScanner.scan(md);
      expect(
        findings.any((f) => f.kind == MarkdownThreat.scriptExecution),
        isTrue,
      );
    });

    test('flags an inline event handler after a solidus', () {
      final findings = MarkdownSafetyScanner.scan('<svg/onload=alert(1)>');
      expect(
        findings.any((f) => f.kind == MarkdownThreat.scriptExecution),
        isTrue,
      );
    });

    test('flags a javascript: link target but not the word JavaScript', () {
      expect(
        MarkdownSafetyScanner.scan('[click](javascript:alert(1))'),
        isNotEmpty,
      );
      // Prose mentioning the language must not trip the gate.
      expect(
        MarkdownSafetyScanner.isSafe('We discuss JavaScript: the language.'),
        isTrue,
      );
    });

    test('flags iframe/object as embedded content', () {
      expect(
        MarkdownSafetyScanner.scan(
          '<iframe src="https://evil"></iframe>',
        ).any((f) => f.kind == MarkdownThreat.embeddedContent),
        isTrue,
      );
    });

    test('flags data:text/html and meta refresh as unsafe URLs', () {
      expect(
        MarkdownSafetyScanner.scan(
          '[x](data:text/html,<script>1</script>)',
        ).any((f) => f.kind == MarkdownThreat.unsafeUrl),
        isTrue,
      );
      expect(
        MarkdownSafetyScanner.scan(
          '<meta http-equiv="refresh" content="0;url=x">',
        ).any((f) => f.kind == MarkdownThreat.unsafeUrl),
        isTrue,
      );
    });

    test('sees through numeric-entity and zero-width evasion', () {
      // javascript: encoded with a numeric entity inside a link target.
      expect(
        MarkdownSafetyScanner.scan('[x](&#106;avascript:alert(1))'),
        isNotEmpty,
      );
      // A zero-width space splitting the opening script tag.
      expect(
        MarkdownSafetyScanner.scan('<scr\u200Bipt>x</script>'),
        isNotEmpty,
      );
    });

    test('benign inline HTML like <b> and <div> is allowed', () {
      expect(
        MarkdownSafetyScanner.isSafe('Some **<b>bold</b>** and <div>x</div>'),
        isTrue,
      );
    });

    group("own <iframe class=\"ocideck-embed\"> video embeds", () {
      const youtube =
          '<iframe class="ocideck-embed" data-src="https://youtu.be/dQw4w9WgXcQ" '
          'src="https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ?autoplay=0" '
          'style="width:100%; aspect-ratio:16/9; border:0;" '
          'allow="autoplay; fullscreen; picture-in-picture" allowfullscreen></iframe>';
      const vimeo =
          '<iframe class="ocideck-embed" data-src="https://vimeo.com/123456" '
          'src="https://player.vimeo.com/video/123456" '
          'style="width:100%; aspect-ratio:16/9;" allowfullscreen></iframe>';

      test('YouTube embed passes the gate', () {
        expect(MarkdownSafetyScanner.isSafe(youtube), isTrue);
      });
      test('Vimeo embed passes the gate', () {
        expect(MarkdownSafetyScanner.isSafe(vimeo), isTrue);
      });

      test('embed pointing at a foreign host is still blocked', () {
        const evil =
            '<iframe class="ocideck-embed" src="https://evil.example.com/x"></iframe>';
        expect(MarkdownSafetyScanner.isSafe(evil), isFalse);
      });
      test('embed with a javascript: src is still blocked', () {
        const evil =
            '<iframe class="ocideck-embed" src="javascript:alert(1)"></iframe>';
        expect(MarkdownSafetyScanner.isSafe(evil), isFalse);
      });
      test('embed with an on… handler is still flagged', () {
        const evil =
            '<iframe class="ocideck-embed" onload="alert(1)" '
            'src="https://www.youtube-nocookie.com/embed/x"></iframe>';
        expect(MarkdownSafetyScanner.isSafe(evil), isFalse);
      });
      test('a plain foreign iframe without the class is still blocked', () {
        expect(
          MarkdownSafetyScanner.isSafe(
            '<iframe src="https://www.youtube-nocookie.com/embed/x"></iframe>',
          ),
          isFalse,
        );
      });
      test('the class alias does not whitelist object/embed', () {
        expect(
          MarkdownSafetyScanner.isSafe(
            '<object class="ocideck-embed"></object>',
          ),
          isFalse,
        );
      });
    });
  });
}
