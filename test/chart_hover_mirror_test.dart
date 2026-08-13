import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/chart.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/chart_hover.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Mounts a chart slide inside a [ChartHoverScope], the way the presenter's
/// current-slide canvas and the beamer window wrap theirs. The [controller] is
/// the shared bus that, in the app, a method channel copies to the other screen.
Widget _host(ChartSpec spec, ChartHoverController controller) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: ChartHoverScope(
            controller: controller,
            child: SlidePreviewWidget(
              slide: Slide.create(
                SlideType.chart,
              ).copyWith(customMarkdown: spec.toBlock()),
              presentationMode: true,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  // The regression this guards: hovering a chart on one screen did nothing on
  // the other. The chart must (a) report its own hover to the shared controller
  // — which the bridge forwards to the other window — and (b) draw a hover it
  // receives back from that window. Both, or the presenter and beamer drift.

  testWidgets('a mirrored hover from the other screen shows on a pie', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.pie,
      title: 'Verdeling',
      x: ['Team A', 'Team B'],
      series: [
        ChartSeries(name: 'Gereed', data: [70, 40]),
      ],
    );
    final controller = ChartHoverController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(spec, controller));
    await tester.pump();
    // Nothing hovered yet: no tooltip.
    expect(find.byKey(const ValueKey('pie-hover-tooltip')), findsNothing);

    // The other screen points at the first slice — the beamer receives this over
    // the channel as an external hover.
    controller.setExternal(const ChartHover(category: 0));
    await tester.pump();
    expect(find.byKey(const ValueKey('pie-hover-tooltip')), findsOneWidget);

    // And it clears again when the other screen's pointer leaves the chart.
    controller.setExternal(null);
    await tester.pump();
    expect(find.byKey(const ValueKey('pie-hover-tooltip')), findsNothing);
  });

  testWidgets('a mirrored hover floats a tooltip on a bar chart too', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      title: 'Omzet',
      x: ['Q1', 'Q2'],
      series: [
        ChartSeries(name: '2026', data: [10, 14]),
      ],
    );
    final controller = ChartHoverController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(spec, controller));
    await tester.pump();
    expect(find.byKey(const ValueKey('cell-hover-tooltip')), findsNothing);

    // The presenter points at Q2 of the 2026 series; the beamer mirrors it.
    controller.setExternal(const ChartHover(category: 1, series: 0));
    await tester.pump();
    final tooltip = find.byKey(const ValueKey('cell-hover-tooltip'));
    expect(tooltip, findsOneWidget);
    // The mirrored tooltip is composed from the data, so it reads the same on
    // both screens without introducing a new localised string.
    expect(
      find.descendant(of: tooltip, matching: find.textContaining('14')),
      findsOneWidget,
    );
  });

  testWidgets('hovering a legend reports the series to the shared controller', (
    tester,
  ) async {
    const spec = ChartSpec(
      type: ChartType.bar,
      title: 'Omzet',
      x: ['Q1', 'Q2'],
      series: [
        ChartSeries(name: 'Noord', data: [10, 14]),
        ChartSeries(name: 'Zuid', data: [8, 12]),
      ],
    );
    final controller = ChartHoverController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(_host(spec, controller));
    await tester.pump();
    expect(controller.local, isNull);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    // Hovering the second series' legend chip is a local interaction the bridge
    // forwards to the other screen — so it must land on the controller.
    await gesture.moveTo(tester.getCenter(find.text('Zuid')));
    await tester.pump();
    expect(controller.local, const ChartHover(series: 1));

    // Leaving the chip clears it, so the other screen stops highlighting.
    await gesture.moveTo(Offset.zero);
    await tester.pump();
    expect(controller.local, isNull);
  });
}
