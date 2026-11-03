import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/editor_provider.dart';
import 'package:ocideck/widgets/editors/deck_search_workspace.dart';
import 'package:ocideck/widgets/editors/editor_text_controller.dart';
import 'package:ocideck/widgets/editors/markdown_find_bar.dart';

void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  testWidgets(
    'first Enter reveals exact field among identical text without editing or stealing focus',
    (tester) async {
      final slide = Slide(
        id: 'one',
        type: SlideType.twoBullets,
        title: 'zelfde',
        bullets: ['zelfde'],
        bullets2: ['zelfde zelfde'],
      );
      final md = MarkdownService();
      final notifier = DeckNotifier(
        md,
        FileService(md, ImageService(), () => const ThemeProfile()),
      )..loadDeck(Deck(title: 'Test', slides: [slide]));
      final container = ProviderContainer(
        overrides: [deckProvider.overrideWith((ref) => notifier)],
      );
      addTearDown(container.dispose);
      final title = EditorTextController(
        text: slide.title,
        searchFieldId: 'title',
      );
      final left = EditorTextController(
        text: 'zelfde',
        searchFieldId: 'bullets.0',
      );
      final right = EditorTextController(
        text: 'zelfde zelfde',
        searchFieldId: 'bullets2.0',
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: DeckSearchWorkspace(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      TextField(controller: title),
                      const SizedBox(height: 1200),
                      TextField(controller: left),
                      TextField(controller: right),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      container
          .read(editorProvider.notifier)
          .requestMarkdownFind(showReplace: false);
      await tester.pumpAndSettle();
      final query = find
          .descendant(
            of: find.byType(MarkdownFindBar),
            matching: find.byType(TextField),
          )
          .first;
      await tester.enterText(query, 'zelfde');
      await tester.pump();
      expect(title.selection.isCollapsed, isTrue);
      final revision = notifier.currentState.revision;
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        title.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        left.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
      expect(right.selection.isCollapsed, isTrue);
      final editable = tester.widget<EditableText>(
        find.descendant(of: query, matching: find.byType(EditableText)),
      );
      expect(editable.focusNode.hasFocus, isTrue);
      expect(notifier.currentState.revision, revision);
      final selectedField = find.byWidgetPredicate(
        (w) => w is TextField && identical(w.controller, left),
      );
      expect(
        tester
            .getRect(selectedField)
            .overlaps(tester.getRect(find.byType(DeckSearchWorkspace))),
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(
        right.selection,
        const TextSelection(baseOffset: 7, extentOffset: 13),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(MarkdownFindBar), findsNothing);
      final selectedEditable = tester.widget<EditableText>(
        find.byWidgetPredicate(
          (w) => w is EditableText && identical(w.controller, right),
        ),
      );
      expect(selectedEditable.focusNode.hasFocus, isTrue);
      await tester.pumpWidget(const SizedBox());
      title.dispose();
      left.dispose();
      right.dispose();
    },
  );
}
