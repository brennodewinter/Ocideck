import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/gallery_layout.dart';
import 'package:ocideck/models/presentation_step_plan.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/slide_image_refs.dart';

/// Serialize a single slide to markdown and parse it straight back.
Slide _roundTrip(Slide slide) {
  final service = MarkdownService();
  final markdown = service.generateDeck(Deck(title: 'Demo', slides: [slide]));
  final deck = service.parseDeck(markdown);
  expect(deck, isNotNull, reason: 'parseDeck returned null for:\n$markdown');
  expect(
    deck!.slides,
    hasLength(1),
    reason: 'Expected exactly one slide from:\n$markdown',
  );
  return deck.slides.single;
}

void main() {
  group('imageGallery (#2838) — markdown rondgang', () {
    test('raster: entries en lay-out komen terug, zonder stack-token', () {
      final out = _roundTrip(
        Slide.create(SlideType.imageGallery).copyWith(
          title: 'Krantenkoppen',
          galleryImages: const [
            '![](media/nrc.png)',
            '![Volkskrant kop](media/vk.png)',
            '![](media/nu.png)',
          ],
          galleryLayout: GalleryLayout.grid,
        ),
      );
      expect(out.type, SlideType.imageGallery);
      expect(out.title, 'Krantenkoppen');
      expect(out.galleryLayout, GalleryLayout.grid);
      expect(out.galleryImages, hasLength(3));
      expect(out.galleryImages[1], '![Volkskrant kop](media/vk.png)');
    });

    test('stapel: gallery-stack-token schrijft en leest terug', () {
      final service = MarkdownService();
      final markdown = service.generateDeck(
        Deck(
          title: 'Demo',
          slides: [
            Slide.create(SlideType.imageGallery).copyWith(
              galleryImages: const ['![](a.png)', '![](b.png)'],
              galleryLayout: GalleryLayout.stack,
            ),
          ],
        ),
      );
      expect(markdown, contains('gallery-stack'));
      final out = _roundTrip(
        Slide.create(SlideType.imageGallery).copyWith(
          galleryImages: const ['![](a.png)', '![](b.png)'],
          galleryLayout: GalleryLayout.stack,
        ),
      );
      expect(out.galleryLayout, GalleryLayout.stack);
      expect(out.galleryImages, hasLength(2));
    });

    test('alt-tekst reist in de entry zelf mee', () {
      final out = _roundTrip(
        Slide.create(SlideType.imageGallery).copyWith(
          galleryImages: const ['![Foto van het team](team.jpg)'],
        ),
      );
      expect(out.galleryImages.single, '![Foto van het team](team.jpg)');
    });
  });

  group('imageGallery — stapplan', () {
    test('stapel met n beelden heeft n-1 stappen; stap 0 toont de eerste', () {
      final slide = Slide.create(SlideType.imageGallery).copyWith(
        galleryImages: const ['![](a)', '![](b)', '![](c)', '![](d)'],
        galleryLayout: GalleryLayout.stack,
      );
      final plan = PresentationStepPlan.forSlide(slide);
      expect(plan, isA<ImageStackStepPlan>());
      final sp = plan as ImageStackStepPlan;
      expect(sp.imageCount, 4);
      expect(sp.remainingSteps, 3);
      expect(sp.revealedImageCount(0), 1);
      expect(sp.revealedImageCount(3), 4);
      expect(sp.revealedImageCount(99), 4);
    });

    test('raster stapt niet — alles staat er meteen', () {
      final slide = Slide.create(SlideType.imageGallery).copyWith(
        galleryImages: const ['![](a)', '![](b)'],
        galleryLayout: GalleryLayout.grid,
      );
      expect(PresentationStepPlan.forSlide(slide), isA<NoStepPlan>());
    });

    test('lege stapel stapt niet', () {
      final slide = Slide.create(SlideType.imageGallery).copyWith(
        galleryLayout: GalleryLayout.stack,
      );
      expect(
        PresentationStepPlan.forSlide(slide).remainingSteps,
        0,
      );
    });
  });

  group('imageGallery — asset-reis via slideImageRefs', () {
    test('paden en alt-teksten zijn zichtbaar voor de verzamelaar', () {
      final slide = Slide.create(SlideType.imageGallery).copyWith(
        galleryImages: const [
          '![](media/nrc.png)',
          '![Kop](media/vk.png)',
        ],
      );
      final refs = slideImageRefs(slide).toList();
      expect(refs.map((r) => r.path), ['media/nrc.png', 'media/vk.png']);
      expect(refs.map((r) => r.slot), [
        SlideImageSlot.gallery,
        SlideImageSlot.gallery,
      ]);
      expect(refs[1].alt, 'Kop');
    });

    test('herschrijven verandert het pad en laat de alt-tekst staan', () {
      final slide = Slide.create(SlideType.imageGallery).copyWith(
        galleryImages: const ['![Kop](media/vk.png)', '![](media/nu.png)'],
      );
      final out = rewriteSlideImagePaths(
        slide,
        (p) => p == 'media/vk.png' ? 'media/archief/vk.png' : null,
      );
      expect(out.galleryImages, [
        '![Kop](media/archief/vk.png)',
        '![](media/nu.png)',
      ]);
    });
  });
}
