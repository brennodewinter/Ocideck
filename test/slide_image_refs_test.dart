import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/slide_image_refs.dart';

/// De centrale helper die de vraag "welke afbeeldingen gebruikt deze dia"
/// beantwoordt. Hij is de enige plek waar het antwoord staat, dus een fout hier
/// plant zich voort naar de sweep, de opruimer en de export tegelijk.
void main() {
  Slide slideWith({
    String imagePath = '',
    String imagePath2 = '',
    String customMarkdown = '',
  }) => Slide.create(SlideType.freeMarkdown).copyWith(
    imagePath: imagePath,
    imagePath2: imagePath2,
    customMarkdown: customMarkdown,
  );

  group('slideImageRefs', () {
    test('geeft de velden en daarna de tekst, in leesvolgorde', () {
      final refs = slideImageRefs(
        slideWith(
          imagePath: 'images/een.png',
          imagePath2: 'images/twee.png',
          customMarkdown: 'Tekst ![alt drie](images/drie.png) meer tekst.',
        ),
      );

      expect(refs.map((r) => r.path), [
        'images/een.png',
        'images/twee.png',
        'images/drie.png',
      ]);
      expect(refs.map((r) => r.slot), [
        SlideImageSlot.image,
        SlideImageSlot.image2,
        SlideImageSlot.inline,
      ]);
      expect(refs.last.alt, 'alt drie');
    });

    test('een leeg veld is geen verwijzing', () {
      expect(slideImageRefs(slideWith(imagePath: '   ')), isEmpty);
    });

    test('meerdere afbeeldingen in dezelfde tekst komen alle mee', () {
      final paths = slideImagePaths(
        slideWith(customMarkdown: '![a](een.png)\n\n![b](twee.png)\n'),
      );
      expect(paths, ['een.png', 'twee.png']);
    });

    test('inlineImagePaths leest de maatvoering als gewone alt-tekst', () {
      expect(inlineImagePaths('![w:600 h:400](foto.png)'), ['foto.png']);
    });
  });

  group('rewriteInlineImagePaths', () {
    test('vervangt alleen het pad en laat de alt-tekst staan', () {
      final out = rewriteInlineImagePaths(
        'Zie ![w:600 mijn foto](oud.png) hier.',
        (path) => path == 'oud.png' ? 'images/nieuw.png' : null,
      );
      expect(out, 'Zie ![w:600 mijn foto](images/nieuw.png) hier.');
    });

    test('null laat de verwijzing onaangeroerd', () {
      const md = '![a](een.png) en ![b](twee.png)';
      expect(
        rewriteInlineImagePaths(md, (path) => path == 'een.png' ? 'X' : null),
        '![a](X) en ![b](twee.png)',
      );
    });
  });

  group('rewriteSlideImagePaths', () {
    test('herschrijft de velden én de tekst', () {
      final out = rewriteSlideImagePaths(
        slideWith(
          imagePath: 'a.png',
          imagePath2: 'b.png',
          customMarkdown: 'x ![alt](c.png) y',
        ),
        (path) => 'images/$path',
      );

      expect(out.imagePath, 'images/a.png');
      expect(out.imagePath2, 'images/b.png');
      expect(out.customMarkdown, 'x ![alt](images/c.png) y');
    });

    test('geeft dezelfde dia terug als er niets te herschrijven valt', () {
      final slide = slideWith(
        imagePath: 'a.png',
        customMarkdown: '![x](c.png)',
      );
      expect(
        identical(rewriteSlideImagePaths(slide, (_) => null), slide),
        true,
      );
    });
  });
}
