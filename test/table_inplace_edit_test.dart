import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart' show TableAlign;
import 'package:ocideck/widgets/reader/document_markdown_view.dart';
import 'package:ocideck/widgets/reader/table_edit_controller.dart';

/// Een tabel bewerken ging via een dialoog met losse velden van gelijke
/// breedte: je zag daar niet wat je kreeg. Nu vul je de tabel in op de plek
/// waar hij staat, in de vorm waarin hij verschijnt — zoals in een rekenblad.
void main() {
  const markdown = '''
| Naam | Rol |
|------|-----|
| Aap | Tester |
| Noot | Bouwer |
''';

  late TableEditController editor;
  late List<List<List<String>>> emitted;
  late List<List<TableAlign>> emittedAligns;

  setUp(() {
    emitted = [];
    emittedAligns = [];
    editor = TableEditController(
      rows: const [
        ['Naam', 'Rol'],
        ['Aap', 'Tester'],
        ['Noot', 'Bouwer'],
      ],
      alignments: const [TableAlign.left, TableAlign.left],
      onChanged: (rows, aligns) {
        emitted.add(rows);
        emittedAligns.add(aligns);
      },
    );
    // Via addTearDown, niet tearDown: de focusnodes moeten weg vóórdat het
    // testraamwerk zijn FocusManager opruimt.
    addTearDown(() => editor.dispose());
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            child: DocumentMarkdownView(markdown, tableEditController: editor),
          ),
        ),
      ),
    );
  }

  testWidgets('elke cel is een invulveld binnen de gerenderde tabel', (
    tester,
  ) async {
    await pump(tester);
    // Zes cellen, en ze staan in een echte Table — dus met de kolomverdeling,
    // randen en huisstijl van de gelezen tabel, niet in een los formulier.
    expect(find.byType(Table), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(6));
  });

  testWidgets('typen in een cel schrijft het hele raster terug', (
    tester,
  ) async {
    await pump(tester);
    await tester.enterText(find.byType(TextField).at(2), 'Aapje');
    await tester.pump();

    expect(emitted.last[1][0], 'Aapje');
    expect(emitted.last[0], ['Naam', 'Rol'], reason: 'de kop blijft staan');
    expect(emitted.last[2], ['Noot', 'Bouwer']);
  });

  testWidgets('de tabel herschikt terwijl je typt', (tester) async {
    await pump(tester);
    final before =
        (tester.widget<Table>(find.byType(Table)).columnWidths![0]
                as FixedColumnWidth)
            .value;

    await tester.enterText(
      find.byType(TextField).at(2),
      'Verwerkingsverantwoordelijke',
    );
    await tester.pumpAndSettle();

    final after =
        (tester.widget<Table>(find.byType(Table)).columnWidths![0]
                as FixedColumnWidth)
            .value;
    expect(
      after,
      greaterThan(before),
      reason:
          'de kolom hoort mee te groeien met wat erin staat — dat is het punt '
          'van live invullen in plaats van een dialoog',
    );
  });

  testWidgets('de werkbalk verschijnt pas als de cursor in een cel staat', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byTooltip('Rij eronder'), findsNothing);

    await tester.tap(find.byType(TextField).at(2));
    await tester.pump();

    expect(find.byTooltip('Rij eronder'), findsOneWidget);
  });

  testWidgets('rij eronder invoegen doet dat bij de cel waar je staat', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(TextField).at(2)); // rij 1, kolom 0
    await tester.pump();
    await tester.tap(find.byTooltip('Rij eronder'));
    await tester.pump();

    expect(editor.rowCount, 4);
    expect(editor.rows[2], ['', ''], reason: 'de nieuwe rij staat op plek 2');
    expect(editor.rows[3], ['Noot', 'Bouwer']);
  });

  testWidgets('de koprij kan niet worden weggehaald', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(TextField).first); // de koprij
    await tester.pump();

    final button = tester.widget<IconButton>(
      find.ancestor(
        of: find.byTooltip('Rij weghalen'),
        matching: find.byType(IconButton),
      ),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('een kolom toevoegen groeit elke rij mee', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.tap(find.byTooltip('Kolom rechts'));
    await tester.pump();

    expect(editor.colCount, 3);
    expect(editor.rows.every((r) => r.length == 3), isTrue);
    expect(find.byType(TextField), findsNWidgets(9));
  });

  testWidgets('een rij verplaatsen kan zonder de tabel-editor erbij', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(TextField).at(4)); // rij 2, kolom 0
    await tester.pump();
    await tester.tap(find.byTooltip('Rij omhoog'));
    await tester.pump();

    expect(editor.rows[1], ['Noot', 'Bouwer']);
    expect(editor.rows[2], ['Aap', 'Tester']);
    expect(editor.rows[0], ['Naam', 'Rol'], reason: 'de kop blijft de kop');
  });

  testWidgets('de koprij schuift niet omhoog en niet omlaag', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    for (final tip in ['Rij omhoog', 'Rij omlaag']) {
      final button = tester.widget<IconButton>(
        find.ancestor(
          of: find.byTooltip(tip),
          matching: find.byType(IconButton),
        ),
      );
      expect(button.onPressed, isNull, reason: '$tip mag niet op de koprij');
    }
  });

  testWidgets('een kolom verplaatsen neemt de uitlijning mee', (tester) async {
    await pump(tester);
    await tester.tap(find.byType(TextField).at(1)); // rij 0, kolom 1
    await tester.pump();
    await tester.tap(find.byTooltip('Rechts uitlijnen'));
    await tester.pump();
    await tester.tap(find.byTooltip('Kolom naar links'));
    await tester.pump();

    expect(editor.rows[1], ['Tester', 'Aap']);
    expect(
      editor.alignments[0],
      TableAlign.right,
      reason: 'de uitlijning hoort bij de kolom, niet bij de plek',
    );
  });

  testWidgets('uitlijning is een kolomeigenschap en wordt teruggegeven', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.byType(TextField).at(3)); // rij 1, kolom 1
    await tester.pump();
    await tester.tap(find.byTooltip('Rechts uitlijnen'));
    await tester.pump();

    expect(editor.alignments[1], TableAlign.right);
    expect(emittedAligns.last[1], TableAlign.right);
  });

  group('toetsenbord', () {
    test('Tab op de laatste cel maakt een rij bij', () {
      final result = editor.handleCellKey(
        2,
        1,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.tab,
          logicalKey: LogicalKeyboardKey.tab,
          timeStamp: Duration.zero,
        ),
      );
      expect(result, KeyEventResult.handled);
      expect(editor.rowCount, 4);
      expect(editor.takePendingFocus(), (row: 3, col: 0));
    });

    test('Enter onderaan groeit de tabel in dezelfde kolom', () {
      editor.handleCellKey(
        2,
        1,
        const KeyDownEvent(
          physicalKey: PhysicalKeyboardKey.enter,
          logicalKey: LogicalKeyboardKey.enter,
          timeStamp: Duration.zero,
        ),
      );
      expect(editor.rowCount, 4);
      expect(editor.takePendingFocus(), (row: 3, col: 1));
    });

    group('pijltjes', () {
      KeyEventResult press(
        int r,
        int c,
        LogicalKeyboardKey key, {
        bool repeat = false,
      }) => editor.handleCellKey(
        r,
        c,
        repeat
            ? KeyRepeatEvent(
                physicalKey: PhysicalKeyboardKey.arrowRight,
                logicalKey: key,
                timeStamp: Duration.zero,
              )
            : KeyDownEvent(
                physicalKey: PhysicalKeyboardKey.arrowRight,
                logicalKey: key,
                timeStamp: Duration.zero,
              ),
      );

      void caretAt(int r, int c, int offset) {
        editor.cellController(r, c).selection = TextSelection.collapsed(
          offset: offset,
        );
      }

      test('midden in de tekst laat het pijltje de cel met rust', () {
        caretAt(1, 0, 1); // 'Aap', cursor na de A
        expect(
          press(1, 0, LogicalKeyboardKey.arrowRight),
          KeyEventResult.ignored,
        );
        expect(
          press(1, 0, LogicalKeyboardKey.arrowLeft),
          KeyEventResult.ignored,
        );
      });

      test('aan het eind van de tekst gaat rechts naar de volgende cel', () {
        caretAt(1, 0, 3); // achter 'Aap'
        expect(
          press(1, 0, LogicalKeyboardKey.arrowRight),
          KeyEventResult.handled,
        );
        expect(editor.cellController(1, 1).selection.baseOffset, 0);
      });

      test('links vanaf het begin gaat terug, cursor achteraan', () {
        caretAt(1, 1, 0);
        expect(
          press(1, 1, LogicalKeyboardKey.arrowLeft),
          KeyEventResult.handled,
        );
        final back = editor.cellController(1, 0);
        expect(back.selection.baseOffset, back.text.length);
        expect(back.selection.isCollapsed, isTrue);
      });

      test('omhoog en omlaag lopen door de rijen', () {
        caretAt(1, 1, 0);
        expect(
          press(1, 1, LogicalKeyboardKey.arrowDown),
          KeyEventResult.handled,
        );
        // De cel waar je binnenkomt staat geselecteerd, zoals bij Tab en Enter.
        expect(editor.cellController(2, 1).selection.isCollapsed, isFalse);
      });

      test('een ingehouden pijltje loopt door', () {
        caretAt(1, 0, 3);
        expect(
          press(1, 0, LogicalKeyboardKey.arrowRight, repeat: true),
          KeyEventResult.handled,
        );
      });

      test(
        'aan de rand van de tabel gebeurt er niets — en niets loopt door',
        () {
          // De toets wordt opgegeten in plaats van doorgelaten: in de visuele
          // documentmodus staat de cel in een Quill-embed, en een doorgelaten
          // pijltje liet Quill de cursor van het *document* verzetten en dat
          // resultaat in de cel schrijven (#1565).
          caretAt(0, 0, 0);
          expect(
            press(0, 0, LogicalKeyboardKey.arrowLeft),
            KeyEventResult.handled,
          );
          expect(
            press(0, 0, LogicalKeyboardKey.arrowUp),
            KeyEventResult.handled,
          );
          expect(editor.activeCell, isNull);
          caretAt(2, 1, editor.cellController(2, 1).text.length);
          expect(
            press(2, 1, LogicalKeyboardKey.arrowRight),
            KeyEventResult.handled,
          );
          expect(
            press(2, 1, LogicalKeyboardKey.arrowDown),
            KeyEventResult.handled,
          );
        },
      );
    });

    test(
      'een geplakte rekenbladselectie vult het raster en laat het groeien',
      () {
        editor.pasteAt(1, 0, 'a\tb\tc\nd\te\tf');
        expect(editor.colCount, 3);
        expect(editor.rows[1], ['a', 'b', 'c']);
        expect(editor.rows[2], ['d', 'e', 'f']);
        expect(editor.rows[0], ['Naam', 'Rol', '']);
      },
    );

    test('gewone tekst plakken blijft gewoon tekst in de cel', () {
      editor.pasteAt(1, 0, 'losse tekst');
      expect(editor.colCount, 2);
      expect(editor.rows[1][0], contains('losse tekst'));
    });
  });

  group('onCellFocused', () {
    testWidgets('wordt aangeroepen zodra een cel focus krijgt', (tester) async {
      var focused = 0;
      final cellEditor = TableEditController(
        rows: const [
          ['Naam', 'Rol'],
          ['Aap', 'Tester'],
        ],
        alignments: const [TableAlign.left, TableAlign.left],
        onChanged: (_, _) {},
        onCellFocused: () => focused++,
      );
      addTearDown(() => cellEditor.dispose());

      await tester.binding.setSurfaceSize(const Size(900, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              child: DocumentMarkdownView(
                '| Naam | Rol |\n|------|-----|\n| Aap | Tester |',
                tableEditController: cellEditor,
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byType(TextField).at(2));
      await tester.pump();

      expect(
        focused,
        1,
        reason: 'onCellFocused hoort één keer te vuren bij focus',
      );
    });
  });
}
