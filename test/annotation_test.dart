import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/annotation.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/annotation_codec.dart';
import 'package:ocideck/widgets/presentation/annotation_overlay.dart';

void main() {
  group('InkStroke JSON', () {
    test('round-trips tool, color, width and points', () {
      const stroke = InkStroke(
        tool: InkTool.highlighter,
        color: 0xFF22C55E,
        width: 0.022,
        points: [Offset(0.1, 0.2), Offset(0.3, 0.45)],
        id: 's1',
      );
      final back = InkStroke.fromJson(stroke.toJson());
      expect(back.tool, InkTool.highlighter);
      expect(back.color, 0xFF22C55E);
      expect(back.width, closeTo(0.022, 1e-9));
      expect(back.points.length, 2);
      expect(back.points[1].dx, closeTo(0.3, 1e-4));
      expect(back.points[1].dy, closeTo(0.45, 1e-4));
    });
  });

  group('AnnotationCodec', () {
    InkStroke stroke() => const InkStroke(
      tool: InkTool.pen,
      color: 0xFFEF4444,
      width: 0.004,
      points: [Offset(0.1, 0.1), Offset(0.2, 0.2)],
      id: 's2',
    );

    test('encodes nothing when there are no strokes', () {
      final slides = [Slide.create(SlideType.bullets)];
      expect(AnnotationCodec.encode(slides, {}), isNull);
    });

    test('round-trips strokes for the same deck', () {
      final slides = [
        Slide.create(SlideType.bullets).copyWith(title: 'A'),
        Slide.create(SlideType.bullets).copyWith(title: 'B'),
      ];
      final ann = {
        slides[1].id: [stroke()],
      };
      final json = AnnotationCodec.encode(slides, ann)!;
      final back = AnnotationCodec.decode(json, slides);
      expect(back.keys, [slides[1].id]);
      expect(back[slides[1].id]!.single.points.length, 2);
    });

    test('re-anchors strokes to the matching slide after reordering', () {
      final a = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final b = Slide.create(SlideType.bullets).copyWith(title: 'B');
      final json = AnnotationCodec.encode(
        [a, b],
        {
          a.id: [stroke()],
        },
      )!;

      // Reload parses fresh slides with NEW ids but identical content, in a
      // different order.
      final a2 = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final b2 = Slide.create(SlideType.bullets).copyWith(title: 'B');
      final back = AnnotationCodec.decode(json, [b2, a2]);
      expect(back.containsKey(a2.id), isTrue);
      expect(back.containsKey(b2.id), isFalse);
    });

    test('drops strokes when the slide content changed', () {
      final a = Slide.create(SlideType.bullets).copyWith(title: 'A');
      final json = AnnotationCodec.encode(
        [a],
        {
          a.id: [stroke()],
        },
      )!;
      final edited = Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'A (changed)');
      final back = AnnotationCodec.decode(json, [edited]);
      expect(back, isEmpty);
    });

    test('round-trips per-page strokes on one rich-text slide', () {
      final slide = Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Verhaal', listStyle: ListStyle.richText);
      // Page 0 uses the bare id; later pages get a suffixed key.
      final ann = {
        slide.id: [stroke()],
        annotationKey(slide.id, 1): [stroke(), stroke()],
      };
      final json = AnnotationCodec.encode([slide], ann)!;
      final back = AnnotationCodec.decode(json, [slide]);
      expect(back[slide.id]!, hasLength(1));
      expect(back[annotationKey(slide.id, 1)]!, hasLength(2));
    });

    test('a legacy entry without a page decodes onto page 0', () {
      final slide = Slide.create(SlideType.bullets).copyWith(title: 'A');
      // A v1 sidecar never wrote a "page" field.
      final legacy = AnnotationCodec.encode(
        [slide],
        {
          slide.id: [stroke()],
        },
      )!;
      expect(legacy, isNot(contains('"page"')));
      final back = AnnotationCodec.decode(legacy, [slide]);
      expect(back.keys, [slide.id]);
    });
  });

  group('annotationKey', () {
    test('page 0 is the bare id; later pages are suffixed and reversible', () {
      expect(annotationKey('abc', 0), 'abc');
      expect(annotationKey('abc', 2), 'abc#p2');
      expect(annotationPageForKey('abc', 'abc'), 0);
      expect(annotationPageForKey('abc#p2', 'abc'), 2);
      // A key for a different slide id does not match.
      expect(annotationPageForKey('xyz#p1', 'abc'), isNull);
    });
  });

  group('AnnotationLayer live stroke', () {
    testWidgets('streams the in-progress stroke and clears it on commit', (
      tester,
    ) async {
      final active = <InkStroke?>[];
      final committed = <List<InkStroke>>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 225,
                child: AnnotationLayer(
                  strokes: const [],
                  tool: InkTool.pen,
                  interactive: true,
                  onStrokesChanged: committed.add,
                  onActiveStrokeChanged: active.add,
                ),
              ),
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(AnnotationLayer));
      final gesture = await tester.startGesture(center);
      await gesture.moveBy(const Offset(20, 0));
      await gesture.moveBy(const Offset(20, 10));
      await tester.pump();

      // While drawing, the partial stroke is reported with growing points.
      final partials = active.whereType<InkStroke>().toList();
      expect(partials, isNotEmpty);
      expect(partials.last.tool, InkTool.pen);
      expect(partials.last.points.length, greaterThan(1));

      await gesture.up();
      await tester.pump();

      // Committing clears the live preview (null) and emits the final stroke.
      expect(active.last, isNull);
      expect(committed.single.single.points.length, greaterThan(1));
    });

    testWidgets('reports null when a tap is too short to commit', (
      tester,
    ) async {
      final active = <InkStroke?>[];
      final committed = <List<InkStroke>>[];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 400,
                height: 225,
                child: AnnotationLayer(
                  strokes: const [],
                  tool: InkTool.pen,
                  interactive: true,
                  onStrokesChanged: committed.add,
                  onActiveStrokeChanged: active.add,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byType(AnnotationLayer));
      await tester.pump();

      // A single down/up makes no stroke, but the preview must still be cleared.
      expect(active.last, isNull);
      expect(committed, isEmpty);
    });
  });
}
