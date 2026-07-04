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

  testWidgets('horizontal timeline cards never overlap each other', (
    tester,
  ) async {
    Rect cardRect(int i) =>
        tester.getRect(find.byKey(ValueKey('timeline-card-$i')));

    Future<void> check(int n, double height) async {
      final slide = Slide.create(SlideType.timeline).copyWith(
        title: 'Reis door de tijd',
        bullets: [
          for (var k = 0; k < n; k++)
            '20${10 + k} :: Mijlpaal $k :: Een gebeurtenis met wat toelichting.',
        ],
        timelineLayout: TimelineLayout.horizontal,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 800,
                height: height,
                child: SlidePreviewWidget(slide: slide),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final rects = [for (var i = 0; i < n; i++) cardRect(i)];
      for (var a = 0; a < n; a++) {
        for (var b = a + 1; b < n; b++) {
          final inter = rects[a].intersect(rects[b]);
          final overlaps = inter.width > 0.5 && inter.height > 0.5;
          expect(
            overlaps,
            isFalse,
            reason:
                'n=$n h=$height: card $a (${rects[a]}) overlaps '
                'card $b (${rects[b]})',
          );
        }
      }
    }

    // timelineMaxEvents caps a timeline at 12 events; cover the whole range at a
    // normal 16:9 height and at a squat height (less vertical room for floors,
    // which exercises the width-cap fallback).
    for (final n in [4, 5, 6, 7, 8, 9, 10, 11, 12]) {
      await check(n, 450);
      await check(n, 300);
    }
  });

  testWidgets(
    'the current point takes over the highlight from the last event',
    (tester) async {
      BoxDecoration cardDecoration(int i) {
        final container = tester.widget<Container>(
          find
              .descendant(
                of: find.byKey(ValueKey('timeline-card-$i')),
                matching: find.byType(Container),
              )
              .first,
        );
        return container.decoration! as BoxDecoration;
      }

      // Without a current point the last card carries the subtle emphasis.
      await tester.pumpWidget(_host(_timeline()));
      await tester.pump();
      expect(cardDecoration(3).border!.top.width, 1.6);
      expect(cardDecoration(1).border!.top.width, 1.0);

      // Marking event 2 as current moves the (stronger) highlight there.
      await tester.pumpWidget(
        _host(_timeline().copyWith(timelineCurrentIndex: 1)),
      );
      await tester.pump();
      expect(cardDecoration(1).border!.top.width, 2.0);
      expect(cardDecoration(1).boxShadow, isNotNull);
      expect(cardDecoration(3).border!.top.width, 1.0);

      // A stale index beyond the event list highlights nothing extra: the last
      // card keeps its default emphasis.
      await tester.pumpWidget(
        _host(_timeline().copyWith(timelineCurrentIndex: 9)),
      );
      await tester.pump();
      expect(cardDecoration(3).border!.top.width, 1.6);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('empty timeline renders just the title without crashing', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_timeline(bullets: const [''])));
    await tester.pump();
    expect(find.text('Van idee tot beursgang'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
