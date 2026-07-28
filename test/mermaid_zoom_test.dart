import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/slides/mermaid_diagram.dart';
// ignore: depend_on_referenced_packages
import 'package:vector_math/vector_math_64.dart' as vm;

/// De zoom van een groot mermaid-diagram tijdens het presenteren (#930): de
/// rekenkern (maat-onafhankelijke kijkstand ↔ InteractiveViewer-matrix), de
/// controller, de knoppen, en de spiegeling naar het publieksvenster.
void main() {
  setUp(() => AppLocalizations.setActiveLanguageCode('nl'));

  group('rekenkern', () {
    test('matrix en genormaliseerd zijn elkaars inverse', () {
      const cw = 840.0, ch = 3360.0;
      final m = mermaidViewMatrix(2.0, 0.25, 0.1, cw, ch);
      final n = mermaidViewNormalized(m, cw, ch);
      expect(n.scale, closeTo(2.0, 1e-9));
      expect(n.fx, closeTo(0.25, 1e-9));
      expect(n.fy, closeTo(0.1, 1e-9));
    });

    test('de kind-fractie landt op de vensterrand', () {
      const cw = 840.0, ch = 3360.0;
      // Op zoom 2, fractie (0.25, 0.1): het kindpunt (0.25·cw, 0.1·ch) hoort op
      // de vensterrand (0,0) te landen.
      final m = mermaidViewMatrix(2.0, 0.25, 0.1, cw, ch);
      final p = m.transform3(vm.Vector3(0.25 * cw, 0.1 * ch, 0));
      expect(p.x, closeTo(0.0, 1e-6));
      expect(p.y, closeTo(0.0, 1e-6));
    });

    test('inzoomen rond het midden houdt het midden vast', () {
      const cw = 840.0, ch = 3360.0, vw = 840.0, vh = 320.0;
      final start = (scale: 1.0, fx: 0.0, fy: 0.0);
      final visYStart = vh / (start.scale * ch);
      final centreY = start.fy + visYStart / 2;

      final zoomed = mermaidZoomAroundCentre(
        start,
        factor: 2.0,
        vw: vw,
        vh: vh,
        childW: cw,
        childH: ch,
      );
      expect(zoomed.scale, closeTo(2.0, 1e-9));
      // Het midden van het venster wijst na het zoomen nog naar hetzelfde punt.
      final visY2 = vh / (zoomed.scale * ch);
      expect(zoomed.fy + visY2 / 2, closeTo(centreY, 1e-6));
      // Horizontaal past het diagram precies (cw==vw): op zoom 2 gecentreerd.
      final visX2 = vw / (zoomed.scale * cw);
      expect(zoomed.fx, closeTo(0.5 - visX2 / 2, 1e-6));
    });

    test('uitzoomen klemt de kijkstand terug binnen het diagram', () {
      const cw = 840.0, ch = 3360.0, vw = 840.0, vh = 320.0;
      // Ver ingezoomd en naar rechtsonder geschoven, dan fors uitzoomen: het
      // venster mag daarna niet buiten het diagram (0..1) hangen.
      final out = mermaidZoomAroundCentre(
        (scale: 4.0, fx: 0.7, fy: 0.9),
        factor: 0.4,
        vw: vw,
        vh: vh,
        childW: cw,
        childH: ch,
      );
      final visX = vw / (out.scale * cw);
      final visY = vh / (out.scale * ch);
      expect(out.fx, inInclusiveRange(0.0, 1.0 - visX + 1e-9));
      expect(out.fy, inInclusiveRange(0.0, 1.0 - visY + 1e-9));
    });

    test('passend-maat is de kleinste die het diagram in het venster legt', () {
      // Hoog diagram: verticaal knijpt het, dus de passend-maat is vh/ch < 1.
      expect(mermaidFitScale(840, 320, 840, 3360), closeTo(320 / 3360, 1e-9));
      // Een diagram dat al past → nooit boven 1 (niet onnodig verkleinen).
      expect(mermaidFitScale(840, 320, 200, 100), 1.0);
    });

    test('uitzoomen mag nu voorbij 1 tot de passend-maat (#944)', () {
      const cw = 840.0, ch = 3360.0, vw = 840.0, vh = 320.0;
      final fit = mermaidFitScale(vw, vh, cw, ch); // ≈ 0.095
      // Vanaf leesbaar (1.0) fors uitzoomen mag onder 1, tot de passend-maat.
      final out = mermaidZoomAroundCentre(
        (scale: 1.0, fx: 0.0, fy: 0.0),
        factor: 0.01, // ruim voorbij passend
        vw: vw,
        vh: vh,
        childW: cw,
        childH: ch,
      );
      expect(out.scale, closeTo(fit, 1e-9));
      expect(out.scale, lessThan(1.0));
    });
  });

  group('controller', () {
    test('laat uitzoomen onder 1 toe (#944), klemt op de vangnet-grenzen', () {
      final c = MermaidViewController();
      // Onder 1 mag nu: uitzoomen tot het hele diagram past.
      c.set(scale: 0.3, fx: -1, fy: 5);
      expect(c.scale, 0.3);
      expect(c.fx, 0.0);
      expect(c.fy, 1.0);
      // Maar niet tot nul: de vangnet-ondergrens.
      c.set(scale: 0.0001, fx: 0, fy: 0);
      expect(c.scale, kMermaidMinZoom);
      c.set(scale: 999, fx: 0.5, fy: 0.5);
      expect(c.scale, kMermaidMaxZoom);
    });

    test('meldt alleen bij een echte wijziging', () {
      final c = MermaidViewController();
      var notifs = 0;
      c.addListener(() => notifs++);
      c.set(scale: 2, fx: 0.1, fy: 0.1);
      c.set(scale: 2, fx: 0.1, fy: 0.1); // gelijk → geen melding
      expect(notifs, 1);
      c.reset();
      expect(notifs, 2);
      expect(c.scale, 1.0);
    });

    // De toetsenbord-zoom (#930) leunt op zoomBy: die zoomt rond het midden met
    // de laatst doorgegeven maten, zodat een toets hetzelfde doet als de knop.
    test('zoomBy zonder bekende maten doet niets', () {
      final c = MermaidViewController();
      // Vers, nog geen layout geweest: er is geen zoombaar diagram, dus de toets
      // hoort niet als afgehandeld te tellen en de stand blijft ongemoeid.
      expect(c.zoomBy(0.8), isFalse);
      expect(c.zoomBy(1.25), isFalse);
      expect(c.scale, 1.0);
    });

    test('zoomBy met maten zoomt in én weer uit, tot de passend-maat', () {
      final c = MermaidViewController()
        ..setMetrics(vw: 840, vh: 320, childW: 840, childH: 3360);
      expect(c.zoomBy(2.0), isTrue);
      expect(c.scale, closeTo(2.0, 1e-9));
      // Uitzoomen brengt hem terug richting passend — dít was de klacht (#930):
      // inzoomen werkte, uitzoomen deed niets omdat de toets nergens op zat.
      expect(c.zoomBy(0.5), isTrue);
      expect(c.scale, closeTo(1.0, 1e-9));
      // En verder uitzoomen mag nu ónder 1, tot het hele diagram past (#944) —
      // niet slechts tot leesbare volle breedte. Onder passend kan niet, maar op
      // een zoombaar diagram telt de toets wél als afgehandeld.
      final fit = mermaidFitScale(840, 320, 840, 3360);
      for (var i = 0; i < 20; i++) {
        expect(c.zoomBy(0.5), isTrue);
      }
      expect(c.scale, closeTo(fit, 1e-6));
    });
  });

  // Een sterk verticaal diagram raakt het interactieve (zoombare) pad.
  const tall =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 400">'
      '<rect width="10" height="10"/></svg>';

  Future<void> pumpDiagram(
    WidgetTester tester, {
    required MermaidViewController controller,
    required bool interactive,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MermaidRenderScope(
            scrollable: true,
            viewController: controller,
            interactive: interactive,
            child: MermaidDiagram(
              source: 'flowchart TD; A-->B',
              width: 1000,
              renderer: (_) async => tall,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('knoppen en spiegeling', () {
    testWidgets(
      'de presentator ziet zoomknoppen; inzoomen, uitzoomen en passend werken',
      (tester) async {
        final view = MermaidViewController();
        addTearDown(view.dispose);
        await pumpDiagram(tester, controller: view, interactive: true);

        expect(find.byTooltip('Inzoomen'), findsOneWidget);
        expect(find.byTooltip('Uitzoomen'), findsOneWidget);
        expect(view.scale, 1.0);

        await tester.tap(find.byTooltip('Inzoomen'));
        await tester.pumpAndSettle();
        expect(view.scale, greaterThan(1.0));

        // Uitzoomen mag nu voorbij 1 (het hoge diagram is op leesbare breedte
        // groter dan het venster), tot onder 1 (#944).
        await tester.tap(find.byTooltip('Uitzoomen'));
        await tester.tap(find.byTooltip('Uitzoomen'));
        await tester.tap(find.byTooltip('Uitzoomen'));
        await tester.pumpAndSettle();
        expect(view.scale, lessThan(1.0));

        // Passend maken: in één klik naar de passend-maat, het hele diagram in
        // beeld. Voor een diagram dat te hoog is, is die factor < 1.
        await tester.tap(find.byTooltip('Zoom resetten'));
        await tester.pumpAndSettle();
        expect(
          view.scale,
          lessThan(1.0),
          reason: 'passend maken toont het hele diagram, dus verkleind (#944)',
        );
        // En het hele diagram past nu verticaal: schaal · kindhoogte ≤ venster.
        // (kindhoogte 3360 op breedte 1000, venster 320 → passend ≈ 0.095.)
        expect(view.scale, closeTo(320 / 3360, 0.02));
      },
    );

    testWidgets('na de layout zoomt de toetsenbord-zoom (zoomBy) mee', (
      tester,
    ) async {
      final view = MermaidViewController();
      addTearDown(view.dispose);
      // Vóór enige layout kent de controller nog geen maten.
      expect(view.zoomBy(1.25), isFalse);

      await pumpDiagram(tester, controller: view, interactive: true);
      // De layout heeft de venster- en kindmaat aan de controller doorgegeven,
      // dus nu doet de toetsenbord-zoom hetzelfde als de knop.
      expect(view.zoomBy(1.25), isTrue);
      await tester.pumpAndSettle();
      expect(view.scale, greaterThan(1.0));

      final zoomedIn = view.scale;
      expect(view.zoomBy(0.8), isTrue);
      await tester.pumpAndSettle();
      expect(view.scale, lessThan(zoomedIn));
    });

    testWidgets('het publieksvenster toont geen knoppen en spiegelt de zoom', (
      tester,
    ) async {
      final view = MermaidViewController();
      addTearDown(view.dispose);
      // interactive:false = de beamer: geen knoppen, alleen meespiegelen.
      await pumpDiagram(tester, controller: view, interactive: false);
      expect(find.byTooltip('Inzoomen'), findsNothing);

      final before = tester.getRect(find.byType(SvgPicture)).width;
      view.set(scale: 2.0, fx: 0.0, fy: 0.0);
      await tester.pumpAndSettle();
      final after = tester.getRect(find.byType(SvgPicture)).width;
      // De gespiegelde zoomfactor 2 verdubbelt de getekende breedte.
      expect(after, closeTo(before * 2, 2));
    });

    testWidgets('passend maken verkleint het diagram écht tot het past (#944)', (
      tester,
    ) async {
      // Deze toets meet de gerénderde maat, niet slechts de opgeslagen zoom:
      // dát was het gat waardoor de eerste poging "groen" was maar de app niet
      // uitzoomde (InteractiveViewer klemde de min-zoom terug).
      final view = MermaidViewController();
      addTearDown(view.dispose);
      await pumpDiagram(tester, controller: view, interactive: true);

      // Op de leesbare standaard is het diagram hoger dan het venster (320).
      final full = tester.getRect(find.byType(SvgPicture)).height;
      expect(full, greaterThan(320));

      await tester.tap(find.byTooltip('Zoom resetten'));
      await tester.pumpAndSettle();
      final fitted = tester.getRect(find.byType(SvgPicture)).height;

      // Nu kleiner én binnen de vensterhoogte: het hele diagram past.
      expect(fitted, lessThan(full));
      expect(fitted, lessThanOrEqualTo(320 + 1));
    });
  });
}
