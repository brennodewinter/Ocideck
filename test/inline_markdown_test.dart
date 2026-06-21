import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/slides/inline_markdown.dart';

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
}
