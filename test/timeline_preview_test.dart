import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/timeline.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

Widget _host(
  Slide slide, {
  bool presentationMode = false,
  bool scrollableTimeline = true,
  bool disableAnimations = false,
  TimelineViewController? timelineViewController,
  bool timelineInteractive = true,
  int? revealed,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            width: 800,
            height: 450,
            child: SlidePreviewWidget(
              slide: slide,
              presentationMode: presentationMode,
              scrollableTimeline: scrollableTimeline,
              timelineViewController: timelineViewController,
              timelineInteractive: timelineInteractive,
              timelineRevealedCount: revealed,
            ),
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

    // Above six events the rail extends beyond the viewport instead of
    // crowding more cards into the same frame. Cover that transition at a
    // normal 16:9 height and at a squat height.
    for (final n in [4, 5, 6, 7, 8, 9, 10, 11, 12]) {
      await check(n, 450);
      await check(n, 300);
    }
  });

  testWidgets('a long horizontal timeline scrolls instead of shrinking', (
    tester,
  ) async {
    final slide = _timeline(
      layout: TimelineLayout.horizontal,
      reveal: TimelineReveal.instant,
      bullets: [
        for (var i = 1; i <= 24; i++)
          '$i :: Mijlpaal $i :: Volledige toelichting bij gebeurtenis $i.',
      ],
    );
    await tester.pumpWidget(_host(slide, presentationMode: true));
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.maxScrollExtent, greaterThan(800));
    expect(find.byType(RawScrollbar), findsOneWidget);

    await tester.drag(find.byType(Scrollable), const Offset(-500, 0));
    await tester.pump();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('step mode automatically follows the latest event', (
    tester,
  ) async {
    final slide = _timeline(
      layout: TimelineLayout.horizontal,
      reveal: TimelineReveal.steps,
      bullets: [for (var i = 1; i <= 18; i++) '$i :: Gebeurtenis $i'],
    );
    await tester.pumpWidget(_host(slide, presentationMode: true, revealed: 1));
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);

    await tester.pumpWidget(_host(slide, presentationMode: true, revealed: 14));
    await tester.pumpAndSettle();
    expect(scrollable.position.pixels, greaterThan(0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('manual position is shared as a display-independent fraction', (
    tester,
  ) async {
    final controller = TimelineViewController();
    addTearDown(controller.dispose);
    final slide = _timeline(
      layout: TimelineLayout.horizontal,
      reveal: TimelineReveal.instant,
      bullets: [for (var i = 1; i <= 18; i++) '$i :: Gebeurtenis $i'],
    );
    await tester.pumpWidget(
      _host(slide, presentationMode: true, timelineViewController: controller),
    );
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

    await tester.drag(find.byType(Scrollable), const Offset(-400, 0));
    await tester.pump();
    expect(controller.fraction, greaterThan(0));

    controller.setFraction(0.75);
    await tester.pump();
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent * 0.75, 1),
    );
  });

  testWidgets('an already shared position is applied on first layout', (
    tester,
  ) async {
    final controller = TimelineViewController()..setFraction(0.75);
    addTearDown(controller.dispose);
    final slide = _timeline(
      layout: TimelineLayout.horizontal,
      reveal: TimelineReveal.instant,
      bullets: [for (var i = 1; i <= 18; i++) '$i :: Gebeurtenis $i'],
    );

    await tester.pumpWidget(
      _host(
        slide,
        presentationMode: true,
        timelineViewController: controller,
        timelineInteractive: false,
      ),
    );
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent * 0.75, 1),
      reason:
          'de kijkstand kan vóór de dia-update arriveren; het nieuw gebouwde '
          'publieksoppervlak moet die beginstand alsnog toepassen',
    );
  });

  testWidgets('a read-only surface never publishes its local scroll', (
    tester,
  ) async {
    final controller = TimelineViewController();
    addTearDown(controller.dispose);
    final slide = _timeline(
      layout: TimelineLayout.horizontal,
      reveal: TimelineReveal.instant,
      bullets: [for (var i = 1; i <= 18; i++) '$i :: Gebeurtenis $i'],
    );

    await tester.pumpWidget(
      _host(
        slide,
        presentationMode: true,
        timelineViewController: controller,
        timelineInteractive: false,
      ),
    );
    await tester.pump();
    await tester.drag(find.byType(Scrollable), const Offset(-400, 0));
    await tester.pump();

    expect(controller.fraction, 0);
    expect(
      tester.state<ScrollableState>(find.byType(Scrollable)).position.pixels,
      greaterThan(0),
    );
  });

  testWidgets('a long vertical timeline scrolls to its final event', (
    tester,
  ) async {
    final slide = _timeline(
      layout: TimelineLayout.vertical,
      reveal: TimelineReveal.instant,
      bullets: [
        for (var i = 1; i <= timelineMaxEvents; i++)
          '$i :: Gebeurtenis $i :: Toelichting $i',
      ],
    );
    await tester.pumpWidget(_host(slide, presentationMode: true));
    await tester.pump();

    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.axis, Axis.vertical);
    expect(scrollable.position.maxScrollExtent, greaterThan(450));

    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent, 0.01),
    );
    final viewport = tester.getRect(find.byType(Scrollable));
    final finalCard = tester.getRect(
      find.byKey(const ValueKey('timeline-card-63')),
    );
    expect(
      viewport.overlaps(finalCard),
      isTrue,
      reason: 'gebeurtenis 64 moet in het laatste echte kijkvenster liggen',
    );
    expect(finalCard.bottom, lessThanOrEqualTo(viewport.bottom + 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('draw-in measures card layout only once', (tester) async {
    resetTimelineLayoutMeasurementPasses();
    final slide = _timeline(
      layout: TimelineLayout.vertical,
      bullets: [
        for (var i = 1; i <= timelineMaxEvents; i++)
          '$i :: Gebeurtenis $i :: Toelichting $i',
      ],
    );
    await tester.pumpWidget(_host(slide, presentationMode: true));
    await tester.pump();
    expect(timelineLayoutMeasurementPasses, 1);

    for (var frame = 0; frame < 12; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(
      timelineLayoutMeasurementPasses,
      1,
      reason: 'de animatie verandert alleen revealwaarden, niet de geometrie',
    );
  });

  testWidgets('draw-in mode automatically travels along a long rail', (
    tester,
  ) async {
    final slide = _timeline(
      layout: TimelineLayout.horizontal,
      bullets: [for (var i = 1; i <= 18; i++) '$i :: Gebeurtenis $i'],
    );
    await tester.pumpWidget(_host(slide, presentationMode: true));
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));

    await tester.pump(const Duration(milliseconds: 1100));
    expect(scrollable.position.pixels, greaterThan(0));
    await tester.pumpAndSettle();
    expect(
      scrollable.position.pixels,
      closeTo(scrollable.position.maxScrollExtent, 1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('reduced motion shows the settled rail without auto-scrolling', (
    tester,
  ) async {
    final slide = _timeline(
      layout: TimelineLayout.horizontal,
      bullets: [for (var i = 1; i <= 18; i++) '$i :: Gebeurtenis $i'],
    );
    await tester.pumpWidget(
      _host(slide, presentationMode: true, disableAnimations: true),
    );
    await tester.pump();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.pixels, 0);
    expect(
      tester
          .widget<Opacity>(
            find
                .ancestor(
                  of: find.text('Gebeurtenis 18'),
                  matching: find.byType(Opacity),
                )
                .first,
          )
          .opacity,
      1,
    );
  });

  testWidgets(
    'static export fallback keeps the complete sequence on one slide',
    (tester) async {
      final slide = _timeline(
        layout: TimelineLayout.vertical,
        reveal: TimelineReveal.instant,
        bullets: [
          for (var i = 1; i <= timelineMaxEvents; i++)
            '$i :: Gebeurtenis $i :: Toelichting $i',
        ],
      );
      await tester.pumpWidget(_host(slide, scrollableTimeline: false));
      await tester.pump();

      expect(find.byType(Scrollable), findsNothing);
      expect(find.text('Gebeurtenis 1'), findsOneWidget);
      expect(find.text('Gebeurtenis 64'), findsOneWidget);
      expect(find.text('Toelichting 64'), findsOneWidget);
      final slideRect = tester.getRect(find.byType(SlidePreviewWidget));
      final cards = [
        for (var i = 0; i < timelineMaxEvents; i++)
          tester.getRect(find.byKey(ValueKey('timeline-card-$i'))),
      ];
      for (var a = 0; a < cards.length; a++) {
        expect(cards[a].height, greaterThanOrEqualTo(18));
        expect(slideRect.contains(cards[a].topLeft), isTrue);
        expect(slideRect.contains(cards[a].bottomRight), isTrue);
        for (var b = a + 1; b < cards.length; b++) {
          final overlap = cards[a].intersect(cards[b]);
          expect(
            overlap.width > 0.5 && overlap.height > 0.5,
            isFalse,
            reason: 'statische kaarten $a en $b overlappen: $overlap',
          );
        }
      }
      expect(tester.takeException(), isNull);
    },
  );

  test('the safety ceiling keeps the first 64 events', () {
    final events = parseTimelineEvents([
      for (var i = 1; i <= timelineMaxEvents + 5; i++) '$i :: Gebeurtenis $i',
    ]);
    expect(events, hasLength(timelineMaxEvents));
    expect(events.last.title, 'Gebeurtenis 64');
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
