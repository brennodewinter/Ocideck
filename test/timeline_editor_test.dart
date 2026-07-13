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

  testWidgets('the place-pin toggles the current point on and off', (
    tester,
  ) async {
    // Tall surface so all four event rows (and their pins) are tappable.
    await tester.binding.setSurfaceSize(const Size(900, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Slide? out;
    await tester.pumpWidget(
      _host(Slide.create(SlideType.timeline), (s) => out = s),
    );
    await tester.pump();

    // A fresh timeline has no current point: four outlined pins.
    expect(find.byIcon(Icons.place_outlined), findsNWidgets(4));

    // Marking the second event stores its (0-based) index.
    await tester.tap(find.byIcon(Icons.place_outlined).at(1));
    await tester.pump();
    expect(out!.timelineCurrentIndex, 1);
    expect(find.byIcon(Icons.place), findsOneWidget);

    // Marking another event moves the single current point there.
    await tester.tap(find.byIcon(Icons.place_outlined).at(2));
    await tester.pump();
    expect(out!.timelineCurrentIndex, 3);
    expect(find.byIcon(Icons.place), findsOneWidget);

    // Tapping the active pin clears the current point again.
    await tester.tap(find.byIcon(Icons.place));
    await tester.pump();
    expect(out!.timelineCurrentIndex, isNull);
    expect(find.byIcon(Icons.place_outlined), findsNWidgets(4));
  });

  testWidgets('"PTES-fasen laden" seeds the seven PTES phases', (tester) async {
    await tester.binding.setSurfaceSize(const Size(900, 2200));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    Slide? out;
    // An empty timeline shows a lone blank starter row, which the loader replaces.
    final empty = Slide.create(SlideType.timeline).copyWith(bullets: const []);
    await tester.pumpWidget(_host(empty, (s) => out = s));
    await tester.pump();

    await tester.tap(find.text('PTES-fasen laden'));
    await tester.pumpAndSettle();

    final events = parseTimelineEvents(out!.bullets);
    expect(events, hasLength(7));
    expect(events.first.title, 'Voorafgaande afspraken');
    expect(events.last.title, 'Rapportage');
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
