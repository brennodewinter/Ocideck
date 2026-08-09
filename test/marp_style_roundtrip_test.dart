import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  final markdown = MarkdownService();

  test('deck and spot style directives round-trip as standard Marp', () {
    const source = '''
---
marp: true
color: '#112233'
backgroundColor: '#fefefe'
backgroundImage: "url('images/deck.png')"
header: '**Deckkop**'
footer: 'Deckvoet'
---

<!-- _class: section -->
<!-- _color: #abcdef -->
<!-- _backgroundColor: #101010 -->
<!-- _backgroundImage: url('images/slide.png') -->
<!-- _header: *Diakop* -->
<!-- _footer: Diavoet -->

# Kop

Tekst
''';

    final deck = markdown.parseDeck(source)!;
    expect(
      deck.marpStyle,
      const MarpStyle(
        color: '#112233',
        backgroundColor: '#fefefe',
        backgroundImage: "url('images/deck.png')",
        header: '**Deckkop**',
        footer: 'Deckvoet',
      ),
    );
    expect(
      deck.slides.single.marpStyle,
      const MarpStyle(
        color: '#abcdef',
        backgroundColor: '#101010',
        backgroundImage: "url('images/slide.png')",
        header: '*Diakop*',
        footer: 'Diavoet',
      ),
    );

    final saved = markdown.generateDeck(deck);
    expect(saved, contains('color: "#112233"'));
    expect(saved, contains('backgroundColor: "#fefefe"'));
    expect(saved, contains('<!-- _color: #abcdef -->'));
    expect(saved, contains('<!-- _footer: Diavoet -->'));
    final reopened = markdown.parseDeck(saved)!;
    expect(reopened.marpStyle, deck.marpStyle);
    expect(reopened.slides.single.marpStyle, deck.slides.single.marpStyle);
  });

  test('background fit, filters and heading fit remain meaningful', () {
    const source = '''
---
marp: true
---

<!-- _class: section -->

![bg contain blur:2px brightness:1.2 grayscale](images/bg.png)

# Schaal mij
<!-- fit -->

Tekst
''';

    final deck = markdown.parseDeck(source)!;
    final slide = deck.slides.single;
    expect(slide.type, SlideType.section);
    expect(slide.imagePath, 'images/bg.png');
    expect(slide.marpStyle.imageFit, 'contain');
    expect(slide.marpStyle.imageFilters, [
      'blur:2px',
      'brightness:1.2',
      'grayscale',
    ]);
    expect(slide.marpStyle.headingFit, isTrue);

    final saved = markdown.generateDeck(deck);
    expect(
      saved,
      contains(
        '![bg contain blur:2px brightness:1.2 grayscale opacity:.45]'
        '(images/bg.png)',
      ),
    );
    expect(saved, contains('# Schaal mij\n<!-- fit -->'));
    final reopened = markdown.parseDeck(saved)!.slides.single;
    expect(reopened.marpStyle, slide.marpStyle);
  });

  test('edited deck style replaces preserved front matter values', () {
    const source = '''
---
marp: true
color: red
backgroundColor: white
backgroundImage: none
header: Oud
footer: Oude voet
---

# Kop
''';

    final deck = markdown.parseDeck(source)!;
    final saved = markdown.generateDeck(
      deck.copyWith(
        marpStyle: const MarpStyle(
          color: 'blue',
          backgroundColor: 'black',
          backgroundImage: "url('nieuw.png')",
          header: 'Nieuw',
          footer: 'Nieuwe voet',
        ),
      ),
    );

    final reopened = markdown.parseDeck(saved)!;
    expect(
      reopened.marpStyle,
      const MarpStyle(
        color: 'blue',
        backgroundColor: 'black',
        backgroundImage: "url('nieuw.png')",
        header: 'Nieuw',
        footer: 'Nieuwe voet',
      ),
    );
    expect(RegExp(r'^color:', multiLine: true).allMatches(saved), hasLength(1));
    expect(
      RegExp(r'^header:', multiLine: true).allMatches(saved),
      hasLength(1),
    );
  });
}
