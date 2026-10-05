import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/inline_markdown.dart';

void main() {
  group('stripInlineMarkdown', () {
    test('removes emphasis markers but keeps the text', () {
      expect(
        stripInlineMarkdown('Dit is **vet** en *cursief*.'),
        'Dit is vet en cursief.',
      );
      expect(stripInlineMarkdown('Een `code` stukje'), 'Een code stukje');
      expect(stripInlineMarkdown('~~weg~~ ermee'), 'weg ermee');
    });

    test('keeps link text and drops the url', () {
      expect(
        stripInlineMarkdown('Zie [de site](https://example.com) nu'),
        'Zie de site nu',
      );
    });

    test('leaves plain text untouched and is cheap', () {
      expect(stripInlineMarkdown('Gewoon platte tekst'), 'Gewoon platte tekst');
    });

    test('unterminated markers stay literal', () {
      expect(stripInlineMarkdown('2 * 3 = 6'), '2 * 3 = 6');
      expect(stripInlineMarkdown('een **halve vet'), 'een **halve vet');
    });

    test('escaped markers become literal characters', () {
      expect(
        stripInlineMarkdown(r'letterlijk \*sterren\*'),
        'letterlijk *sterren*',
      );
      expect(stripInlineMarkdown(r'Geen \- streepje'), 'Geen - streepje');
    });
  });

  group('parseInlineRuns', () {
    test('splits styled and plain runs', () {
      final runs = parseInlineRuns('a **b** c');
      expect(runs.map((r) => r.text).toList(), ['a ', 'b', ' c']);
      expect(runs[0].bold, isFalse);
      expect(runs[1].bold, isTrue);
      expect(runs[2].bold, isFalse);
    });

    test('__underscores__ are bold, like **asterisks**', () {
      final runs = parseInlineRuns('__vet__ en **ook**');
      expect(runs.map((r) => r.text).toList(), ['vet', ' en ', 'ook']);
      expect(runs[0].bold, isTrue);
      expect(runs[1].bold, isFalse);
      expect(runs[2].bold, isTrue);
    });

    test('single _underscores_ stay italic', () {
      final runs = parseInlineRuns('_cursief_');
      expect(runs.single.text, 'cursief');
      expect(runs.single.italic, isTrue);
      expect(runs.single.bold, isFalse);
    });

    test('nested emphasis inside a link carries both flags', () {
      final runs = parseInlineRuns('[**klik**](https://x.io)');
      expect(runs, hasLength(1));
      expect(runs.single.text, 'klik');
      expect(runs.single.bold, isTrue);
      expect(runs.single.link, 'https://x.io');
    });

    test('code spans are literal (no inner parsing)', () {
      final runs = parseInlineRuns('`a*b*c`');
      expect(runs, hasLength(1));
      expect(runs.single.text, 'a*b*c');
      expect(runs.single.code, isTrue);
    });

    test('combines bold and italic when nested', () {
      final runs = parseInlineRuns('**_allebei_**');
      expect(runs.single.bold, isTrue);
      expect(runs.single.italic, isTrue);
      expect(runs.single.text, 'allebei');
    });

    test('merges adjacent runs with identical styling', () {
      // 'a' + escaped '*' + 'b' → één platte run "a*b"
      final runs = parseInlineRuns(r'a\*b');
      expect(runs, hasLength(1));
      expect(runs.single.text, 'a*b');
    });
  });

  // Geïmporteerde tekst (pptx/odp/key) wordt aan de importgrens HTML-escaped
  // (#876): `&` → `&amp;`, `<` → `&lt;`, `>` → `&gt;`. Dat is correct in het
  // `.md` (de HTML-export decodeert het weer), maar de Flutter-preview rendert
  // via `parseInlineRuns`, dus híer moeten de named entities terug. Alleen
  // named, nooit numeriek — anders wordt een bron-`&#60;` alsnog `<` en dat is
  // precies de evasie die de sanitizer blokkeert (#1299).
  group('HTML entity decoding (imported text)', () {
    test('decodes named entities in plain text', () {
      expect(
        parseInlineRuns(
          'Where to find, copy &amp; paste?',
        ).map((r) => r.text).join(),
        'Where to find, copy & paste?',
      );
      expect(
        parseInlineRuns(
          'a &lt; b &gt; c &quot;d&quot;',
        ).map((r) => r.text).join(),
        'a < b > c "d"',
      );
    });

    test('leaves numeric entities untouched (evasion guard)', () {
      expect(
        parseInlineRuns('&#60;script&#62;').map((r) => r.text).join(),
        '&#60;script&#62;',
      );
    });

    test('code spans keep entities literal', () {
      final runs = parseInlineRuns('`a &amp; b`');
      expect(runs, hasLength(1));
      expect(runs.single.code, isTrue);
      expect(runs.single.text, 'a &amp; b');
    });
  });

  // Marp staat inline-HTML toe in koppen: `# A<br>B` rendert als
  // `<h1>A<br />B</h1>`. De parser kende geen HTML, dus het merkteken verscheen
  // letterlijk op de titeldia (#2274). Alleen `<br>` wordt vertaald — een echte
  // HTML-parser invoegen zou meer weggooien dan Marp belooft.
  group('inline HTML <br> (Marp)', () {
    test('renders <br> as a line break', () {
      expect(parseInlineRuns('First<br>Second').single.text, 'First\nSecond');
    });

    test('accepts the Marp/HTML spellings, case-insensitive', () {
      expect(stripInlineMarkdown('a<br/>b'), 'a\nb');
      expect(stripInlineMarkdown('a<br />b'), 'a\nb');
      expect(stripInlineMarkdown('a<BR>b'), 'a\nb');
      expect(stripInlineMarkdown('a<br clear="all">b'), 'a\nb');
    });

    test('keeps the break inside the active styling', () {
      final runs = parseInlineRuns('**a<br>b**');
      expect(runs.single.text, 'a\nb');
      expect(runs.single.bold, isTrue);
    });

    test('leaves other inline tags literal', () {
      expect(
        parseInlineRuns('a<span>x</span>b').map((r) => r.text).join(),
        'a<span>x</span>b',
      );
      expect(parseInlineRuns('a<brx>b').map((r) => r.text).join(), 'a<brx>b');
    });

    test('a <br> inside a code span stays literal', () {
      expect(parseInlineRuns('`a<br>b`').single.text, 'a<br>b');
    });

    test('hasInlineMarkdown sees <br> (measurement path)', () {
      expect(hasInlineMarkdown('First<br>Second'), isTrue);
      expect(hasInlineMarkdown('plain <span> text'), isFalse);
    });
  });

  // `decodeNamedHtmlEntities` is de publieke helper voor platte-`Text`-plekken
  // die geïmporteerde tekst tonen maar niet door `parseInlineRuns` gaan
  // (chart-labels, timeline-events) — #1299 follow-up.
  group('decodeNamedHtmlEntities', () {
    test('decodes the four named entities', () {
      expect(decodeNamedHtmlEntities('a &amp; b'), 'a & b');
      expect(decodeNamedHtmlEntities('a &lt; b &gt; c'), 'a < b > c');
      expect(decodeNamedHtmlEntities('&quot;q&quot;'), '"q"');
    });

    test('leaves numeric entities untouched (evasion guard)', () {
      expect(decodeNamedHtmlEntities('&#60;script&#62;'), '&#60;script&#62;');
    });

    test('no-op without an ampersand (short-circuit)', () {
      expect(decodeNamedHtmlEntities('plain text'), 'plain text');
      expect(decodeNamedHtmlEntities(''), '');
    });
  });
}
