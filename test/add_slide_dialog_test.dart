import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/dialogs/add_slide_dialog.dart';

void main() {
  Future<SlideType?> Function() openDialog(
    WidgetTester tester, {
    bool reveal = false,
  }) {
    SlideType? picked;
    return () async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async => picked = await AddSlideDialog.show(
                  context,
                  revealInfoSafety: reveal,
                ),
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
    // Reveal the security module so every type is offered; the "Alle" tab drops
    // the category filter so all of them are visible at once.
    await openDialog(tester, reveal: true)();
    await tester.tap(find.text('Alle'));
    await tester.pumpAndSettle();
    expect(visibleTypes(tester).toSet(), SlideType.values.toSet());
  });

  testWidgets('offers every type in the slideTypeMeta registry', (
    tester,
  ) async {
    // Derived from the single source of truth, so a newly added type shows up
    // automatically instead of having to be added to a second hand-kept list.
    await openDialog(tester, reveal: true)();
    await tester.tap(find.text('Alle'));
    await tester.pumpAndSettle();
    expect(visibleTypes(tester).toSet(), slideTypeMeta.keys.toSet());
  });

  testWidgets('hides the security types and tab bar until the module is on', (
    tester,
  ) async {
    // Module off (the default): only SlideCategory.algemeen types are offered,
    // so no tab bar is drawn and no Informatieveiligheid type is reachable.
    await openDialog(tester)();
    expect(find.byType(ChoiceChip), findsNothing);
    expect(
      visibleTypes(
        tester,
      ).any((t) => t.category == SlideCategory.informatieveiligheid),
      isFalse,
    );
  });

  testWidgets('reveals the security types under a tab when the module is on', (
    tester,
  ) async {
    await openDialog(tester, reveal: true)();
    // A second category now carries types, so the tab bar appears. The default
    // tab is Algemeen, so no security type is shown yet.
    expect(find.byType(ChoiceChip), findsWidgets);
    expect(
      visibleTypes(
        tester,
      ).any((t) => t.category == SlideCategory.informatieveiligheid),
      isFalse,
    );
    // The Informatieveiligheid tab shows exactly the module's types.
    await tester.tap(find.text('Informatieveiligheid'));
    await tester.pumpAndSettle();
    expect(visibleTypes(tester).toSet(), {
      SlideType.assets,
      SlideType.finding,
      SlideType.findingsSummary,
      SlideType.checklist,
      SlideType.scopeMatrix,
      SlideType.signOff,
    });
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

    // Assert the *ordering*, not which label happens to win it. Naming the
    // winner meant this test broke every time a type was added whose label
    // sorted early — which says nothing about whether sorting works.
    final labels = [
      for (final type in visibleTypes(tester)) slideTypeMeta[type]!.label,
    ];
    final sorted = [...labels]
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    expect(labels, sorted);
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
