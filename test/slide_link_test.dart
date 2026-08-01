import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

// Links in slides: een link in slide-tekst hoort de callback aan te roepen die
// hem (in de app) extern opent. Dit toetst de bedrading van de slide-render tot
// de tik-afhandeling — het ontbreken ervan was waarom links in slides niets
// deden op sommige oppervlakken.
void main() {
  Widget host(Slide slide, void Function(String)? onLinkTap) => MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: 800,
          height: 450,
          child: SlidePreviewWidget(slide: slide, onLinkTap: onLinkTap),
        ),
      ),
    ),
  );

  testWidgets('een link in een bullet roept onLinkTap met de URL aan', (
    tester,
  ) async {
    String? tapped;
    final slide = Slide.create(SlideType.bullets).copyWith(
      title: 'Bronnen',
      bullets: const ['Zie [de site](https://voorbeeld.example) voor meer.'],
    );
    await tester.pumpWidget(host(slide, (url) => tapped = url));
    await tester.pump();

    await tester.tapOnText(find.textRange.ofSubstring('de site'));
    await tester.pump();
    expect(tapped, 'https://voorbeeld.example');
  });

  testWidgets('zonder onLinkTap crasht een link in een slide niet', (
    tester,
  ) async {
    // De thumbnail- en export-paden geven bewust geen onLinkTap door; een link
    // hoort daar simpelweg niet-klikbaar te zijn, niet te ontploffen.
    final slide = Slide.create(SlideType.bullets).copyWith(
      bullets: const ['Zie [de site](https://voorbeeld.example) voor meer.'],
    );
    await tester.pumpWidget(host(slide, null));
    await tester.pump();
    await tester.tapOnText(find.textRange.ofSubstring('de site'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
