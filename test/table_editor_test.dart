import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/table_editor.dart';

void main() {
  Future<Slide> pasteIntoFirstCell(WidgetTester tester, String clip) async {
    var updated = Slide.create(SlideType.table);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.getData') {
          return <String, dynamic>{'text': clip};
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: updated, onUpdate: (s) => updated = s),
        ),
      ),
    );

    // Field 0 is the title; the first table cell is the next TextField.
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    return updated;
  }

  testWidgets('pasting a spreadsheet selection fills and grows the grid', (
    tester,
  ) async {
    final updated = await pasteIntoFirstCell(
      tester,
      'Naam\tScore\nJan\t8\nPiet\t9\n',
    );
    expect(updated.tableRows, [
      ['Naam', 'Score'],
      ['Jan', '8'],
      ['Piet', '9'],
    ]);
  });

  testWidgets('pasting plain text stays inside the one cell', (tester) async {
    final updated = await pasteIntoFirstCell(tester, 'hallo wereld');
    expect(updated.tableRows, [
      ['hallo wereld', ''],
      ['', ''],
    ]);
  });

  testWidgets('documentContext verbergt de dia-woordenschat (titel)', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.table);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(
            slide: slide,
            onUpdate: (_) {},
            documentContext: true,
          ),
        ),
      ),
    );
    await tester.pump();
    // In een plat document bestaat geen dia: geen 'Slide titel'-veld —
    // alleen het tabelraster.
    expect(find.text('Slide titel'), findsNothing);
    expect(find.text('Tabel'), findsOneWidget);
  });

  testWidgets('zonder documentContext blijft de dia-woordenschat zichtbaar', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.table);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: slide, onUpdate: (_) {}),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Slide titel'), findsOneWidget);
  });

  // Tab loopt door de cellen en maakt op de laatste cel een rij bij — hetzelfde
  // als in de presentatiemodus, zodat de bouwer niet achterloopt op het
  // live-bewerken.
  testWidgets('Tab moves focus across cells and appends a row at the end', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.table);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: updated, onUpdate: (s) => updated = s),
        ),
      ),
    );

    // Eerste tabelcel (veld 0 is de titel).
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    // Tweede cel van de eerste rij hoort nu focus te hebben.
    final secondCell = find.byType(TextField).at(2);
    expect(secondCell, findsOneWidget);
    expect(Focus.of(tester.element(secondCell)).hasFocus, isTrue);

    // Tab op de laatste cel (rij 1, kolom 1) voegt een rij toe.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(updated.tableRows.length, 3);
  });

  // Shift+Tab loopt terug en stopt bij de eerste cel — geen wrapping voorbij
  // het begin.
  testWidgets('Shift+Tab moves focus back and stops at the first cell', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.table);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: updated, onUpdate: (s) => updated = s),
        ),
      ),
    );

    // Begin bij de tweede cel (veld 0 is de titel, veld 1 = cel(0,0),
    // veld 2 = cel(0,1)).
    await tester.tap(find.byType(TextField).at(2));
    await tester.pump();
    // Shift+Tab terug naar de eerste cel.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    final firstCell = find.byType(TextField).at(1);
    expect(Focus.of(tester.element(firstCell)).hasFocus, isTrue);
  });

  // "Rij onder invoegen" zet een lege rij ná de huidige, niet onderaan —
  // essentieel om een rij halverwege toe te voegen zonder alles te verplaatsen.
  testWidgets('insert row below adds an empty row after the chosen one', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.table);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: updated, onUpdate: (s) => updated = s),
        ),
      ),
    );
    // Vul de koprij zodat de tabel 2×2 is.
    await tester.enterText(find.byType(TextField).at(1), 'A');
    await tester.pump();
    // De per-rij-menu's staan ná de per-kolom-menu's: bij 2 kolommen is het
    // rij-0-menu op index 2 van de more_vert-iconen.
    await tester.tap(find.byIcon(Icons.more_vert).at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rij onder invoegen'));
    await tester.pumpAndSettle();
    expect(updated.tableRows.length, 3);
    // De nieuwe rij staat op index 1 (ná de kop), niet onderaan op index 2.
    expect(updated.tableRows[1], ['', '']);
    // De oorspronkelijke tweede rij schuift naar index 2.
    expect(updated.tableRows[2], ['', '']);
  });

  // "Kolom rechts invoegen" zet een lege kolom ná de gekozen kolom.
  testWidgets('insert column right adds an empty column after the chosen one', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.table);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: updated, onUpdate: (s) => updated = s),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(1), 'A');
    await tester.pump();
    // Het eerste per-kolom-menu hoort bij kolom 0.
    await tester.tap(find.byIcon(Icons.more_vert).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kolom rechts invoegen'));
    await tester.pumpAndSettle();
    expect(updated.tableRows.first.length, 3);
    // De nieuwe kolom staat op index 1 (ná kolom 0), de oude tweede op index 2.
    expect(updated.tableRows[0][1], '');
    expect(updated.tableRows[0][2], '');
  });

  // "Rij omhoog" verplaatst een body-rij, maar de kop blijft de kop: een rij
  // kan niet boven index 1 komen.
  testWidgets('move row up reorders body rows and keeps the header fixed', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.table).copyWith(
      tableRows: [
        ['Kop', 'X'],
        ['A', '1'],
        ['B', '2'],
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: updated, onUpdate: (s) => updated = s),
        ),
      ),
    );
    // Rij 2 (B) omhoog: more_vert op index 2 kolommen + 2 rijen = at(4) is rij 2.
    await tester.tap(find.byIcon(Icons.more_vert).at(4));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rij omhoog'));
    await tester.pumpAndSettle();
    expect(updated.tableRows[0], ['Kop', 'X']); // kop ongewijzigd
    expect(updated.tableRows[1], ['B', '2']); // B naar boven
    expect(updated.tableRows[2], ['A', '1']);
  });

  // "Kolom naar rechts" verplaatst een kolom over alle rijen heen.
  testWidgets('move column right reorders columns across all rows', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.table).copyWith(
      tableRows: [
        ['A', 'B'],
        ['1', '2'],
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: updated, onUpdate: (s) => updated = s),
        ),
      ),
    );
    // Kolom 0 (A) naar rechts: more_vert at(0) is kolom 0.
    await tester.tap(find.byIcon(Icons.more_vert).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kolom naar rechts'));
    await tester.pumpAndSettle();
    expect(updated.tableRows[0], ['B', 'A']);
    expect(updated.tableRows[1], ['2', '1']);
  });

  // Cmd/Ctrl+C met geen tekst geselecteerd kopieert de hele tabel als TSV —
  // de spiegel van plakken. Staat er wél een tekstselectie, dan kopieert het
  // veld die tekst (niet getoetst hier: dat is standaard-TextField-gedrag).
  testWidgets('Ctrl+C with no text selection copies the table as TSV', (
    tester,
  ) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final slide = Slide.create(SlideType.table).copyWith(
      tableRows: [
        ['Naam', 'Score'],
        ['Jan', '8'],
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: slide, onUpdate: (_) {}),
        ),
      ),
    );
    // Focus de eerste cel (geen tekstselectie → collapsed).
    await tester.tap(find.byType(TextField).at(1));
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(copied, 'Naam\tScore\nJan\t8');
  });

  // Uitlijnen via het kolom-menu zet de GFM-scheidingsrij met colons.
  testWidgets('align column right sets TableAlign.right on the slide', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.table);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TableEditor(slide: updated, onUpdate: (s) => updated = s),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(1), 'A');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.more_vert).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rechts uitlijnen'));
    await tester.pumpAndSettle();
    expect(updated.tableColumnAlignments, [TableAlign.right]);
  });

  // Getalnotatie-toggle markeert een kolom — de celinhoud blijft rauw in de
  // .md, maar bij het renderen wordt de waarde taalbewust geformatteerd.
  // StatefulBuilder zodat de editor de bijgewerkte slide terugziet bij de
  // tweede toggle — anders leest hij nog de oude widget.slide.
  testWidgets('toggle number column sets tableNumberColumns on the slide', (
    tester,
  ) async {
    var updated = Slide.create(SlideType.table);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => TableEditor(
              slide: updated,
              onUpdate: (s) => setState(() => updated = s),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(1), 'A');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.more_vert).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Getalnotatie'));
    await tester.pumpAndSettle();
    expect(updated.tableNumberColumns, [true]);
    // Nogmaals toggelen zet hem uit.
    await tester.tap(find.byIcon(Icons.more_vert).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Getalnotatie'));
    await tester.pumpAndSettle();
    expect(updated.tableNumberColumns, [false]);
  });
}
