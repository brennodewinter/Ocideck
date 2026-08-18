import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/menu.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/menu_blocks.dart';

// Fase 3 van #1162: het keuze-menu-diatype. De blokken leven als link-bullets;
// dit toetst dat parse↔format en de volledige markdown-round-trip niets verliezen.
void main() {
  group('parseMenuBlock', () {
    test('leest label + doelanker uit een link', () {
      final b = parseMenuBlock('[Prijzen](#prijzen)');
      expect(b.label, 'Prijzen');
      expect(b.targetAnchor, 'prijzen');
      expect(b.hasImage, isFalse);
    });

    test('leest een optionele afbeelding erbij', () {
      final b = parseMenuBlock('[Demo](#demo) ![](mem:9f2a1c)');
      expect(b.label, 'Demo');
      expect(b.targetAnchor, 'demo');
      expect(b.imagePath, 'mem:9f2a1c');
    });

    test('een blok zonder link is een gewoon tekstblok', () {
      final b = parseMenuBlock('Gewoon een kop');
      expect(b.label, 'Gewoon een kop');
      expect(b.hasTarget, isFalse);
      expect(b.hasImage, isFalse);
    });
  });

  group('menuBlockToBullet', () {
    test('is de inverse van parseMenuBlock', () {
      for (final block in const [
        MenuBlock(label: 'Prijzen', targetAnchor: 'prijzen'),
        MenuBlock(label: 'Demo', targetAnchor: 'demo', imagePath: 'mem:x'),
        MenuBlock(label: 'Platte tekst'),
      ]) {
        expect(parseMenuBlock(menuBlockToBullet(block)), block);
      }
    });
  });

  group('uitleg per blok', () {
    test('leest de tekst achter het gedachtestreepje als uitleg', () {
      final b = parseMenuBlock('[Prijzen](#prijzen) — Wat het kost');
      expect(b.label, 'Prijzen');
      expect(b.description, 'Wat het kost');
      expect(b.targetAnchor, 'prijzen');
    });

    test('een gewoon streepje of dubbele punt telt ook', () {
      expect(parseMenuBlock('[A](#a) - Uitleg').description, 'Uitleg');
      expect(parseMenuBlock('[A](#a): Uitleg').description, 'Uitleg');
    });

    test('splitst ook zonder link, en blijft dan stabiel', () {
      final b = parseMenuBlock('Kop — Uitleg');
      expect(b.label, 'Kop');
      expect(b.description, 'Uitleg');
      // Een tweede rondgang mag er niets meer aan veranderen.
      expect(parseMenuBlock(menuBlockToBullet(b)), b);
    });

    test('uitleg en afbeelding samen raken elkaar niet kwijt', () {
      final b = parseMenuBlock('[Demo](#demo) — Kijk mee ![](mem:9f2a1c)');
      expect(b.label, 'Demo');
      expect(b.description, 'Kijk mee');
      expect(b.imagePath, 'mem:9f2a1c');
      expect(menuBlockToBullet(b), '[Demo](#demo) — Kijk mee ![](mem:9f2a1c)');
    });
  });

  group('categorieën', () {
    List<String> bullets() => [
      groupHeadingBullet('Producten'),
      '[Prijzen](#prijzen)',
      '[Demo](#demo)',
      groupHeadingBullet('Over ons'),
      '[Team](#team)',
    ];

    test('groepeert de blokken onder hun tussenkop', () {
      final cats = menuCategoriesFor(bullets());
      expect(cats.map((c) => c.label), ['Producten', 'Over ons']);
      expect(cats[0].blocks.map((b) => b.label), ['Prijzen', 'Demo']);
      expect(cats[1].blocks.map((b) => b.label), ['Team']);
    });

    test('zonder tussenkop is er één naamloze categorie en geen balk', () {
      final cats = menuCategoriesFor(['[A](#a)', '[B](#b)']);
      expect(cats, hasLength(1));
      expect(cats.first.isNamed, isFalse);
      expect(menuHasCategories(cats), isFalse);
    });

    test('blokken vóór de eerste tussenkop krijgen een eigen groep', () {
      final cats = menuCategoriesFor([
        '[Los](#los)',
        groupHeadingBullet('Rest'),
        '[B](#b)',
      ]);
      expect(cats, hasLength(2));
      expect(cats.first.isNamed, isFalse);
      expect(cats.first.blocks.single.label, 'Los');
      expect(menuHasCategories(cats), isTrue);
    });

    test('menuBlocksFor slaat de tussenkoppen over', () {
      expect(menuBlocksFor(bullets()).map((b) => b.label), [
        'Prijzen',
        'Demo',
        'Team',
      ]);
    });

    test('menuBulletsFrom is de inverse van menuCategoriesFor', () {
      expect(menuBulletsFrom(menuCategoriesFor(bullets())), bullets());
    });

    test('een doel zetten laat de tussenkoppen staan', () {
      final slides = [
        Slide.create(SlideType.menu).copyWith(bullets: bullets()),
        Slide.create(SlideType.bullets).copyWith(title: 'Team'),
      ];
      // Blok 2 is 'Team' — de derde bullet ná de koppen, niet de derde bullet.
      final out = slidesWithMenuTarget(slides, 0, 2, 1)!;
      expect(out[0].bullets.where(isGroupHeading), hasLength(2));
      expect(menuBlocksFor(out[0].bullets)[2].targetAnchor, out[1].anchor);
      expect(out[1].anchor, isNotEmpty);
    });
  });

  test('indeling en categorieën round-trippen door de markdown', () {
    final md = MarkdownService();
    final deck = Deck(
      title: 'Demo',
      slides: [
        Slide.create(SlideType.menu).copyWith(
          title: 'Kies een onderwerp',
          menuLayout: MenuLayout.circle,
          bullets: [
            groupHeadingBullet('Producten'),
            '[Prijzen](#prijzen) — Wat het kost',
          ],
        ),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Prijzen', anchor: 'prijzen', bullets: ['x']),
      ],
    );

    final back = md.parseDeck(md.generateDeck(deck))!;
    expect(back.slides[0].type, SlideType.menu);
    expect(back.slides[0].menuLayout, MenuLayout.circle);
    expect(back.slides[0].bullets, deck.slides[0].bullets);
    final cats = menuCategoriesFor(back.slides[0].bullets);
    expect(cats.single.label, 'Producten');
    expect(cats.single.blocks.single.description, 'Wat het kost');
  });

  test('een raster-menu schrijft geen indelingstoken weg', () {
    final md = MarkdownService();
    final out = md.generateDeck(
      Deck(
        title: 'Demo',
        slides: [
          Slide.create(SlideType.menu).copyWith(bullets: ['[A](#a)']),
        ],
      ),
    );
    expect(out, contains('_class: menu'));
    expect(out, isNot(contains('menu-grid')));
  });

  test('een menudia round-trippt verliesvrij door de markdown', () {
    final md = MarkdownService();
    final deck = Deck(
      title: 'Demo',
      slides: [
        Slide.create(SlideType.menu).copyWith(
          title: 'Kies een onderwerp',
          anchor: 'hoofdmenu',
          bullets: [
            '[Prijzen](#prijzen)',
            '[Demo](#demo) ![](mem:9f2a1c)',
            'Platte tekst',
          ],
        ),
        Slide.create(
          SlideType.bullets,
        ).copyWith(title: 'Prijzen', anchor: 'prijzen', bullets: ['x']),
      ],
    );

    final back = md.parseDeck(md.generateDeck(deck))!;

    expect(
      back.slides[0].type,
      SlideType.menu,
      reason: 'type overleeft herladen',
    );
    expect(back.slides[0].bullets, deck.slides[0].bullets);
    final blocks = menuBlocksFor(back.slides[0].bullets);
    expect(blocks[0].targetAnchor, 'prijzen');
    expect(blocks[1].imagePath, 'mem:9f2a1c');
    expect(blocks[2].hasTarget, isFalse);
  });
}
