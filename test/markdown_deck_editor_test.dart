import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';
import 'package:ocideck/widgets/editors/markdown_find_bar.dart';

Widget _host({
  required String content,
  required void Function(String) onApply,
}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: MarkdownDeckEditor(
          initialContent: content,
          onApply: (md) {
            onApply(md);
            return true;
          },
          parseError: false,
          onExitMarkdown: () {},
          onScopeChanged: (_) {},
        ),
      ),
    ),
  );
}

Future<void> sendControlKey(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
}

void main() {
  testWidgets('opens find bar on Ctrl+F', (tester) async {
    await tester.pumpWidget(
      _host(content: '# Titel\n\nfoo bar', onApply: (_) {}),
    );

    await tester.tap(find.byType(TextField).last);
    await tester.pump();
    await sendControlKey(tester, LogicalKeyboardKey.keyF);
    await tester.pumpAndSettle();

    expect(find.byType(MarkdownFindBar), findsOneWidget);
  });

  testWidgets('finds matches and navigates in markdown text', (tester) async {
    await tester.pumpWidget(
      _host(content: 'alpha beta alpha', onApply: (_) {}),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarkdownDeckEditor)),
    );
    container
        .read(editorProvider.notifier)
        .requestMarkdownFind(showReplace: false);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'alpha');
    await tester.pumpAndSettle();

    expect(find.text('1 / 2'), findsOneWidget);
  });

  testWidgets('replace all updates live markdown text', (tester) async {
    String? applied;
    await tester.pumpWidget(
      _host(content: 'foo bar foo', onApply: (md) => applied = md),
    );

    final container = ProviderScope.containerOf(
      tester.element(find.byType(MarkdownDeckEditor)),
    );
    container
        .read(editorProvider.notifier)
        .requestMarkdownFind(showReplace: true);
    await tester.pumpAndSettle();

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'foo');
    await tester.enterText(fields.at(1), 'baz');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vervang alles'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Toepassen'));
    await tester.pumpAndSettle();

    expect(applied, 'baz bar baz');
  });

  testWidgets('accentuates finding lines in the code after checking', (
    tester,
  ) async {
    bool isHighlightLayer(Widget w) =>
        w is CustomPaint &&
        w.painter.runtimeType.toString() == '_IssueHighlightPainter';

    await tester.pumpWidget(
      _host(
        // Unclosed front matter → a validation error on a specific line.
        content: '---\nmarp: true\n# nooit gesloten\n',
        onApply: (_) {},
      ),
    );

    // Nothing is checked yet, so no code is accentuated.
    expect(find.byWidgetPredicate(isHighlightLayer), findsNothing);

    await tester.tap(find.text('Controleren'));
    await tester.pump();

    // After checking, the finding is painted behind the code.
    expect(find.byWidgetPredicate(isHighlightLayer), findsOneWidget);

    // Editing clears the stale findings, so the accent disappears again.
    await tester.enterText(
      find.byType(TextField).first,
      '---\nmarp: true\n---\n\n# ok\n',
    );
    await tester.pump();
    expect(find.byWidgetPredicate(isHighlightLayer), findsNothing);
  });
}
