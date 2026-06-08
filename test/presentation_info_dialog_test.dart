import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/widgets/dialogs/presentation_info_dialog.dart';

void main() {
  testWidgets('double-clicking date fills in the current date', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: PresentationInfoDialog(deck: Deck(title: 'Test')),
        ),
      ),
    );

    final dateField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Datum',
    );
    final now = DateTime.now();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    final expected =
        '${now.year}-${twoDigits(now.month)}-${twoDigits(now.day)}';

    await tester.tap(dateField);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(dateField);
    await tester.pump(const Duration(milliseconds: 100));

    final field = tester.widget<TextField>(dateField);
    expect(field.controller!.text, expected);
  });
}
