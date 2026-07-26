import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/slides/mermaid_diagram.dart';

/// [MermaidDiagram] is de enige plek waar een gerenderd diagram het scherm
/// bereikt, en de laatste zeef ervoor: wat de renderer teruggeeft gaat eerst
/// door `sanitizeMermaidSvg`. Wordt die stap overgeslagen, dan tekent de app
/// opmaak van buiten ongefilterd.
///
/// De renderer zelf draait op een verborgen WebView die onder `flutter test`
/// niet bestaat; die hangt nu aan de `renderer`-naad, zodat het gedrag van de
/// widget — zeven, kaderen, wachten, terugvallen — wél te toetsen is.
void main() {
  /// De opmaak zoals die op het scherm terechtkomt, uit de SVG-widget zelf.
  String renderedSvg(WidgetTester tester) {
    final picture = tester.widget<SvgPicture>(find.byType(SvgPicture));
    return (picture.bytesLoader as SvgStringLoader).provideSvg(null);
  }

  Future<void> pump(
    WidgetTester tester,
    String source,
    MermaidRenderer renderer, {
    double width = 800,
    bool scrollable = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MermaidRenderScope(
            scrollable: scrollable,
            child: MermaidDiagram(
              source: source,
              width: width,
              renderer: renderer,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  MermaidRenderer returns(String? svg) =>
      (_) async => svg;

  const goodSvg =
      '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10" height="10"/></svg>';

  testWidgets('een geldig diagram komt als SVG op het scherm, niet als code', (
    tester,
  ) async {
    await pump(tester, 'graph TD; A-->B;', returns(goodSvg));

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(renderedSvg(tester), contains('<rect'));
    // De brontekst is dan juist niet zichtbaar; die is de terugval.
    expect(find.text('graph TD; A-->B;'), findsNothing);
  });

  testWidgets('de SVG wordt geschoond voordat hij getekend wordt', (
    tester,
  ) async {
    // Opmaak zoals een kwaadaardige of kapotte renderer hem kan opleveren:
    // een script-element, een gebeurtenis-attribuut en een klikbare
    // javascript:-verwijzing.
    const vuil =
        '<svg xmlns="http://www.w3.org/2000/svg" onload="steel()">'
        '<script>alert(1)</script>'
        '<a href="javascript:alert(2)"><rect width="10" height="10"/></a>'
        '</svg>';
    await pump(tester, 'graph TD; A-->B;', returns(vuil));

    final svg = renderedSvg(tester);
    expect(svg, isNot(contains('<script')));
    expect(svg, isNot(contains('onload')));
    expect(svg, isNot(contains('javascript:')));
    // Maar de tekening zelf blijft staan: schonen is geen weggooien.
    expect(svg, contains('<rect'));
  });

  testWidgets('opmaak die geen SVG is valt terug op de brontekst', (
    tester,
  ) async {
    // `sanitizeMermaidSvg` weigert dit (geen <svg>), en dan hoort de gebruiker
    // zijn eigen diagramcode te zien in plaats van een leeg vlak.
    await pump(tester, 'graph TD; A-->B;', returns('<html>fout</html>'));

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text('graph TD; A-->B;'), findsOneWidget);
  });

  testWidgets('een mislukte render toont de brontekst', (tester) async {
    await pump(tester, 'sequenceDiagram\n  A->>B: hoi', returns(null));

    expect(find.byType(SvgPicture), findsNothing);
    expect(find.text('sequenceDiagram\n  A->>B: hoi'), findsOneWidget);
  });

  testWidgets('zolang de render loopt draait er een wachtindicator', (
    tester,
  ) async {
    final open = Completer<String?>();
    addTearDown(() {
      if (!open.isCompleted) open.complete(null);
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MermaidDiagram(
            source: 'graph TD; A-->B;',
            width: 800,
            renderer: (_) => open.future,
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    // Niet de terugval: die zou de code laten opflitsen bij élk diagram.
    expect(find.text('graph TD; A-->B;'), findsNothing);

    open.complete(goodSvg);
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('een gewijzigde bron wordt opnieuw gerenderd, een gelijke niet', (
    tester,
  ) async {
    final gevraagd = <String>[];
    Future<String?> renderer(String source) async {
      gevraagd.add(source);
      return '<svg xmlns="http://www.w3.org/2000/svg">'
          '<rect id="${gevraagd.length}" width="10" height="10"/></svg>';
    }

    Widget app(String source) => MaterialApp(
      home: Scaffold(
        body: MermaidDiagram(source: source, width: 800, renderer: renderer),
      ),
    );

    await tester.pumpWidget(app('graph TD; A-->B;'));
    await tester.pumpAndSettle();
    expect(gevraagd, ['graph TD; A-->B;']);
    expect(renderedSvg(tester), contains('id="1"'));

    // Zelfde bron, nieuwe build: geen tweede render, en het beeld blijft staan.
    await tester.pumpWidget(app('graph TD; A-->B;'));
    await tester.pumpAndSettle();
    expect(gevraagd, hasLength(1));
    expect(renderedSvg(tester), contains('id="1"'));

    // Andere bron: wél opnieuw, en het nieuwe beeld vervangt het oude.
    await tester.pumpWidget(app('graph LR; B-->C;'));
    await tester.pumpAndSettle();
    expect(gevraagd, ['graph TD; A-->B;', 'graph LR; B-->C;']);
    expect(renderedSvg(tester), contains('id="2"'));
  });

  testWidgets('het diagram schaalt mee met de breedte van de dia', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester, 'graph TD; A-->B;', returns(goodSvg), width: 1000);

    // De tekening krijgt 84% van de diabreedte; op vaste punten zou een brede
    // dia een postzegel opleveren en een smalle dia zou overlopen.
    expect(tester.widget<SvgPicture>(find.byType(SvgPicture)).width, 840);
  });

  const tall =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 100 400">'
      '<rect width="10" height="10"/></svg>';

  testWidgets('op een statisch oppervlak schaalt een hoge flowchart passend '
      'omlaag i.p.v. te scrollen (#868/#872)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Sterk verticaal diagram (breedte/hoogte = 0.25). Op een niet-scrollbaar
    // oppervlak (export/publiek) moet het hele diagram passen: begrensd op
    // maxH = 0.32·1000 = 320, met behoud van verhouding → breedte 80. Geen
    // scrollvenster.
    await pump(
      tester,
      'flowchart TD; A-->B',
      returns(tall),
      width: 1000,
      scrollable: false,
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    final pic = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(pic.height, closeTo(320, 0.5));
    expect(pic.width, closeTo(80, 0.5));
  });

  testWidgets('op een interactief oppervlak wordt een hoge flowchart scrollbaar '
      'op leesbare breedte (#872)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Zelfde hoge diagram, maar nu interactief (scrollable = true, de default).
    // In plaats van tot een postzegel te verkleinen blijft het op leesbare volle
    // breedte (maxW = 840) en krijgt het zijn natuurlijke hoogte (840/0.25 =
    // 3360), scrollbaar binnen een vast-hoog venster.
    await pump(tester, 'flowchart TD; A-->B', returns(tall), width: 1000);

    expect(find.byType(SingleChildScrollView), findsOneWidget);
    final pic = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(pic.width, closeTo(840, 0.5));
    expect(pic.height, closeTo(3360, 1));
  });

  testWidgets('het scrollvenster scrolt het diagram ook echt (#872)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 2000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(tester, 'flowchart TD; A-->B', returns(tall), width: 1000);

    // De onderkant van het (te hoge) diagram zit vóór het scrollen ver onder de
    // rand; na omhoog slepen schuift de tekening zichtbaar mee omhoog.
    final before = tester.getTopLeft(find.byType(SvgPicture)).dy;
    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();
    final after = tester.getTopLeft(find.byType(SvgPicture)).dy;
    expect(after, lessThan(before - 100));
  });

  testWidgets('een breed, laag diagram houdt zijn natuurlijke maat (#868)', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Breedte/hoogte = 4: natuurlijke hoogte op breedte 840 is 210, ruim onder
    // het plafond, dus geen omlaagschaling.
    const wide =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 100">'
        '<rect width="10" height="10"/></svg>';
    await pump(tester, 'flowchart LR; A-->B', returns(wide), width: 1000);

    final pic = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(pic.width, closeTo(840, 0.5));
    expect(pic.height, closeTo(210, 0.5));
  });

  testWidgets('een zeer breed diagram (gantt) wordt horizontaal scrollbaar op '
      'leesbare hoogte (#895)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // Breedte/hoogte = 9 (zoals een gantt, ~1384×148): passend zou een dunne
    // strip zijn (hoogte 840/9 = 93, onder de leesbaarheidsvloer 0.16·1000 =
    // 160). Interactief tonen we het daarom op volle hoogte (maxH = 320) en
    // horizontaal scrollbaar → breedte 320·9 = 2880.
    const veryWide =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 100">'
        '<rect width="10" height="10"/></svg>';
    await pump(tester, 'gantt title X', returns(veryWide), width: 1000);

    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.scrollDirection, Axis.horizontal);
    final pic = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(pic.height, closeTo(320, 0.5));
    expect(pic.width, closeTo(2880, 1));
  });

  testWidgets('een zeer breed diagram blijft passend op een statisch oppervlak '
      '(#895)', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const veryWide =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 900 100">'
        '<rect width="10" height="10"/></svg>';
    // Statisch (export/publiek): geen scroll, passend → volle breedte 840,
    // natuurlijke (dunne) hoogte 93.
    await pump(
      tester,
      'gantt title X',
      returns(veryWide),
      width: 1000,
      scrollable: false,
    );

    expect(find.byType(SingleChildScrollView), findsNothing);
    final pic = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(pic.width, closeTo(840, 0.5));
    expect(pic.height, closeTo(93.3, 0.5));
  });
}
