import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/markdown_body_blocks.dart';

void main() {
  // Text measurement needs a binding; parsing does not, but one setup covers both.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('parseMarkdownBodyBlocks', () {
    test('empty or blank input yields no blocks', () {
      expect(parseMarkdownBodyBlocks(''), isEmpty);
      expect(parseMarkdownBodyBlocks('   \n  '), isEmpty);
    });

    test('keeps a fenced code block intact', () {
      final blocks = parseMarkdownBodyBlocks('```dart\ncode();\n```');
      expect(blocks, hasLength(1));
      expect(blocks.single.markdown, '```dart\ncode();\n```');
    });

    test('keeps a multi-line display-math block intact', () {
      final blocks = parseMarkdownBodyBlocks('\$\$\nx = y\n\$\$');
      expect(blocks, hasLength(1));
      expect(blocks.single.markdown, '\$\$\nx = y\n\$\$');
    });

    test('treats a one-line display-math line as its own block', () {
      final blocks = parseMarkdownBodyBlocks(r'$$E = mc^2$$');
      expect(blocks, hasLength(1));
      expect(blocks.single.markdown, r'$$E = mc^2$$');
    });

    test('a heading after text starts a new block', () {
      final blocks = parseMarkdownBodyBlocks('alpha\nbeta\n## Heading\ngamma');
      expect(blocks.map((b) => b.markdown), [
        'alpha\nbeta',
        '## Heading\ngamma',
      ]);
    });

    test('blank lines become empty separator blocks', () {
      final blocks = parseMarkdownBodyBlocks('a\n\nb');
      expect(blocks.map((b) => b.markdown), ['a', '', 'b']);
    });

    test('a level-1 heading after text starts a new block', () {
      final blocks = parseMarkdownBodyBlocks('alpha\n# Kop\ngamma');
      expect(blocks.map((b) => b.markdown), ['alpha', '# Kop\ngamma']);
    });
  });

  group('markdownBodyHeight', () {
    double measure(String md) => markdownBodyHeight(
      markdown: md,
      contentW: 400,
      refW: 800,
      bodySize: 24,
      font: 'Roboto',
    );

    test('an empty body has zero height', () {
      expect(measure(''), 0);
    });

    test('a non-empty body has a finite, positive height', () {
      final one = measure('Just one line.');
      expect(one, greaterThan(0));
      expect(one.isFinite, isTrue);
    });

    test('more content is taller than less', () {
      final one = measure('One short line.');
      final many = measure(
        'Line one.\n\nLine two.\n\nLine three with several more words that wrap.',
      );
      expect(many, greaterThan(one));
    });

    // Koppen meten op hun eigen (grotere) korpsgrootte, niet op bodygrootte —
    // anders denkt de paginering dat een kop-rijke pagina past terwijl de
    // render hem groter tekent. bodySize 16 < kop2 (0.03*800=24) < kop1
    // (0.04*800=32), dus beide relaties zijn strikt.
    double measureSmallBody(String md) => markdownBodyHeight(
      markdown: md,
      contentW: 400,
      refW: 800,
      bodySize: 16,
      font: 'Roboto',
    );

    test('a level-1 heading measures taller than the same text as body', () {
      expect(measureSmallBody('# Kop'), greaterThan(measureSmallBody('Kop')));
    });

    test('a level-2 heading measures taller than the same text as body', () {
      expect(measureSmallBody('## Kop'), greaterThan(measureSmallBody('Kop')));
    });
  });

  group('displayMathTex', () {
    test('extracts the inner tex of a one-line display-math block', () {
      expect(displayMathTex(r'$$E = mc^2$$'), 'E = mc^2');
    });

    test('extracts the inner tex of a multi-line display-math block', () {
      expect(displayMathTex('\$\$\n  a + b  \n\$\$'), 'a + b');
    });

    test('is null for a non-math block', () {
      expect(displayMathTex('gewone alinea'), isNull);
      expect(displayMathTex(r'inline $x$ math'), isNull);
    });

    test('is null for an empty formula', () {
      expect(displayMathTex(r'$$$$'), isNull);
      expect(displayMathTex('\$\$\n\n\$\$'), isNull);
    });
  });

  group('displayMathBlockHeight', () {
    // De render (`_markdownMathBlock`) tekent op vaste `refW * 0.032`; een gewone
    // regel is dus ~die grootte + padding, en hoogte-toevoegende constructies
    // reserveren strikt méér. De exacte ijking tegen de echte `Math.tex`-hoogte
    // staat in math_block_height_test.dart; hier alleen de monotonie.
    const refW = 1280.0;

    test('a fraction reserves more height than a plain line', () {
      expect(
        displayMathBlockHeight(r'\frac{a}{b}', refW),
        greaterThan(displayMathBlockHeight('a = b', refW)),
      );
    });

    test('a big operator with limits reserves the most', () {
      expect(
        displayMathBlockHeight(r'\sum_{i=0}^{n} i', refW),
        greaterThan(displayMathBlockHeight(r'\frac{a}{b}', refW)),
      );
    });
  });
}
