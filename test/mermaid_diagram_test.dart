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
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MermaidDiagram(
            source: source,
            width: width,
            renderer: renderer,
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
}
