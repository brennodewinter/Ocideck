import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/marp_style.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';

void main() {
  final markdown = MarkdownService();

  group('MarpStyle contract', () {
    test('explicit empty overrides an inherited value', () {
      const inherited = MarpStyle(header: 'Deckkop', color: '#123456');
      const local = MarpStyle(header: '');
      final effective = local.inherit(inherited);

      expect(effective.header, isEmpty);
      expect(effective.color, '#123456');
      expect(local.hasHeader, isTrue);
      expect(const MarpStyle().hasHeader, isFalse);
      expect(MarpStyle.fromJson(local.toJson()), local);
    });

    test('present JSON fields are type checked instead of ignored', () {
      expect(() => MarpStyle.fromJson({'header': 1}), throwsFormatException);
      expect(
        () => MarpStyle.fromJson({
          'imageFilters': ['blur:2px', 1],
        }),
        throwsFormatException,
      );
      expect(
        () => MarpStyle.fromJson({'headingFit': 'true'}),
        throwsFormatException,
      );
    });

    test('an explicitly empty local directive survives Markdown', () {
      const source = '''
---
marp: true
header: Deckkop
---

<!-- _header: -->

# Kop
''';

      final deck = markdown.parseDeck(source)!;
      expect(deck.slides.single.marpStyle.hasHeader, isTrue);
      expect(deck.slides.single.marpStyle.header, isEmpty);
      expect(
        deck.slides.single.marpStyle.inherit(deck.marpStyle).header,
        isEmpty,
      );

      final saved = markdown.generateDeck(deck);
      expect(saved, contains('<!-- _header:  -->'));
      expect(
        markdown.parseDeck(saved)!.slides.single.marpStyle.hasHeader,
        isTrue,
      );
    });
  });

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

  test('unknown valid Marpit directives stay in their authored position', () {
    const source = '''
---
marp: true
---

# Voor

<!-- transition: fade -->

Na
''';

    final deck = markdown.parseDeck(source)!;
    expect(deck.slides.single.type, SlideType.freeMarkdown);
    final saved = markdown.generateDeck(deck);
    expect(saved, contains('# Voor\n\n<!-- transition: fade -->\n\nNa'));
    expect(markdown.generateDeck(markdown.parseDeck(saved)!), saved);
  });

  test('unsupported and layered backgrounds keep order and are idempotent', () {
    const source = '''
---
marp: true
---

![bg left:33% opacity:.7](images/links.png)
![bg right:67%](images/rechts.png)

# Kop
''';

    final deck = markdown.parseDeck(source)!;
    expect(deck.slides.single.type, SlideType.freeMarkdown);
    final saved = markdown.generateDeck(deck);
    expect(
      saved.indexOf('images/links.png'),
      lessThan(saved.indexOf('images/rechts.png')),
    );
    expect(saved, contains('![bg left:33% opacity:.7](images/links.png)'));
    expect(markdown.generateDeck(markdown.parseDeck(saved)!), saved);
  });

  test('multiple and non-first heading fits keep exact placement', () {
    const source = '''
---
marp: true
---

# Eerste

## Tweede
<!-- fit -->

### Derde
<!-- fit -->
''';

    final deck = markdown.parseDeck(source)!;
    expect(deck.slides.single.type, SlideType.freeMarkdown);
    final saved = markdown.generateDeck(deck);
    expect(saved, contains('## Tweede\n<!-- fit -->'));
    expect(saved, contains('### Derde\n<!-- fit -->'));
    expect(markdown.generateDeck(markdown.parseDeck(saved)!), saved);
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
