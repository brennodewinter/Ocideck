import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  final markdown = MarkdownService();
  Slide reopen(Slide slide) => markdown
      .parseDeck(
        markdown.generateDeck(Deck(title: 'Caption slots', slides: [slide])),
      )!
      .slides
      .single;

  for (final type in [SlideType.twoImages, SlideType.title]) {
    for (final captions in [
      ('', 'Right | caption'),
      ('Left', ''),
      ('Left', 'Right'),
    ]) {
      test('$type preserves caption slots $captions on repeated saves', () {
        var slide = Slide.create(type).copyWith(
          title: 'Two images',
          imagePath: 'left.png',
          imagePath2: 'right.png',
          titleColumnLayout: type == SlideType.title
              ? TitleColumnLayout.both
              : TitleColumnLayout.none,
          imageCaption: captions.$1,
          imageCaption2: captions.$2,
        );
        for (var save = 0; save < 2; save++) {
          slide = reopen(slide);
          expect(slide.imageCaption, captions.$1);
          expect(slide.imageCaption2, captions.$2);
        }
      });
    }
  }
  test('logo opt-out survives a profile without a logo', () {
    var slide = Slide.create(SlideType.bullets).copyWith(showLogo: false);
    for (var save = 0; save < 2; save++) {
      slide = reopen(slide);
      expect(slide.showLogo, isFalse);
    }
  });
}
