import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/edge_drag_auto_scroll.dart';

/// #2907: een tekstsleep die de aanwijzer voorbij de beeldrand laat rusten
/// hoort door te scrollen — native editors doen dat, `EditableText` en Quill
/// niet. De lijst staat bewust op `NeverScrollableScrollPhysics`: dan sleept
/// de aanwijzer geen inhoud mee en blijft alleen het gedrag van de helper
/// over — precies de situatie van een tekstveld waarin slepen selecteert.
void main() {
  const fieldSize = Size(300, 200);

  Widget harness(ScrollController scroll) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: fieldSize.width,
          height: fieldSize.height,
          child: EdgeDragAutoScroll(
            scroll: scroll,
            child: ListView(
              controller: scroll,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < 100; i++) ListTile(title: Text('rij $i')),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Offset fieldCenter(WidgetTester tester) =>
      tester.getCenter(find.byType(EdgeDragAutoScroll));

  testWidgets('aanwijzer onder de rand houden scrolt door', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(harness(scroll));
    expect(scroll.offset, 0);

    final gesture = await tester.startGesture(fieldCenter(tester));
    addTearDown(() => gesture.up());
    // Twintig pixels onder de onderrand, en dan stilhouden.
    await gesture.moveTo(fieldCenter(tester) + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 60));
    expect(
      scroll.offset,
      greaterThan(0),
      reason:
          'de helper hoort door te scrollen terwijl de aanwijzer voorbij de rand rust',
    );

    final first = scroll.offset;
    await tester.pump(const Duration(milliseconds: 500));
    expect(
      scroll.offset,
      greaterThan(first),
      reason: 'de scroll gaat door zolang de aanwijzer voorbij de rand rust',
    );
  });

  testWidgets('aanwijzer boven de rand houden scrolt terug omhoog', (
    tester,
  ) async {
    final scroll = ScrollController(initialScrollOffset: 400);
    addTearDown(scroll.dispose);
    await tester.pumpWidget(harness(scroll));
    expect(scroll.offset, 400);

    final gesture = await tester.startGesture(fieldCenter(tester));
    addTearDown(() => gesture.up());
    await gesture.moveTo(fieldCenter(tester) + const Offset(0, -120));
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, lessThan(400));
  });

  testWidgets('terug in beeld of loslaten stopt de scroll', (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(harness(scroll));

    final gesture = await tester.startGesture(fieldCenter(tester));
    await gesture.moveTo(fieldCenter(tester) + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scroll.offset, greaterThan(0));

    // Terug binnen de rand: de scroll stopt.
    await gesture.moveTo(fieldCenter(tester));
    await tester.pump(const Duration(milliseconds: 50));
    final stopped = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, stopped);

    // Loslaten stopt ook, ook als de aanwijzer voorbij de rand eindigde.
    await gesture.moveTo(fieldCenter(tester) + const Offset(0, 120));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    final released = scroll.offset;
    await tester.pump(const Duration(milliseconds: 300));
    expect(scroll.offset, released);
  });
}
