import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

// #1162 — regressie voor de beeldkeuring: een keuze-menublok mét afbeelding én
// een lang label liep over (RenderFlex overflow) omdat het label onder de
// afbeelding niet begrensd was. Het label hoort af te breken (ellipsis), niet de
// kaart uit te lopen. Getoetst op de maten waar de beeldkeuring het zag:
// presentatiegroot én slidestrook-klein.
void main() {
  Future<void> render(WidgetTester tester, double w, double h) async {
    // Een raster van zes blokken maakt elk kaartje klein — juist dán liep het
    // afbeeldingsblok met een lang label over. Eén ervan draagt beeld + lang label.
    final longLabel = List.filled(10, 'Heel lang label').join(' ');
    final slide = Slide.create(SlideType.menu).copyWith(
      title: 'Menu',
      bullets: [
        '[$longLabel](#doel) ![](mem:onbekend)',
        for (var i = 1; i < 6; i++) '[Blok $i](#doel$i)',
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: w,
              height: h,
              child: SlidePreviewWidget(slide: slide),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('afbeeldingsblok + lang label loopt niet over (presentatie)', (
    tester,
  ) async {
    await render(tester, 640, 360);
    expect(tester.takeException(), isNull);
  });

  testWidgets('afbeeldingsblok + lang label loopt niet over (thumbnail)', (
    tester,
  ) async {
    await render(tester, 200, 112);
    expect(tester.takeException(), isNull);
  });
}
