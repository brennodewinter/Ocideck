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
  });
}
