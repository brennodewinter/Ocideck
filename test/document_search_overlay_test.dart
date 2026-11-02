import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/reader/document_search_overlay.dart';
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/table_edit_controller.dart';
import 'package:ocideck/widgets/reader/table_editable_cell.dart';
import 'package:ocideck/theme/app_theme.dart';

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
