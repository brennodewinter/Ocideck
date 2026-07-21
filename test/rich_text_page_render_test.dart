import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/rich_text_layout.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Hoe een vrije-tekstslide met meerdere pagina's op de dia zelf terechtkomt.
///
/// Twee dingen die met elkaar te maken hebben: er staat géén paginateller meer
/// op de dia (die telde per slide opnieuw vanaf één, terwijl de zaal naar dia 7
/// van 24 kijkt), en de vervolgpagina's zijn niet langer onbereikbaar voor een
/// oppervlak dat slides opsomt in plaats van doorbladert — de export.
Widget _host(Slide slide) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Center(
      child: SizedBox(
        width: 800,
        height: 450,
        child: SlidePreviewWidget(slide: slide),
      ),
    ),
  );
}

/// Een vrije-tekstslide met genoeg genummerde alinea's om te pagineren; elke
/// alinea is uniek, zodat een test kan zien wélke pagina er gerenderd wordt.
Slide _richSlide(int paras) => Slide.create(SlideType.bullets).copyWith(
  title: 'Titel',
  listStyle: ListStyle.richText,
  customMarkdown: List.generate(
    paras,
    (i) => 'Alinea $i met wat tekst om hoogte op te bouwen.',
  ).join('\n\n'),
);

void main() {
  const profile = ThemeProfile();

  testWidgets('a multi-page rich-text slide shows no page counter', (
    tester,
  ) async {
    final slide = _richSlide(40);
    final pages = richTextPageCountForSlide(slide: slide, profile: profile);
    expect(pages, greaterThan(1), reason: 'testopzet: moet pagineren');

    await tester.pumpWidget(_host(slide));

    // Precies het label dat er stond. Niet "geen enkele tekst met een schuine
    // streep": een dia mag "3 / 4" in zijn eigen inhoud hebben staan.
    expect(find.text('1 / $pages'), findsNothing);
  });

  testWidgets('renderPage draws the continuation page, not the first', (
    tester,
  ) async {
    final slide = _richSlide(40);
    final expanded = expandRichTextForRender([slide], profile);
    expect(
      expanded.length,
      greaterThan(1),
      reason: 'testopzet: moet pagineren',
    );

    await tester.pumpWidget(_host(expanded.first));
    expect(
      find.textContaining('Alinea 0 ', findRichText: true),
      findsOneWidget,
    );

    await tester.pumpWidget(_host(expanded[1]));
    expect(find.textContaining('Alinea 0 ', findRichText: true), findsNothing);
    // De titel hoort alleen op de eerste pagina; een vervolgpagina die hem
    // herhaalt leest als een nieuwe dia in plaats van als vervolg.
    expect(find.textContaining('Titel', findRichText: true), findsNothing);
  });

  testWidgets('an image in the text is drawn, not printed as markdown', (
    tester,
  ) async {
    final slide = Slide.create(SlideType.bullets).copyWith(
      listStyle: ListStyle.richText,
      customMarkdown:
          'Kijk hiernaar:\n\n![De grafiek](images/grafiek.png)\n\nEinde.',
    );
    await tester.pumpWidget(_host(slide));

    // De rauwe markdown hoort niet als tekst op de dia te staan.
    expect(
      find.textContaining('![De grafiek]', findRichText: true),
      findsNothing,
    );
    // De tekst eromheen blijft gewoon staan.
    expect(find.textContaining('Kijk hiernaar', findRichText: true), findsOne);
    expect(find.textContaining('Einde.', findRichText: true), findsOne);
  });

  test('an image block reserves height, so it changes the page count', () {
    // Als de paginering het afbeeldingsvak niet meerekent, past er te veel op
    // een pagina en loopt de dia over de onderrand.
    Slide withBody(String body) => Slide.create(
      SlideType.bullets,
    ).copyWith(listStyle: ListStyle.richText, customMarkdown: body);

    final paragraphs = List.generate(
      12,
      (i) => 'Alinea $i met wat tekst om hoogte op te bouwen.',
    ).join('\n\n');
    final withImages = List.generate(
      12,
      (i) =>
          'Alinea $i met wat tekst om hoogte op te bouwen.\n\n'
          '![plaat $i](images/plaat$i.png)',
    ).join('\n\n');

    expect(
      richTextPageCountForSlide(slide: withBody(withImages), profile: profile),
      greaterThan(
        richTextPageCountForSlide(
          slide: withBody(paragraphs),
          profile: profile,
        ),
      ),
    );
  });
}
