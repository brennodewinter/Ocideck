import 'package:ocideck_form_core/src/form_answer_safety.dart';
import 'package:ocideck_form_core/src/form_issue.dart';
import 'package:test/test.dart';

/// The wire names of the issues found in [zone].
List<String> found(String zone, {int firstLine = 1}) => [
  for (final p in answerSafetyIssues(zone, firstLine: firstLine))
    p.code.wireName,
];

List<FormProblem> problems(String zone, {int firstLine = 1}) =>
    answerSafetyIssues(zone, firstLine: firstLine);

void main() {
  group('clean answers', () {
    test('plain prose, lists, quotes, headings, emphasis, tables', () {
      for (final zone in [
        '',
        'Gewoon een antwoord.',
        'Twee alinea\'s.\n\nEn nog een, met *nadruk* en **vet** en `code`.',
        '- een\n- twee\n\n1. a\n2. b',
        '> een citaat\n\n# kop\n\n| a | b |\n|---|---|\n| 1 | 2 |',
        '5 < 6 en 7 > 3 en a<b en x<y z',
        'ik <3 koken',
        'zie [de site](https://example.org/pad?x=1) of [mail](mailto:a@b.nl)',
        '![portret](images/portret-1.jpg)',
        '![gerecht](images/gerecht-2.png "Foto: Sari")',
        'https://bare-url.example.org staat gewoon als tekst',
        'een voetnoot[^1]\n\n[^1]: de tekst van de voetnoot',
      ]) {
        expect(found(zone), isEmpty, reason: zone);
      }
    });
  });

  group('rule 1 — no marker-shaped line, in a fence or out of it', () {
    test('every marker name, with attributes or without', () {
      for (final line in [
        '<!-- answer -->',
        '<!-- /field id=x -->',
        '<!-- field id=x type=text -->',
        '<!-- form id=x -->',
        '<!-- notice -->',
        '<!-- /notice -->',
        '  <!-- answer -->',
      ]) {
        expect(found('tekst\n$line\nmeer'), [
          'answer-contains-marker',
        ], reason: line);
      }
    });

    test('also inside a fence', () {
      expect(found('```\n<!-- answer -->\n```'), ['answer-contains-marker']);
      expect(found('~~~\n<!-- /field id=x -->\n~~~'), [
        'answer-contains-marker',
      ]);
    });

    test('a malformed marker-shaped line counts too', () {
      expect(found('<!-- field id= -->'), ['answer-contains-marker']);
      expect(found('<!-- answer --> trailing'), ['answer-contains-marker']);
    });

    test('a marker line is reported once, not also as raw HTML', () {
      expect(found('<!-- answer -->'), ['answer-contains-marker']);
    });

    test('an ordinary comment is raw HTML, not a marker', () {
      expect(found('<!-- a note -->'), ['answer-contains-html']);
    });

    test('says on which line', () {
      final p = problems('a\nb\n<!-- answer -->', firstLine: 40);
      expect(p.single.line, 42);
    });
  });

  group('rule 2 — no raw HTML outside fenced code', () {
    test('tags, comments, doctypes, processing instructions', () {
      for (final html in [
        '<b>vet</b>',
        '<div class="x">',
        '<br/>',
        '<br />',
        '<img src="x">',
        '<a href="https://x.org">x</a>',
        'tekst <span>x</span> tekst',
        '<!-- verborgen -->',
        '<!DOCTYPE html>',
        '<?php echo 1; ?>',
        '<script>alert(1)</script>',
        '<https://example.org>',
        '<mailto:a@b.nl>',
        '<a@b.nl>',
        '<x-custom-tag>',
      ]) {
        expect(found(html), ['answer-contains-html'], reason: html);
      }
    });

    test('inside a fenced block it is literal code', () {
      expect(found('```html\n<div>x</div>\n<!-- c -->\n```'), isEmpty);
      expect(found('~~~\n<script>1</script>\n~~~'), isEmpty);
    });

    test('inside an inline code span it is literal code', () {
      expect(found('gebruik `<b>` voor vet'), isEmpty);
      expect(found('gebruik ``<b>`x</b>`` voor vet'), isEmpty);
    });

    test('a backslash-escaped angle bracket is text', () {
      expect(found(r'a \<b> c'), isEmpty);
    });

    test('a code span closes only on a run of exactly its own length', () {
      expect(found('`a``<b>x</b>`'), isEmpty);
      expect(found('``a`<b>x</b>``'), isEmpty);
      expect(found('`x```<b>y</b>`'), isEmpty);
      expect(found('`a`<b>x</b>`b`'), ['answer-contains-html']);
    });

    test('an unclosed inline code span does not hide HTML', () {
      expect(found('`oops <b>x</b>'), ['answer-contains-html']);
    });

    test('says on which line', () {
      expect(problems('ok\n<b>x</b>', firstLine: 10).single.line, 11);
    });
  });

  group('rule 3 — a fence must close inside the zone', () {
    test('an unclosed fence is reported at the line that opened it', () {
      final p = problems('tekst\n```\ncode zonder einde', firstLine: 5);
      expect(p.map((x) => x.code), [FormIssueCode.answerUnclosedFence]);
      expect(p.single.line, 6);
    });

    test('a closed fence is fine, with either character', () {
      expect(found('```\nx\n```'), isEmpty);
      expect(found('~~~~\nx\n~~~~'), isEmpty);
    });

    test('a longer closing fence closes; a shorter one does not', () {
      expect(found('````\nx\n`````'), isEmpty);
      expect(found('````\nx\n```'), ['answer-unclosed-fence']);
    });

    test('a different character does not close it', () {
      expect(found('```\nx\n~~~'), ['answer-unclosed-fence']);
    });

    test(
      'HTML after an unclosed fence is inside it, so only the fence is reported',
      () {
        expect(found('```\n<b>x</b>'), ['answer-unclosed-fence']);
      },
    );
  });

  group('rule 4 — images only as images/<name>', () {
    test('the name grammar of §5.4', () {
      for (final ok in [
        'images/portret-1.jpg',
        'images/a.png',
        'images/gerecht-12.webp',
        'images/foto-1.heic',
        'images/${'a' * 64}.jpg',
      ]) {
        expect(found('![x]($ok)'), isEmpty, reason: ok);
      }
    });

    test('a name that only starts like a device name is fine', () {
      for (final ok in [
        'images/con-1.jpg',
        'images/console.jpg',
        'images/nul-1.webp',
        'images/xnul.jpg',
        'images/com10.jpg',
        'images/lpt-3.png',
        'images/com.heic',
        'images/a-con.jpg',
      ]) {
        expect(found('![x]($ok)'), isEmpty, reason: ok);
      }
    });

    test('everything else is a bad image', () {
      for (final bad in [
        'http://example.org/x.png',
        'https://example.org/x.png',
        '//example.org/x.png',
        'data:image/png;base64,AAAA',
        'javascript:alert(1)',
        '../images/x.jpg',
        '/images/x.jpg',
        'images/../x.jpg',
        'images/sub/x.jpg',
        'images/X.jpg',
        'images/x.JPG',
        'images/x.gif',
        'images/x.svg',
        'images/x',
        'images/.jpg',
        'images/x y.jpg',
        'images/${'a' * 65}.jpg',
        // The names Windows keeps for devices: on its disks these are not files.
        for (final device in [
          'con',
          'prn',
          'aux',
          'nul',
          for (var n = 0; n <= 9; n++) ...['com$n', 'lpt$n'],
        ])
          'images/$device.png',
        'x.jpg',
        'file:///etc/passwd',
        '',
      ]) {
        expect(found('![x]($bad)'), ['answer-bad-image'], reason: bad);
      }
    });

    test(
      'a title is allowed, an angle-bracketed destination is read through',
      () {
        expect(found('![x](images/a-1.jpg "Foto: Sari")'), isEmpty);
        expect(found('![x](<images/a-1.jpg>)'), isEmpty);
        expect(found('![x](<http://x.org/a.png>)'), ['answer-bad-image']);
        expect(found('[x](<https://x.org/a>)'), isEmpty);
      },
    );

    test(
      'a construct that is not quite an image is refused, not guessed at',
      () {
        for (final odd in [
          '![x](images/a-1.jpg extra)',
          '![x](images/a-1.jpg',
          '![x](http://x/a.png',
          '![x](images/x y.jpg)',
        ]) {
          expect(found(odd), contains('answer-bad-image'), reason: odd);
        }
      },
    );

    test(
      'a reference-style image is refused: its definition could be remote',
      () {
        expect(found('![x][ref]'), ['answer-bad-image']);
        expect(found('![x][]'), ['answer-bad-image']);
        expect(found('![x]'), ['answer-bad-image']);
      },
    );

    test('reports the destination and every bad image on a line', () {
      final p = problems(
        '![a](http://x/1.png) en ![b](images/ok-1.jpg) en ![c](ftp://y/2.png)',
      );
      expect(p.map((x) => x.facts['dest']), [
        'http://x/1.png',
        'ftp://y/2.png',
      ]);
    });

    test('images inside a fence or inline code are text', () {
      expect(found('```\n![x](http://x/1.png)\n```'), isEmpty);
      expect(found('schrijf `![x](http://x/1.png)` zo'), isEmpty);
    });
  });

  group('rule 5 — links only https: and mailto:', () {
    test('the allowed schemes, in any case', () {
      for (final ok in [
        'https://example.org',
        'HTTPS://example.org',
        'mailto:a@b.nl',
        'MAILTO:a@b.nl',
        '<https://example.org>',
      ]) {
        expect(found('[x]($ok)'), isEmpty, reason: ok);
      }
    });

    test('everything else is a bad link', () {
      for (final bad in [
        'http://example.org',
        'javascript:alert(1)',
        'JavaScript:alert(1)',
        'data:text/html,x',
        'file:///etc/passwd',
        'ftp://example.org',
        'tel:+31612345678',
        '//example.org',
        '/pad',
        'pad/naar/iets',
        '#anker',
        'images/a-1.jpg',
        '',
      ]) {
        expect(found('[x]($bad)'), ['answer-bad-link'], reason: bad);
      }
    });

    test('a title after a good destination is fine', () {
      expect(found('[x](https://example.org "titel")'), isEmpty);
    });

    test('a construct that is not quite a link is refused, not guessed at', () {
      for (final odd in [
        '[x](javascript:alert 1)',
        '[x](https://a.org',
        '[x](ht tp://a)',
      ]) {
        expect(found(odd), contains('answer-bad-link'), reason: odd);
      }
    });

    test('a link definition is checked like a link', () {
      expect(found('[ref]: https://example.org'), isEmpty);
      expect(found('[ref]: javascript:alert(1)'), ['answer-bad-link']);
      expect(found('  [ref]: http://example.org'), ['answer-bad-link']);
    });

    test('an image is judged as an image, not also as a link', () {
      expect(found('![x](http://x/1.png)'), ['answer-bad-image']);
    });

    test('links inside a fence or inline code are text', () {
      expect(found('```\n[x](javascript:alert(1))\n```'), isEmpty);
      expect(found('`[x](javascript:alert(1))`'), isEmpty);
    });

    test('says on which line, and what the destination was', () {
      final p = problems('ok\n[x](http://a.org)', firstLine: 3);
      expect(p.single.line, 4);
      expect(p.single.facts['dest'], 'http://a.org');
    });
  });

  group('several rules at once', () {
    test('every violation is reported, in line order', () {
      final zone = [
        '<b>x</b>', // html
        '[x](ftp://a)', // link
        '![y](http://b/c.png)', // image
        '<!-- answer -->', // marker
        '```', // unclosed fence
        'code',
      ].join('\n');
      expect(found(zone), [
        'answer-contains-html',
        'answer-bad-link',
        'answer-bad-image',
        'answer-contains-marker',
        'answer-unclosed-fence',
      ]);
    });

    test('a marker line is recognised with CRLF line endings too', () {
      expect(found('a\r\n<!-- answer -->\r\nb'), ['answer-contains-marker']);
    });

    test('CRLF changes nothing', () {
      expect(found('<b>x</b>\r\n[x](ftp://a)\r\n'), [
        'answer-contains-html',
        'answer-bad-link',
      ]);
    });

    test('never throws on arbitrary text, and is quick', () {
      final pieces = [
        '<',
        '>',
        '![',
        '](',
        ')',
        '[',
        ']',
        '`',
        '``',
        '```',
        '~~~',
        '\\',
        '<!--',
        '-->',
        'a',
        ' ',
        '\n',
        'http://',
        'images/a.jpg',
        '<b>',
      ];
      var seed = 7;
      int next() {
        seed = (seed * 1103515245 + 12345) & 0x7fffffff;
        return seed;
      }

      final sw = Stopwatch()..start();
      for (var round = 0; round < 2000; round++) {
        final text = [
          for (var i = 0; i < 30; i++) pieces[next() % pieces.length],
        ].join();
        answerSafetyIssues(text);
      }
      expect(sw.elapsedMilliseconds, lessThan(5000));
    });
  });
}
