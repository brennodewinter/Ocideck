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

  // Wat 'Acties en besluiten' als apart slidetype bood, zit nu hier: de
  // kolommen om mee te beginnen, in een tabel die verder alles kan wat een
  // tabel kan.
  testWidgets('the preset fills the header row and turns on date marking', (
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

    expect(find.text('Acties en besluiten'), findsOneWidget);
    await tester.tap(find.text('Acties en besluiten'));
    await tester.pump();

    expect(updated.tableRows.first, [
      'Actie',
      'Eigenaar',
      'Deadline',
      'Status',
    ]);
    // De preset is pas compleet als verlopen deadlines ook opvallen; anders
    // levert hij kolomkoppen en laat hij het nut liggen.
    expect(updated.tableMarkOverdue, isTrue);
    // De lege regel eronder groeit mee naar vier kolommen.
    expect(updated.tableRows[1], ['', '', '', '']);
  });

  testWidgets('the preset disappears once the table carries content', (
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

    expect(find.text('Acties en besluiten'), findsOneWidget);
    // Veld 0 is de titel; de eerste tabelcel is het volgende tekstveld.
    await tester.enterText(find.byType(TextField).at(1), 'Eigen kop');
    await tester.pump();
    // Een preset die ingetypte koppen zou overschrijven, hoort er niet te staan.
    expect(find.text('Acties en besluiten'), findsNothing);
  });

  testWidgets('documentContext verbergt de dia-woordenschat (titel + preset)', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.table); // leeg 2×2 → preset zou tonen
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
    // In een plat document bestaat geen dia: geen 'Slide titel'-veld, geen
    // deck-preset — alleen het tabelraster.
    expect(find.text('Slide titel'), findsNothing);
    expect(find.text('Acties en besluiten'), findsNothing);
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
    expect(find.text('Acties en besluiten'), findsOneWidget);
  });
}
