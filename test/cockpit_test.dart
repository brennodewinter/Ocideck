import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

void main() {
  group('CockpitSpec', () {
    test('round-trips meters through block JSON', () {
      const spec = CockpitSpec(
        animateOnEnter: false,
        animationDurationMs: 4200,
        meters: [
          CockpitMeterSpec(
            type: CockpitMeterType.thermometer,
            label: 'Risk heat',
            unit: '/10',
            min: 0,
            max: 10,
            greenFrom: 0,
            greenTo: 3,
            redFrom: 7,
            value: 8.4,
          ),
          CockpitMeterSpec(
            type: CockpitMeterType.horizon,
            label: 'Stability',
            pitch: 8,
            bank: -12,
          ),
        ],
      );

      final back = CockpitSpec.parse(spec.toBlock());

      expect(back.animateOnEnter, isFalse);
      expect(back.animationDurationMs, 4200);
      expect(back.meters, hasLength(2));
      expect(back.meters.first.type, CockpitMeterType.thermometer);
      expect(back.meters.first.value, 8.4);
      expect(back.meters.last.type, CockpitMeterType.horizon);
      expect(back.meters.last.bank, -12);
    });

    test('keeps at most six meters', () {
      final spec = CockpitSpec(
        meters: [for (var i = 0; i < 8; i++) CockpitMeterSpec(label: 'M$i')],
      );

      final back = CockpitSpec.parse(spec.toBlock());

      expect(back.meters, hasLength(cockpitMaxMeters));
      expect(back.meters.last.label, 'M5');
    });

    test('clamps animation duration to supported range', () {
      final tooShort = CockpitSpec.parse('{"animationDurationMs": 100}');
      final tooLong = CockpitSpec.parse('{"animationDurationMs": 20000}');

      expect(tooShort.animationDurationMs, cockpitMinAnimationDurationMs);
      expect(tooLong.animationDurationMs, cockpitMaxAnimationDurationMs);
    });

    test('heading keeps actual course and target marker separately', () {
      const spec = CockpitSpec(
        meters: [
          CockpitMeterSpec(
            type: CockpitMeterType.heading,
            label: 'Course',
            value: 187,
            heading: 90,
            markerLabel: 'Runway',
          ),
        ],
      );

      final back = CockpitSpec.parse(spec.toBlock()).meters.single;

      expect(back.value, 187);
      expect(back.heading, 90);
      expect(back.markerLabel, 'Runway');
    });
  });

  testWidgets('preview renders six meters without overflowing', (tester) async {
    final slide = Slide.create(SlideType.cockpit).copyWith(
      customMarkdown: CockpitSpec(
        meters: [
          for (final type in CockpitMeterType.values.take(6))
            CockpitMeterSpec(type: type, label: cockpitMeterTypeLabel(type)),
        ],
      ).toBlock(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(width: 640, child: SlidePreviewWidget(slide: slide)),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SlidePreviewWidget), findsOneWidget);
  });

  test('CockpitColorScheme round-trips through JSON', () {
    const scheme = CockpitColorScheme(
      name: 'Koud thema',
      good: '#11AA22',
      warning: '#FFAA00',
      critical: '#CC0000',
      cold: '#0066FF',
      sky: '#0EA5E9',
      ground: '#7C4A12',
    );

    final back = CockpitColorScheme.fromJson(scheme.toJson());

    expect(back.name, 'Koud thema');
    expect(back.isBuiltIn, isFalse);
    expect(back.good, '#11AA22');
    expect(back.warning, '#FFAA00');
    expect(back.critical, '#CC0000');
    expect(back.cold, '#0066FF');
    expect(back.sky, '#0EA5E9');
    expect(back.ground, '#7C4A12');
  });

  testWidgets('preview renders with a custom cockpit colour scheme', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.cockpit).copyWith(
      customMarkdown: CockpitSpec(
        meters: const [
          CockpitMeterSpec(
            type: CockpitMeterType.thermometer,
            min: 0,
            max: 10,
            greenFrom: 2,
            greenTo: 6,
            redFrom: 8,
            value: 1,
          ),
          CockpitMeterSpec(value: 78),
        ],
      ).toBlock(),
    );
    const scheme = CockpitColorScheme(
      name: 'Test',
      good: '#11AA22',
      cold: '#0066FF',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 640,
            child: SlidePreviewWidget(slide: slide, cockpitColorScheme: scheme),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.byType(SlidePreviewWidget), findsOneWidget);
  });
}
