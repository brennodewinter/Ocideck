import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/dialogs/add_slide_dialog.dart';

void main() {
  Future<SlideType?> Function() openDialog(WidgetTester tester) {
    SlideType? picked;
    return () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async =>
                    picked = await AddSlideDialog.show(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return picked;
    };
  }

  List<SlideType> visibleTypes(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((p) => p.painter)
      .whereType<SlideTypePreviewPainter>()
      .map((p) => p.type)
      .toList();

  testWidgets('every slide type shows a wireframe preview', (tester) async {
    await openDialog(tester)();
    expect(visibleTypes(tester).toSet(), SlideType.values.toSet());
  });

  testWidgets('offers every type in the slideTypeMeta registry', (
    tester,
  ) async {
    // Derived from the single source of truth, so a newly added type shows up
    // automatically instead of having to be added to a second hand-kept list.
    await openDialog(tester)();
    expect(visibleTypes(tester).toSet(), slideTypeMeta.keys.toSet());
  });

  testWidgets('shows no category tab bar while one category has types', (
    tester,
  ) async {
    // Everything is SlideCategory.algemeen today; the tab bar only appears once
    // a second category carries types.
    await openDialog(tester)();
    expect(find.byType(ChoiceChip), findsNothing);
  });

  testWidgets('the search field filters cards by localised label', (
    tester,
  ) async {
    await openDialog(tester)();
    expect(find.text('Tabel'), findsOneWidget);
    expect(find.text('Titelpagina'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'tab');
    await tester.pumpAndSettle();

    expect(find.text('Tabel'), findsOneWidget);
    expect(find.text('Titelpagina'), findsNothing);
    expect(visibleTypes(tester), [SlideType.table]);
  });

  testWidgets('an empty search shows a no-results message', (tester) async {
    await openDialog(tester)();
    await tester.enterText(find.byType(TextField), 'zzzzz');
    await tester.pumpAndSettle();
    expect(visibleTypes(tester), isEmpty);
    expect(find.text('Geen resultaten'), findsOneWidget);
  });

  testWidgets('the sort toggle switches to alphabetical order', (tester) async {
    await openDialog(tester)();
    // Curated order leads with the title slide.
    expect(visibleTypes(tester).first, SlideType.title);

    await tester.tap(find.byTooltip('Alfabetisch sorteren'));
    await tester.pumpAndSettle();

    // Alphabetically by Dutch label, "Alleen Bullets" comes first.
    expect(visibleTypes(tester).first, SlideType.bullets);
  });

  testWidgets('type cards are labelled buttons (WCAG name/role)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await openDialog(tester)();
    expect(
      tester.getSemantics(find.text('Tabel')),
      isSemantics(isButton: true, isFocusable: true, label: 'Tabel'),
    );
    handle.dispose();
  });

  testWidgets('the dialog is fully keyboard-operable', (tester) async {
    SlideType? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async =>
                  picked = await AddSlideDialog.show(context),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // The first card (title slide) is focused on open; tab moves to the
    // second card and Enter activates it.
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(picked, SlideType.section);
  });

  testWidgets('escape closes the dialog without choosing', (tester) async {
    await openDialog(tester)();
    expect(find.byType(AddSlideDialog), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(AddSlideDialog), findsNothing);
  });
}
