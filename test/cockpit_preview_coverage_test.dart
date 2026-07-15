import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Coverage-oriented widget tests for the cockpit instrument dashboard
/// (`lib/widgets/slides/previews/cockpit_preview.dart`). Each meter type has its
/// own painter branch (arc gauges, thermometer, climb/descent, artificial
/// horizon, heading), and the arc/thermometer painters split again on whether
/// the red band sits above (`redHigh`) or below the green band. These tests
/// build a [CockpitSpec] per case, render it through the shared preview host,
/// and assert it paints without throwing and shows the expected labels/values.
Widget _host(
  CockpitSpec spec, {
  String title = '',
  bool presentationMode = false,
  CockpitColorScheme scheme = CockpitColorScheme.standard,
}) {
  final slide = Slide.create(
    SlideType.cockpit,
  ).copyWith(customMarkdown: spec.toBlock(), title: title);
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 960,
          height: 540,
          child: SlidePreviewWidget(
            slide: slide,
            cockpitColorScheme: scheme,
            presentationMode: presentationMode,
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('every meter type renders standalone without throwing', (
    tester,
  ) async {
    // A single-meter spec drives the 1-column grid path and, one type at a
    // time, every branch of the painter's `switch (meter.type)`.
    for (final type in CockpitMeterType.values) {
      final label = 'M-${type.name}';
      final spec = CockpitSpec(
        meters: [
          CockpitMeterSpec(
            type: type,
            label: label,
            unit: '%',
            min: 0,
            max: 100,
            greenFrom: 0,
            greenTo: 40,
            redFrom: 70,
            value: 55,
            pitch: 10,
            bank: -20,
            heading: 120,
          ),
        ],
      );
      await tester.pumpWidget(_host(spec));
      await tester.pump();
      expect(find.text(label), findsOneWidget, reason: 'label for $type');
      expect(tester.takeException(), isNull, reason: '$type threw');
    }
  });

  testWidgets('an empty meter list falls back to the pentest preset', (
    tester,
  ) async {
    const spec = CockpitSpec(meters: []);
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    // The preset supplies four named meters when the slide carries none.
    expect(find.text('Overall risk'), findsOneWidget);
    expect(find.text('Exploitability heat'), findsOneWidget);
    expect(find.text('Evidence confidence'), findsOneWidget);
    expect(find.text('Findings trend'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a meter with no label falls back to its type name', (
    tester,
  ) async {
    const spec = CockpitSpec(
      meters: [CockpitMeterSpec(type: CockpitMeterType.altimeter, label: '')],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    // cockpitMeterTypeLabel(altimeter).toUpperCase()
    expect(find.text('ALTIMETER'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arc gauge covers both red-high and red-low band orders', (
    tester,
  ) async {
    // red-high: red band sits above the green band (redFrom > greenTo), value
    // pinned at the maximum.
    const highSpec = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.speedometer,
          label: 'Risk high',
          unit: '%',
          min: 0,
          max: 100,
          greenFrom: 0,
          greenTo: 40,
          redFrom: 70,
          value: 100,
        ),
      ],
    );
    await tester.pumpWidget(_host(highSpec));
    await tester.pump();
    expect(find.text('Risk high'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // red-low: green band sits high, red band low (redFrom < greenFrom), value
    // pinned at the minimum — the voltmeter/confidence arrangement.
    const lowSpec = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.voltmeter,
          label: 'Confidence low',
          unit: '%',
          min: 0,
          max: 100,
          greenFrom: 75,
          greenTo: 100,
          redFrom: 50,
          value: 0,
        ),
      ],
    );
    await tester.pumpWidget(_host(lowSpec));
    await tester.pump();
    expect(find.text('Confidence low'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('thermometer covers both band orders and a fractional value', (
    tester,
  ) async {
    // red-high with a fractional reading (exercises _fmt's one-decimal path).
    const heatSpec = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.thermometer,
          label: 'Heat',
          unit: '/10',
          min: 0,
          max: 10,
          greenFrom: 0,
          greenTo: 3,
          redFrom: 7,
          value: 8.4,
        ),
      ],
    );
    await tester.pumpWidget(_host(heatSpec));
    await tester.pump();
    expect(find.text('Heat'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // red-low thermometer (green high, red low).
    const coolSpec = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.thermometer,
          label: 'Cool',
          unit: '/10',
          min: 0,
          max: 10,
          greenFrom: 7,
          greenTo: 10,
          redFrom: 3,
          value: 2,
        ),
      ],
    );
    await tester.pumpWidget(_host(coolSpec));
    await tester.pump();
    expect(find.text('Cool'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('climb/descent shows a leading + for a positive value', (
    tester,
  ) async {
    const spec = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.climbDescent,
          label: 'Trend up',
          min: -20,
          max: 20,
          neutralFrom: -3,
          neutralTo: 3,
          value: 12,
        ),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();
    expect(find.text('Trend up'), findsOneWidget);
    // The value text is painted on the canvas (+12), so we assert on the label
    // and a clean paint rather than a Text widget.
    expect(tester.takeException(), isNull);
  });

  testWidgets('climb/descent handles a negative value without the + sign', (
    tester,
  ) async {
    const spec = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.climbDescent,
          label: 'Trend down',
          min: -20,
          max: 20,
          neutralFrom: -3,
          neutralTo: 3,
          value: -15,
        ),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();
    expect(find.text('Trend down'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('artificial horizon paints sky/ground with pitch and bank', (
    tester,
  ) async {
    const spec = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.horizon,
          label: 'Attitude',
          pitch: 22,
          bank: -35,
        ),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();
    expect(find.text('Attitude'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('heading gauge renders with and without a marker label', (
    tester,
  ) async {
    const withMarker = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.heading,
          label: 'Course',
          value: 90,
          heading: 270,
          markerLabel: 'Target bearing',
        ),
      ],
    );
    await tester.pumpWidget(_host(withMarker));
    await tester.pump();
    expect(find.text('Course'), findsOneWidget);
    expect(tester.takeException(), isNull);

    const noMarker = CockpitSpec(
      meters: [
        CockpitMeterSpec(
          type: CockpitMeterType.heading,
          label: 'Course 2',
          value: 5,
          heading: 5,
          markerLabel: '',
        ),
      ],
    );
    await tester.pumpWidget(_host(noMarker));
    await tester.pump();
    expect(find.text('Course 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the slide title renders above the instrument grid', (
    tester,
  ) async {
    const spec = CockpitSpec(
      meters: [CockpitMeterSpec(type: CockpitMeterType.speedometer)],
    );
    await tester.pumpWidget(_host(spec, title: 'Cockpit dashboard'));
    await tester.pump();
    expect(find.text('Cockpit dashboard'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('grid arranges 1, 2, 4 and 6 meters without overflow', (
    tester,
  ) async {
    CockpitSpec make(int n) => CockpitSpec(
      meters: [
        for (var i = 0; i < n; i++)
          CockpitMeterSpec(
            type: CockpitMeterType.values[i % CockpitMeterType.values.length],
            label: 'G$n-$i',
          ),
      ],
    );

    for (final n in [1, 2, 4, 6]) {
      await tester.pumpWidget(_host(make(n)));
      await tester.pump();
      for (var i = 0; i < n; i++) {
        expect(find.text('G$n-$i'), findsOneWidget, reason: 'meter $i of $n');
      }
      expect(tester.takeException(), isNull, reason: '$n meters threw');
    }
  });

  testWidgets('more than the max meters are clamped to the cap', (
    tester,
  ) async {
    final spec = CockpitSpec(
      meters: [
        for (var i = 0; i < cockpitMaxMeters + 3; i++)
          CockpitMeterSpec(type: CockpitMeterType.speedometer, label: 'Cap$i'),
      ],
    );
    await tester.pumpWidget(_host(spec));
    await tester.pump();

    // Only the first cockpitMaxMeters survive parsing/rendering.
    expect(find.text('Cap0'), findsOneWidget);
    expect(find.text('Cap${cockpitMaxMeters - 1}'), findsOneWidget);
    expect(find.text('Cap$cockpitMaxMeters'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('presentation mode plays the boot animation and settles', (
    tester,
  ) async {
    const spec = CockpitSpec(
      animationDurationMs: 600,
      meters: [
        CockpitMeterSpec(type: CockpitMeterType.speedometer, label: 'Boot'),
        CockpitMeterSpec(type: CockpitMeterType.thermometer, label: 'Boot 2'),
      ],
    );
    await tester.pumpWidget(_host(spec, presentationMode: true));
    await tester.pump();
    // Advance mid-animation, then let it finish.
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    expect(find.text('Boot'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('animateOnEnter:false stays static even in presentation', (
    tester,
  ) async {
    const spec = CockpitSpec(
      animateOnEnter: false,
      meters: [
        CockpitMeterSpec(type: CockpitMeterType.altimeter, label: 'Static'),
      ],
    );
    await tester.pumpWidget(_host(spec, presentationMode: true));
    await tester.pump();
    expect(find.text('Static'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('re-parses and re-arms when the slide markdown changes', (
    tester,
  ) async {
    const first = CockpitSpec(
      meters: [
        CockpitMeterSpec(type: CockpitMeterType.speedometer, label: 'First'),
      ],
    );
    const second = CockpitSpec(
      meters: [
        CockpitMeterSpec(type: CockpitMeterType.heading, label: 'Second'),
      ],
    );

    await tester.pumpWidget(_host(first));
    await tester.pump();
    expect(find.text('First'), findsOneWidget);

    // Same widget position, changed markdown + presentation flag: exercises
    // didUpdateWidget's re-parse and _maybeStart.
    await tester.pumpWidget(_host(second, presentationMode: true));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('honours a custom colour scheme for the status bands', (
    tester,
  ) async {
    const scheme = CockpitColorScheme(
      name: 'Custom',
      good: '#00FF00',
      warning: '#FFAA00',
      critical: '#FF0000',
      cold: '#0000FF',
      sky: '#112244',
      ground: '#664422',
    );
    const spec = CockpitSpec(
      meters: [
        CockpitMeterSpec(type: CockpitMeterType.thermometer, label: 'Themed'),
        CockpitMeterSpec(type: CockpitMeterType.horizon, label: 'Themed sky'),
      ],
    );
    await tester.pumpWidget(_host(spec, scheme: scheme));
    await tester.pump();
    expect(find.text('Themed'), findsOneWidget);
    expect(find.text('Themed sky'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
