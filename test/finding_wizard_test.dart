import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/dialogs/finding_wizard.dart';

/// The finding wizard steps through its pages and emits a finding **group** (a
/// `finding` header + an evidence placeholder by default), with the header
/// carrying an assembled CVSS 4.0 vector.

void main() {
  testWidgets('walks the steps and emits a finding group', (tester) async {
    List<Slide>? emitted;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                emitted = await FindingWizard.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Step 0 (Basis): title + finding id.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'F-1 · Test finding');
    await tester.enterText(fields.at(1), 'F-1');

    // The FilledButton is the single Next/Finish control: 3 × Next, then Finish.
    Finder next() => find.byType(FilledButton);
    for (var i = 0; i < 3; i++) {
      await tester.tap(next());
      await tester.pumpAndSettle();
    }
    await tester.tap(next());
    await tester.pumpAndSettle();

    expect(emitted, isNotNull);
    // Default group: finding header + evidence placeholder, sharing the id.
    expect(emitted!.map((s) => s.type), [SlideType.finding, SlideType.image]);
    final header = emitted!.first;
    expect(header.findingId, 'F-1');
    expect(header.findingRole, FindingRole.header);

    final spec = FindingSpec.parse(header.customMarkdown);
    expect(spec.heading, 'F-1 · Test finding');
    expect(spec.cvssVector, startsWith('CVSS:4.0/'));
    // A builder-assembled vector always parses, so the header has a severity.
    expect(spec.severity, isNotNull);
  });

  testWidgets('cancel returns null', (tester) async {
    List<Slide>? emitted;
    var called = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                called = true;
                emitted = await FindingWizard.show(context);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextButton).first); // Annuleren
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(emitted, isNull);
  });
}
