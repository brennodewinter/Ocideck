import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/menu.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

// #1162 — regressie voor de beeldkeuring: een keuze-menublok mét afbeelding én
// een lang label liep over (RenderFlex overflow) omdat het label onder de
// afbeelding niet begrensd was. Het label hoort af te breken (ellipsis), niet de
// kaart uit te lopen. Getoetst op de maten waar de beeldkeuring het zag:
// presentatiegroot én slidestrook-klein — en sinds de indelingen erbij kwamen op
// alle drie de vormen, vol beladen: veel blokken, lange labels, uitleg,
// afbeeldingen en categorieën tegelijk.
void main() {
  final longLabel = List.filled(10, 'Heel lang label').join(' ');
  final longText = List.filled(8, 'en een uitleg die maar doorgaat').join(' ');

  Future<void> pump(
    WidgetTester tester,
    Slide slide,
    double w,
    double h,
  ) async {
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

  Future<void> render(WidgetTester tester, double w, double h) async {
    // Een raster van zes blokken maakt elk kaartje klein — juist dán liep het
    // afbeeldingsblok met een lang label over. Eén ervan draagt beeld + lang label.
    final slide = Slide.create(SlideType.menu).copyWith(
      title: 'Menu',
      bullets: [
        '[$longLabel](#doel) ![](mem:onbekend)',
        for (var i = 1; i < 6; i++) '[Blok $i](#doel$i)',
      ],
    );
    await pump(tester, slide, w, h);
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

  // Het plafond van elke indeling: zestien blokken is wat het raster op vier
  // kolommen nog netjes kwijt kan, en het is meteen het zwaarste geval voor de
  // ring. Elk blok draagt álles wat een blok kan dragen.
  for (final layout in MenuLayout.values) {
    final slide = Slide.create(SlideType.menu).copyWith(
      title: 'Een menutitel die zelf ook een hele regel in beslag neemt',
      menuLayout: layout,
      bullets: [
        groupHeadingBullet('Eerste categorie met een lange naam'),
        for (var i = 0; i < 16; i++)
          '[$longLabel $i](#doel$i) — $longText ![](mem:onbekend)',
        groupHeadingBullet('Tweede categorie'),
        '[Nog een](#nog)',
      ],
    );

    testWidgets('${layout.name}: zestien volle blokken passen (presentatie)', (
      tester,
    ) async {
      await pump(tester, slide, 1280, 720);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${layout.name}: zestien volle blokken passen (thumbnail)', (
      tester,
    ) async {
      await pump(tester, slide, 200, 112);
      expect(tester.takeException(), isNull);
    });

    testWidgets('${layout.name}: één blok zonder titel past ook', (
      tester,
    ) async {
      await pump(
        tester,
        Slide.create(
          SlideType.menu,
        ).copyWith(menuLayout: layout, bullets: ['[Alleen dit](#doel)']),
        640,
        360,
      );
      expect(tester.takeException(), isNull);
    });
  }

  // Twee gebreken die de proeven hierboven niet zágen, omdat ze geen overloop
  // zijn: een dia die door de `FittedBox` tot een postzegel krimpt, en tekst die
  // over andere tekst valt. Allebei door de beeldkeuring gevonden nadat de suite
  // groen stond (#1162).
  testWidgets('onder elkaar krimpt de dia niet tot een postzegel', (
    tester,
  ) async {
    await pump(
      tester,
      Slide.create(SlideType.menu).copyWith(
        title: 'Menu',
        menuLayout: MenuLayout.list,
        bullets: [for (var i = 0; i < 16; i++) '[Blok $i](#doel$i) — uitleg'],
      ),
      1280,
      720,
    );
    expect(tester.takeException(), isNull);

    final veel = tester.getRect(find.text('Menu')).height;

    // De titel van hetzelfde menu met drie blokken is de maatstaf: de dia mag
    // niet als geheel kleiner worden omdát er meer blokken op staan. Meten tegen
    // een uitgerekende waarde zou de lettermetriek van de proeflettertype
    // vastpinnen; deze vergelijking niet.
    await pump(
      tester,
      Slide.create(SlideType.menu).copyWith(
        title: 'Menu',
        menuLayout: MenuLayout.list,
        bullets: [for (var i = 0; i < 3; i++) '[Blok $i](#doel$i) — uitleg'],
      ),
      1280,
      720,
    );
    final weinig = tester.getRect(find.text('Menu')).height;

    expect(
      veel,
      closeTo(weinig, 1),
      reason:
          'met zestien blokken staat de titel op ${veel}px en met drie op '
          '$weinig — de dia is als geheel teruggeschaald',
    );
  });

  testWidgets('in de ring valt de uitleg niet over het label', (tester) async {
    await pump(
      tester,
      Slide.create(SlideType.menu).copyWith(
        title: 'Menu',
        menuLayout: MenuLayout.circle,
        bullets: [
          for (var i = 0; i < 6; i++)
            '[Sneltoetsen $i](#doel$i) — De handigste van allemaal',
        ],
      ),
      1280,
      720,
    );
    expect(tester.takeException(), isNull);

    for (var i = 0; i < 6; i++) {
      final label = find.text('Sneltoetsen $i');
      if (label.evaluate().isEmpty) continue;
      final uitleg = find.text('De handigste van allemaal');
      if (uitleg.evaluate().length <= i) continue;
      expect(
        tester.getRect(label).overlaps(tester.getRect(uitleg.at(i))),
        isFalse,
        reason: 'label en uitleg van schijf $i overlappen elkaar',
      );
    }
  });
}
