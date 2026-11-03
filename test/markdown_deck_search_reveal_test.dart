import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/deck_source_checks.dart';
import 'package:ocideck/widgets/editors/markdown_deck_editor.dart';
import 'package:ocideck/widgets/editors/markdown_find_bar.dart';

void main() {
  testWidgets(
    'search reveals end of a long wrapped source line using rendered geometry',
    (tester) async {
      // De validatie-isolate valt buiten de widgettestklok. Zoals in de
      // broneditorsuite draait deze onafhankelijke scan hier synchroon mee.
      final originalRunner = deckChecksRunner;
      deckChecksRunner = (args) async => deckSourceChecks(args);
      addTearDown(() => deckChecksRunner = originalRunner);
      AppLocalizations.setActiveLanguageCode('nl');
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final source = '# Titel\n${'gewone woorden ' * 500}einddoel';
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: SizedBox(
                width: 1000,
                child: MarkdownDeckEditor(
                  initialContent: source,
                  onApply: (_) => true,
                  parseError: false,
                  onExitMarkdown: () {},
                  onScopeChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField).last);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      final query = find
          .descendant(
            of: find.byType(MarkdownFindBar),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(query, 'einddoel');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      final sourceField = find.byWidgetPredicate(
        (w) => w is EditableText && w.controller.text == source,
      );
      final state = tester.state<EditableTextState>(sourceField);
      final caret = state.renderEditable.getLocalRectForCaret(
        TextPosition(offset: source.length),
      );
      expect(caret.top, greaterThanOrEqualTo(0));
      expect(
        caret.bottom,
        lessThanOrEqualTo(state.renderEditable.size.height + 1),
      );
      expect(state.widget.controller.selection.end, source.length);
    },
  );
}
