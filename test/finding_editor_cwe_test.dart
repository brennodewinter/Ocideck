import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/editors/finding_editor.dart';

/// The finding editor's "Kies CWE…" action pulls a weakness from the offline
/// CWE catalog. It must always set the CWE field but only fill the description /
/// recommendation when they are still empty — never clobber the tester's text.

Widget _host(Slide slide, void Function(Slide) onUpdate) => MaterialApp(
  home: Scaffold(
    body: FindingEditor(slide: slide, onUpdate: onUpdate),
  ),
);

Future<void> _pickCwe89(WidgetTester tester) async {
  // The CWE button carries the shield icon (locale-independent).
  await tester.tap(find.byIcon(Icons.shield_outlined));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    ),
    '89',
  );
  await tester.pump();
  // Scope to the dialog: the editor's CWE field hint also contains "CWE-89".
  await tester.tap(
    find.descendant(
      of: find.byType(AlertDialog),
      matching: find.textContaining('CWE-89'),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('picking a CWE fills the field and an empty description', (
    tester,
  ) async {
    Slide? updated;
    await tester.pumpWidget(
      _host(Slide.create(SlideType.finding), (s) => updated = s),
    );

    await _pickCwe89(tester);

    expect(updated, isNotNull);
    final spec = FindingSpec.parse(updated!.customMarkdown);
    expect(spec.cweId, 89);
    expect(spec.description.trim(), isNotEmpty);
    expect(spec.recommendation.trim(), isNotEmpty);
  });

  testWidgets('picking a CWE never overwrites an existing description', (
    tester,
  ) async {
    Slide? updated;
    final slide = Slide.create(SlideType.finding).copyWith(
      customMarkdown: const FindingSpec(
        heading: 'F-1',
        description: 'Handmatige beschrijving',
      ).toMarkdown(),
    );
    await tester.pumpWidget(_host(slide, (s) => updated = s));

    await _pickCwe89(tester);

    expect(updated, isNotNull);
    final spec = FindingSpec.parse(updated!.customMarkdown);
    expect(spec.cweId, 89);
    expect(spec.description.trim(), 'Handmatige beschrijving');
  });
}
