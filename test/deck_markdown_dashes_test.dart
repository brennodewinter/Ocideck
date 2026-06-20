import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/deck_markdown_dashes.dart';

void main() {
  group('escapeDeckMarkdownDashLines', () {
    test('escapes standalone dash lines only', () {
      const input = 'Intro\n--\n---\nNiet aangepast: --- tekst';
      final escaped = escapeDeckMarkdownDashLines(input);
      expect(escaped, isNot(contains('\n---\n')));
      expect(unescapeDeckMarkdownDashLines(escaped), input);
    });

    test('preserves indentation around dash lines', () {
      const input = '  --\n';
      final escaped = escapeDeckMarkdownDashLines(input);
      expect(escaped.startsWith('  '), isTrue);
      expect(unescapeDeckMarkdownDashLines(escaped), input);
    });
  });
}
