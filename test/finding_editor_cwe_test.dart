import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/finding_spec.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/editors/finding_editor.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The finding editor's "Kies CWE…" action pulls a weakness from the offline
/// CWE catalog. It must always set the CWE field but only fill the description /
/// recommendation when they are still empty — never clobber the tester's text.

// The editor now embeds AI-suggest controls (ConsumerWidget reading the settings
// provider), so it needs a ProviderScope + a mocked SharedPreferences store.
Widget _host(Slide slide, void Function(Slide) onUpdate) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: FindingEditor(
        slide: slide,
        onUpdate: onUpdate,
        imageService: ImageService(),
      ),
    ),
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
  setUp(() => SharedPreferences.setMockInitialValues({}));

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

  testWidgets('shows the AI-concept badge for a marked field, no suggest '
      'button while the AI backend is off', (tester) async {
    final slide = Slide.create(SlideType.finding)
        .copyWith(
          customMarkdown: const FindingSpec(
            heading: 'F',
            description: 'x',
          ).toMarkdown(),
        )
        .withAiAssistedField('description', present: true);
    // A tall surface so the scrolling field list builds the description row.
    await tester.binding.setSurfaceSize(const Size(1000, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_host(slide, (_) {}));
    await tester.pumpAndSettle();

    // AI backend off by default → no "suggest" control (outlined sparkle).
    expect(find.byIcon(Icons.auto_awesome_outlined), findsNothing);
    // The marked field still shows its AI-concept badge (filled sparkle).
    expect(find.byIcon(Icons.auto_awesome), findsOneWidget);
  });
}
