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

  testWidgets('every slide type shows a wireframe preview', (tester) async {
    await openDialog(tester)();
    final painters = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<SlideTypePreviewPainter>()
        .map((p) => p.type)
        .toSet();
    expect(painters, SlideType.values.toSet());
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
              onPressed: () async => picked = await AddSlideDialog.show(context),
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
