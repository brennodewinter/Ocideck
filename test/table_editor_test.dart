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
}
