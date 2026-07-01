import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/widgets/editors/timeline_editor.dart';

Widget _host(Slide slide, ValueChanged<Slide> onUpdate) => ProviderScope(
  child: MaterialApp(
    home: Scaffold(
      body: TimelineEditor(
        slide: slide,
        onUpdate: onUpdate,
        themeAnimationDurationMs: timelineDefaultAnimationDurationMs,
      ),
    ),
  ),
);

void main() {
  testWidgets('speed slider shows only for the draw-in animation', (
    tester,
  ) async {
    // A fresh timeline defaults to the draw-in animation, so the slider shows.
    await tester.pumpWidget(_host(Slide.create(SlideType.timeline), (_) {}));
    await tester.pump();
    expect(find.byType(Slider), findsOneWidget);

    // Switching to step-by-step (as the user would, via the chip) hides it.
    await tester.tap(find.text('Stap voor stap'));
    await tester.pump();
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('dragging the speed slider changes the draw-in duration', (
    tester,
  ) async {
    Slide? out;
    await tester.pumpWidget(
      _host(Slide.create(SlideType.timeline), (s) => out = s),
    );
    await tester.pump();

    await tester.drag(find.byType(Slider), const Offset(-220, 0));
    await tester.pump();

    expect(out, isNotNull);
    expect(out!.timelineAnimationMs, isNot(timelineDefaultAnimationDurationMs));
    expect(
      out!.timelineAnimationMs,
      inInclusiveRange(
        timelineMinAnimationDurationMs,
        timelineMaxAnimationDurationMs,
      ),
    );
  });
}
