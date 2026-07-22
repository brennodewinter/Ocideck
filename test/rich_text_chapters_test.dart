import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/rich_text_chapters.dart';

/// Een `#` midden in een vrije-tekstbody is in Marp geen opmaak maar een dia die
/// niet is afgesloten. Deze tests leggen vast wat "opknippen" dan precies doet —
/// en vooral wat het níet doet.
void main() {
  Slide richSlide(String body, {String title = '', String subtitle = ''}) =>
      Slide.create(SlideType.bullets).copyWith(
        listStyle: ListStyle.richText,
        title: title,
        subtitle: subtitle,
        customMarkdown: body,
      );

  group('richTextChapterHeadings', () {
    test('finds headings after the first content', () {
      const body =
          'Inleiding.\n\n# Eerste\n\nTekst.\n\n# Tweede\n\nMeer tekst.';
      expect(richTextChapterHeadings(body), ['Eerste', 'Tweede']);
    });

    test('a heading on the first line is the title, not a chapter', () {
      const body = '# Alleen de titel\n\nTekst eronder.';
      expect(richTextChapterHeadings(body), isEmpty);
    });

    test('ignores a hash inside a code fence', () {
      const body =
          'Inleiding.\n\n```bash\n# dit is een shell-commentaar\nls -la\n```\n\nEinde.';
      expect(richTextChapterHeadings(body), isEmpty);
    });

    test('a sub-heading is not a chapter', () {
      const body = 'Inleiding.\n\n## Een tussenkop\n\nTekst.';
      expect(richTextChapterHeadings(body), isEmpty);
    });
  });

  group('splitRichTextIntoChapters', () {
    test('splits into one slide per chapter, heading becomes the title', () {
      final out = splitRichTextIntoChapters(
        richSlide(
          'Inleiding.\n\n# Eerste\n\nTekst een.\n\n# Tweede\n\nTekst twee.',
          title: 'Bestaande titel',
        ),
      );
      expect(out, hasLength(3));
      expect(out[0].title, 'Bestaande titel');
      expect(out[0].customMarkdown, 'Inleiding.');
      expect(out[1].title, 'Eerste');
      expect(out[1].customMarkdown, 'Tekst een.');
      expect(out[2].title, 'Tweede');
      expect(out[2].customMarkdown, 'Tekst twee.');
    });

    test('the first slide keeps the original id, the rest are new', () {
      final slide = richSlide('Intro.\n\n# Kop\n\nTekst.');
      final out = splitRichTextIntoChapters(slide);
      // De annotaties en notities van de auteur hangen aan het id; de bestaande
      // dia moet dus de bestaande dia blijven.
      expect(out.first.id, slide.id);
      expect(out.map((s) => s.id).toSet(), hasLength(out.length));
    });

    test('a leading heading titles this slide instead of adding one', () {
      final out = splitRichTextIntoChapters(
        richSlide('# Hoofdstuk een\n\nTekst.'),
      );
      expect(out, hasLength(1));
      expect(out.single.title, 'Hoofdstuk een');
      expect(out.single.customMarkdown, 'Tekst.');
    });

    test('a sub-heading under a chapter becomes its subtitle', () {
      // Anders tilt de parser hem er bij het volgende inlezen alsnog uit, en
      // ziet de dia er na één keer opslaan anders uit dan direct na het knippen.
      final out = splitRichTextIntoChapters(
        richSlide('Intro.\n\n# Kop\n\n## Ondertitel\n\nTekst.'),
      );
      expect(out, hasLength(2));
      expect(out[1].title, 'Kop');
      expect(out[1].subtitle, 'Ondertitel');
      expect(out[1].customMarkdown, 'Tekst.');
    });

    test('leaves a body without chapters alone', () {
      final slide = richSlide('Gewoon wat tekst.\n\n## Een tussenkop\n\nMeer.');
      expect(splitRichTextIntoChapters(slide), [slide]);
    });

    test('a hash inside a code fence does not split', () {
      final slide = richSlide('Intro.\n\n```\n# geen kop\n```\n\nEinde.');
      expect(splitRichTextIntoChapters(slide), [slide]);
    });

    test('leaves other slide types alone', () {
      // Op een 'tekst met afbeelding'-dia hoort de afbeelding bij déze tekst;
      // waar hij bij het knippen heen moet, kan alleen de auteur beslissen.
      final withImage = Slide.create(SlideType.bulletsImage).copyWith(
        listStyle: ListStyle.richText,
        customMarkdown: 'Intro.\n\n# Kop\n\nTekst.',
        imagePath: 'images/foto.png',
      );
      expect(slideSplitsIntoChapters(withImage), isFalse);
      expect(splitRichTextIntoChapters(withImage), [withImage]);

      final bullets = Slide.create(
        SlideType.bullets,
      ).copyWith(bullets: const ['een', 'twee']);
      expect(splitRichTextIntoChapters(bullets), [bullets]);
    });

    test('the chapter count matches what the split produces', () {
      final slide = richSlide('Intro.\n\n# Een\n\nA.\n\n# Twee\n\nB.');
      expect(
        richTextChapterCount(slide),
        splitRichTextIntoChapters(slide).length,
      );
    });
  });
}
