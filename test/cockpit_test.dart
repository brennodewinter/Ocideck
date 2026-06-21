import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/cockpit.dart';
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
}
