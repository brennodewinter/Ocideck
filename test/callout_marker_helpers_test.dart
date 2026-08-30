// Tests for the callout marker helper widgets (#1853).
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/services/image_viewport_geometry.dart';
import 'package:ocideck/widgets/editors/callout_marker_helpers.dart';

void main() {
  /// Map a point target through a painted rect that clips it, so we get a
  /// MappedTarget with clipped=true for the badge test.
  MappedTarget clippedTarget() {
    // Slot 400×300, image 800×100 (wide), cover → painted width overflows.
    // Point at x=0.01 falls outside the painted rect.
    final painted = ImageViewportGeometry.paintedRect(
      imageW: 800,
      imageH: 100,
      slotW: 400,
      slotH: 300,
      focalX: 0.5,
      focalY: 0.5,
      zoom: 0,
    );
    return ImageViewportGeometry.mapTarget(
      const CalloutPoint(0.01, 0.5),
      painted: painted,
      slotW: 400,
      slotH: 300,
    );
  }

  testWidgets('buildClippedBadge toont de reference-letter', (tester) async {
    final mapped = clippedTarget();
    expect(mapped.clipped, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: Stack(children: [buildClippedBadge('A', mapped, 400, 300)]),
        ),
      ),
    );
    expect(find.text('A'), findsOneWidget);
  });

  testWidgets('buildDragPreview toont een rechthoek zonder painted', (
    tester,
  ) async {
    final d = DragRegion(0.1, 0.2, 0.3, 0.4);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: Stack(children: [buildDragPreview(d, 400, 300, null)]),
        ),
      ),
    );
    expect(find.byType(DecoratedBox), findsOneWidget);
  });

  testWidgets('buildDragPreview met painted rect mapt correct', (tester) async {
    const painted = GeoRect(50, 0, 300, 300);
    final d = DragRegion(0.5, 0.5, 0.2, 0.2);
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 400,
          height: 300,
          child: Stack(children: [buildDragPreview(d, 400, 300, painted)]),
        ),
      ),
    );
    expect(find.byType(DecoratedBox), findsOneWidget);
  });

  test('DragRegion berekent x/y/w/h vanuit start en end', () {
    final d = DragRegion.fromDrag(0.3, 0.4, 0.1, 0.2);
    expect(d.x, 0.1);
    expect(d.y, 0.2);
    expect(d.w, closeTo(0.2, 0.001));
    expect(d.h, closeTo(0.2, 0.001));
  });

  test('DragRegion met omgekeerde drag geeft positieve w/h', () {
    final d = DragRegion.fromDrag(0.1, 0.2, 0.5, 0.6);
    expect(d.x, 0.1);
    expect(d.y, 0.2);
    expect(d.w, closeTo(0.4, 0.001));
    expect(d.h, closeTo(0.4, 0.001));
  });

  test('Handle.offset geeft de juiste hoek-posities', () {
    expect(Handle.topLeft.offset(10, 20, 100, 50), (10, 20));
    expect(Handle.topRight.offset(10, 20, 100, 50), (110, 20));
    expect(Handle.bottomLeft.offset(10, 20, 100, 50), (10, 70));
    expect(Handle.bottomRight.offset(10, 20, 100, 50), (110, 70));
  });
}
