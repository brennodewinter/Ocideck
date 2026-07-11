import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cwe_entry.dart';
import 'package:ocideck/widgets/dialogs/cwe_picker.dart';

void main() {
  testWidgets('picker lists CWE entries, filters, and returns a pick', (
    tester,
  ) async {
    CweEntry? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await CwePicker.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    // The full catalog is shown before typing.
    expect(find.textContaining('CWE-79'), findsWidgets);

    // Searching by keyword narrows to the matching weakness.
    await tester.enterText(find.byType(TextField).first, 'traversal');
    await tester.pump();
    expect(find.textContaining('CWE-22'), findsOneWidget);
    expect(find.textContaining('CWE-79'), findsNothing);

    // Searching by number and tapping the tile returns the entry.
    await tester.enterText(find.byType(TextField).first, '89');
    await tester.pump();
    await tester.tap(find.textContaining('CWE-89'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.id, 89);
    expect(picked!.recommendation, isNotEmpty);
  });
}
