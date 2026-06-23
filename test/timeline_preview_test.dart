import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(Slide slide, {bool presentationMode = false, int? revealed}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(
            slide: slide,
            presentationMode: presentationMode,
            timelineRevealedCount: revealed,
          ),
        ),
      ),
    ),
  );
}

Slide _timeline({
  TimelineLayout layout = TimelineLayout.auto,
  TimelineReveal reveal = TimelineReveal.onEnter,
  List<String>? bullets,
}) => Slide.create(SlideType.timeline).copyWith(
  title: 'Van idee tot beursgang',
  bullets:
      bullets ??
      const [
        '2019 :: Oprichting :: Drie mensen, één zolderkamer.',
        '2021 :: Lancering :: 1.000 gebruikers in zes weken.',
        '2023 :: Serie A :: Internationale groei.',
        'Nu :: Vandaag',
      ],
  timelineLayout: layout,
  timelineReveal: reveal,
);

void main() {
  testWidgets('timeline renders title, markers and event titles', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_timeline()));
    await tester.pump();

    expect(find.text('Van idee tot beursgang'), findsOneWidget);
    expect(find.text('Oprichting'), findsOneWidget);
    expect(find.text('Vandaag'), findsOneWidget);
    expect(find.text('2019'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('forced horizontal and vertical layouts both render cleanly', (
    tester,
  ) async {
    for (final layout in [TimelineLayout.horizontal, TimelineLayout.vertical]) {
      await tester.pumpWidget(_host(_timeline(layout: layout)));
      await tester.pump();
      expect(find.text('Serie A'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('draw-in animation settles without exceptions', (tester) async {
    await tester.pumpWidget(
      _host(_timeline(reveal: TimelineReveal.onEnter), presentationMode: true),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('Oprichting'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('step mode shows only the revealed events', (tester) async {
    await tester.pumpWidget(
      _host(
        _timeline(reveal: TimelineReveal.steps),
        presentationMode: true,
        revealed: 2,
      ),
    );
    await tester.pump();

    // The first two events are revealed (opacity 1); later ones are faded out
    // (opacity 0) but still in the tree. Check the painted reveal via opacity.
    double opacityOf(String title) {
      final opacity = tester.widget<Opacity>(
        find
            .ancestor(of: find.text(title), matching: find.byType(Opacity))
            .first,
      );
      return opacity.opacity;
    }

    expect(opacityOf('Oprichting'), 1.0);
    expect(opacityOf('Lancering'), 1.0);
    expect(opacityOf('Serie A'), 0.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a dense timeline (11 events) lays out without overflow', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.timeline).copyWith(
      title: 'Lange reis',
      bullets: [
        for (var y = 2015; y <= 2025; y++)
          '$y :: Mijlpaal $y :: Een gebeurtenis met wat toelichting erbij.',
      ],
      timelineLayout: TimelineLayout.vertical,
    );
    await tester.pumpWidget(_host(slide));
    await tester.pump();
    // Compact mode keeps the markers and titles; descriptions are dropped.
    expect(find.text('Mijlpaal 2015'), findsOneWidget);
    expect(find.text('Mijlpaal 2025'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a crowded horizontal rail stacks onto floors without overflow', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.timeline).copyWith(
      title: 'Lange reis',
      bullets: [
        for (var y = 2013; y <= 2024; y++)
          '$y :: Mijlpaal $y :: Een gebeurtenis met wat toelichting erbij.',
      ],
      timelineLayout: TimelineLayout.horizontal,
    );
    await tester.pumpWidget(_host(slide));
    await tester.pump();
    expect(find.text('Mijlpaal 2013'), findsOneWidget);
    expect(find.text('Mijlpaal 2024'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty timeline renders just the title without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_timeline(bullets: const [''])));
    await tester.pump();
    expect(find.text('Van idee tot beursgang'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
