import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/menu.dart';
import 'package:ocideck/services/menu_blocks.dart';
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

  /// De werkelijk getekende lettergrootte van een label. De inline-markdown
  /// bouwt een spanboom, dus de maat staat niet altijd op de wortel.
  double labelFontSize(WidgetTester tester, String text) {
    double? found;
    void visit(InlineSpan span) {
      if (found != null) return;
      if (span is TextSpan) {
        final size = span.style?.fontSize;
        if (size != null) {
          found = size;
          return;
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child);
        }
      }
    }

    visit(
      tester
          .widget<RichText>(
            find.descendant(
              of: find.text(text),
              matching: find.byType(RichText),
            ),
          )
          .text,
    );
    return found ?? 0;
  }

  // De leesbaarheidsvloer. "Loopt niet over" en "is te lezen" zijn twee
  // verschillende dingen: bij zestien blokken bleef de dia keurig binnen zijn
  // vak met een letter van 3,7 px (#1162, beeldkeuring). Wat niet leesbaar past
  // wordt nu geteld in plaats van geperst. Deze proef legt dat besluit vast.
  for (final layout in MenuLayout.values) {
    testWidgets('${layout.name}: een vol menu telt wat er niet bij past', (
      tester,
    ) async {
      await pump(
        tester,
        Slide.create(SlideType.menu).copyWith(
          title: 'Menu',
          menuLayout: layout,
          // Veertig: genoeg om zelfs het raster te laten overlopen, dat er
          // bewust veel kwijt kan. Lijst en ring lopen al veel eerder vol.
          bullets: [for (var i = 0; i < 40; i++) '[Blok $i](#doel$i)'],
        ),
        1280,
        720,
      );
      expect(tester.takeException(), isNull);

      // Het eerste blok staat er, het laatste niet, en er staat een telblok dat
      // precies de rest noemt.
      expect(find.text('Blok 0'), findsOneWidget);
      expect(find.text('Blok 39'), findsNothing);
      final zichtbaar = [
        for (var i = 0; i < 40; i++)
          if (find.text('Blok $i').evaluate().isNotEmpty) i,
      ];
      expect(
        find.text('+${40 - zichtbaar.length}'),
        findsOneWidget,
        reason:
            'er staan ${zichtbaar.length} blokken, dus het telblok hoort '
            '"+${40 - zichtbaar.length}" te zeggen',
      );

      // En wat er wél staat, staat op leesbare grootte. De vloer is een fractie
      // van de diabreedte waarop de preview zijn inhoud opmaakt — niet van de
      // pixelmaat van dit vak, want de stellage schaalt daarnaartoe. Die breedte
      // leiden we af uit de titel, die per definitie 0,05·w meet.
      final w = labelFontSize(tester, 'Menu') / 0.05;
      expect(
        labelFontSize(tester, 'Blok 0'),
        greaterThanOrEqualTo(w * kMenuMinLabelFraction),
        reason:
            'het label staat op ${labelFontSize(tester, 'Blok 0')} van de '
            '$w brede opmaak',
      );
    });
  }

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

    // Eerst vaststellen dát alles er staat: zonder deze eis kon de lus hieronder
    // volledig doorlopen zonder één vergelijking uit te voeren, en dan is de
    // proef groen omdat hij niets deed.
    final uitleg = find.text('De handigste van allemaal');
    expect(uitleg, findsNWidgets(6));

    for (var i = 0; i < 6; i++) {
      final label = find.text('Sneltoetsen $i');
      expect(label, findsOneWidget);
      expect(
        tester.getRect(label).overlaps(tester.getRect(uitleg.at(i))),
        isFalse,
        reason: 'label en uitleg van schijf $i overlappen elkaar',
      );
    }
  });
}
