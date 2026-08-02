import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/text_search.dart';
import 'package:ocideck/widgets/editors/markdown_smart_input_formatter.dart';
import 'package:ocideck/widgets/editors/markdown_source_controller.dart';

void main() {
  testWidgets('source controller preserves text while creating styled spans', (
    tester,
  ) async {
    final controller = MarkdownSourceController(
      text: '# Titel\n\n- item met [link](https://example.test)',
    );
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );

    expect(span.toPlainText(), controller.text);
    expect(span.children, isNotEmpty);
    controller.dispose();
  });

  testWidgets('all search matches and active match receive backgrounds', (
    tester,
  ) async {
    final controller = MarkdownSourceController(text: 'een een');
    controller.showSearchMatches(const [
      TextMatchRange(0, 3),
      TextMatchRange(4, 7),
    ], 1);
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (ctx) {
            context = ctx;
            return const SizedBox();
          },
        ),
      ),
    );

    final span = controller.buildTextSpan(
      context: context,
      style: const TextStyle(),
      withComposing: false,
    );
    final styled = span.children!.cast<TextSpan>();
    expect(
      styled.where((part) => part.style?.backgroundColor != null),
      hasLength(2),
    );
    expect(
      styled[0].style?.backgroundColor,
      isNot(styled.last.style?.backgroundColor),
    );
    controller.dispose();
  });

  group('smart Markdown input', () {
    const formatter = MarkdownSmartInputFormatter();

    test('continues a bullet after Enter', () {
      const oldValue = TextEditingValue(
        text: '- eerste',
        selection: TextSelection.collapsed(offset: 8),
      );
      const newValue = TextEditingValue(
        text: '- eerste\n',
        selection: TextSelection.collapsed(offset: 9),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, '- eerste\n- ');
      expect(result.selection.extentOffset, result.text.length);
    });

    test('increments a numbered list after Enter', () {
      const oldValue = TextEditingValue(
        text: '9. negende',
        selection: TextSelection.collapsed(offset: 10),
      );
      const newValue = TextEditingValue(
        text: '9. negende\n',
        selection: TextSelection.collapsed(offset: 11),
      );

      expect(
        formatter.formatEditUpdate(oldValue, newValue).text,
        '9. negende\n10. ',
      );
    });

    test('pairs link brackets and leaves the caret inside', () {
      const oldValue = TextEditingValue(
        selection: TextSelection.collapsed(offset: 0),
      );
      const newValue = TextEditingValue(
        text: '[',
        selection: TextSelection.collapsed(offset: 1),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, '[]');
      expect(result.selection.extentOffset, 1);
    });

    test('typing an existing closing bracket advances without duplicating', () {
      const oldValue = TextEditingValue(
        text: '[]',
        selection: TextSelection.collapsed(offset: 1),
      );
      const newValue = TextEditingValue(
        text: '[]]',
        selection: TextSelection.collapsed(offset: 2),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, '[]');
      expect(result.selection.extentOffset, 2);
    });

    test('third backtick completes a fenced code block', () {
      const oldValue = TextEditingValue(
        text: '``',
        selection: TextSelection.collapsed(offset: 2),
      );
      const newValue = TextEditingValue(
        text: '```',
        selection: TextSelection.collapsed(offset: 3),
      );

      final result = formatter.formatEditUpdate(oldValue, newValue);

      expect(result.text, '```\n\n```');
      expect(result.selection.extentOffset, 4);
    });
  });
}
