import 'package:ocideck/models/slide.dart';

/// Een dia van [type] met het minimum aan inhoud dat hem herkenbaar maakt.
///
/// Types zónder eigen `_class`-token (bullets, image, twoImages, freeMarkdown)
/// worden aan hun inhoud herkend; die krijgen hier precies wat de heuristiek
/// nodig heeft. De rest draagt zijn token en heeft alleen inhoud nodig die niet
/// leeg is.
///
/// Staat apart omdat twee uitputtende tests dezelfde vraag stellen vanaf een
/// andere kant: `markdown_round_trip_test.dart` of elk type als zichzelf
/// terugkomt uit de markdown, en `slide_rasterizer_test.dart` of elk type ook
/// werkelijk iets tékent (#615). Eén lijst, want twee lijsten lopen uiteen —
/// en dan dekt de ene een type dat de andere stilzwijgend overslaat.
Slide slideMetInhoud(SlideType type) {
  final basis = Slide.create(type);
  return switch (type) {
    SlideType.bullets => basis.copyWith(title: 'T', bullets: const ['Punt']),
    SlideType.twoBullets => basis.copyWith(
      title: 'T',
      bullets: const ['Links'],
      bullets2: const ['Rechts'],
    ),
    SlideType.bulletsImage => basis.copyWith(
      title: 'T',
      bullets: const ['Punt'],
      imagePath: 'images/a.png',
    ),
    SlideType.image => basis.copyWith(imagePath: 'images/a.png'),
    SlideType.twoImages => basis.copyWith(
      imagePath: 'images/a.png',
      imagePath2: 'images/b.png',
    ),
    SlideType.video => basis.copyWith(videoPath: 'media/film.mp4'),
    SlideType.quote => basis.copyWith(
      quote: 'Zo gaat dat',
      quoteAuthor: 'N.N.',
    ),
    SlideType.freeMarkdown => basis.copyWith(
      customMarkdown: 'Vrije **tekst** zonder kop.',
    ),
    SlideType.code => basis.copyWith(
      codeLanguage: 'dart',
      customMarkdown: 'void main() {}',
    ),
    SlideType.title ||
    SlideType.section => basis.copyWith(title: 'T', subtitle: 'S'),
    // Menu (#1162): de blokken leven als link-bullets in [Slide.bullets], niet
    // in de body uit Slide.create. Eén blok `[label](#anker)` maakt de dia
    // herkenbaar én laat de golden meer tonen dan alleen de titel.
    SlideType.menu => basis.copyWith(
      title: 'T',
      bullets: const ['[Naar deel twee](#deel-twee)'],
    ),
    // De overige types dragen hun token én een gevulde body uit Slide.create.
    _ => basis.copyWith(title: 'T'),
  };
}
