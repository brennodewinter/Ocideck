import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/rendering.dart';
import 'package:ocideck/widgets/reader/document_search_overlay.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/table_edit_controller.dart';
import 'package:ocideck/widgets/reader/table_editable_cell.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/utils/deck_text_search.dart';
import 'package:ocideck/utils/text_search.dart';
import 'package:ocideck/widgets/editors/deck_search_target.dart';

void main() {
  testWidgets(
    'markering onderscheidt twee treffers in dezelfde gewrapte alinea',
    (tester) async {
      Rect? active;
      final paragraph =
          'vooraf ${List.filled(20, 'lange tekst').join(' ')} kat en kat';
      Widget surface(int index) => MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 180,
            child: DocumentSearchOverlay(
              query: 'kat',
              activeIndex: index,
              onActiveRect: (rect) => active = rect,
              child: Text(paragraph),
            ),
          ),
        ),
      );
      await tester.pumpWidget(surface(0));
      await tester.pumpAndSettle();
      final first = active;
      expect(first, isNotNull);
      expect(first!.width, greaterThan(10));
      await tester.pumpWidget(surface(1));
      await tester.pumpAndSettle();
      expect(active, isNot(first));
      expect(active!.top, greaterThanOrEqualTo(first.top));
    },
  );

  testWidgets('gegenereerde lijstnummers zijn geen teksttreffers', (
    tester,
  ) async {
    Rect? active;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentSearchOverlay(
            query: '1',
            activeIndex: 0,
            onActiveRect: (rect) => active = rect,
            child: const DocumentMarkdownView('1. tekst met 1'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(active, isNotNull);
    expect(
      active!.left,
      greaterThan(40),
      reason: 'de inhoud staat rechts van het gegenereerde nummer',
    );
  });

  testWidgets(
    'onzichtbare tabelinvoer telt niet dubbel naast opgemaakte tekst',
    (tester) async {
      final editor = TableEditController(
        rows: [
          ['kat en **kat**'],
        ],
        alignments: [],
        onChanged: (_, _) {},
      );
      addTearDown(editor.dispose);
      Rect? active;
      Widget surface(int index) => MaterialApp(
        home: Scaffold(
          body: DocumentSearchOverlay(
            query: 'kat',
            activeIndex: index,
            onActiveRect: (rect) => active = rect,
            child: TableEditableCell(
              editor: editor,
              row: 0,
              column: 0,
              style: const TextStyle(fontSize: 16),
              pad: 4,
              caretColor: AppTheme.accent,
              linkColor: AppTheme.accent,
            ),
          ),
        ),
      );
      await tester.pumpWidget(surface(0));
      await tester.pumpAndSettle();
      final first = active;
      expect(first, isNotNull);
      await tester.pumpWidget(surface(1));
      await tester.pumpAndSettle();
      expect(active, isNotNull);
      expect(active!.left, greaterThan(first!.left));
      await tester.pumpWidget(surface(2));
      await tester.pumpAndSettle();
      expect(
        active,
        isNull,
        reason: 'er zijn twee zichtbare treffers, niet vier',
      );
    },
  );

  testWidgets(
    'presentatie zoeken toont exacte tweede opgemaakte treffer onderin lange cel',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final source =
          '**kat** ${List.filled(140, 'gewone tekst').join(' ')} **kat**';
      final editor = TableEditController(
        rows: [
          [source],
        ],
        alignments: [],
        onChanged: (_, _) {},
      );
      editor.cellController(0, 0).searchFieldId = 'tableRows.0.0';
      final scroll = ScrollController();
      final queryFocus = FocusNode();
      addTearDown(editor.dispose);
      addTearDown(scroll.dispose);
      addTearDown(queryFocus.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                TextField(focusNode: queryFocus, autofocus: true),
                Expanded(
                  child: DeckSearchTarget(
                    match: DeckTextMatch(
                      slideId: 'dia-1',
                      slideIndex: 0,
                      fieldId: 'tableRows.0.0',
                      fieldLabel: 'Tabel',
                      text: source,
                      range: TextMatchRange(
                        source.lastIndexOf('kat'),
                        source.lastIndexOf('kat') + 3,
                      ),
                      context: 'kat',
                    ),
                    signal: 1,
                    child: SingleChildScrollView(
                      controller: scroll,
                      child: SizedBox(
                        width: 200,
                        child: TableEditableCell(
                          editor: editor,
                          row: 0,
                          column: 0,
                          style: const TextStyle(fontSize: 16),
                          pad: 4,
                          caretColor: AppTheme.accent,
                          linkColor: AppTheme.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        scroll.offset,
        greaterThan(500),
        reason: tester
            .widgetList<DocumentSearchOverlay>(
              find.byType(DocumentSearchOverlay),
            )
            .map(
              (overlay) =>
                  '${overlay.query}/${overlay.activeIndex}/${overlay.revealSignal}',
            )
            .join(','),
      );
      final highlight = tester.getRect(
        find.byKey(const Key('document-search-highlight')),
      );
      expect(highlight.center.dy, inInclusiveRange(70, 630));
      final paragraph = tester.renderObject<RenderParagraph>(
        find
            .byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText().startsWith('kat gewone tekst'),
            )
            .first,
      );
      final plain = paragraph.text.toPlainText();
      final glyph = paragraph
          .getBoxesForSelection(
            TextSelection(
              baseOffset: plain.lastIndexOf('kat'),
              extentOffset: plain.length,
            ),
          )
          .single
          .toRect();
      expect(highlight.width, closeTo(glyph.width + 4, .01));
      expect(queryFocus.hasFocus, isTrue);
      expect(editor.cellController(0, 0).text, source);
      expect(
        editor.cellController(0, 0).selection,
        const TextSelection.collapsed(offset: -1),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'markering meet de exacte tweede treffer in bewerkbare tabelcel',
    (tester) async {
      final controller = TextEditingController(text: 'kat en kat');
      addTearDown(controller.dispose);
      Rect? active;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocumentSearchOverlay(
              query: 'kat',
              activeIndex: 1,
              onActiveRect: (rect) => active = rect,
              child: Table(
                children: [
                  TableRow(children: [TextField(controller: controller)]),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final first = active;
      expect(first, isNotNull);
      expect(first!.left, greaterThan(20));
      expect(first.width, lessThan(50));
      expect(controller.selection, const TextSelection.collapsed(offset: -1));
      expect(controller.text, 'kat en kat');
    },
  );
}
