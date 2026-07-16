import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_template.dart';
import 'package:ocideck/widgets/dialogs/finding_template_picker.dart';

void main() {
  testWidgets('picker lists bundled templates, filters, and returns a pick', (
    tester,
  ) async {
    FindingTemplate? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                picked = await FindingTemplatePicker.show(
                  context,
                  languageCode: 'en',
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('SQL injection'), findsOneWidget);

    // Search narrows the list.
    await tester.enterText(find.byType(TextField).first, 'xss');
    await tester.pump();
    expect(find.text('SQL injection'), findsNothing);
    expect(find.textContaining('cross-site'), findsOneWidget);

    // Clearing restores it; tapping returns the template.
    await tester.enterText(find.byType(TextField).first, '');
    await tester.pump();
    await tester.tap(find.text('SQL injection'));
    await tester.pumpAndSettle();

    expect(picked, isNotNull);
    expect(picked!.title, 'SQL injection');
    expect(picked!.cweId, 89);
  });
}
