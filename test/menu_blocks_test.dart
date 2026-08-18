import 'dart:math' as math;

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

  group('tekst past in de hoogte die er is', () {
    // De regressie uit de beeldkeuring: bij de indeling "onder elkaar" liep de
    // tekst buiten zijn vak en werd hij weggeknipt — de bovenste helft van elk
    // label was er gewoon af, zonder ellips. Wegknippen is geen overloop, dus
    // geen enkele test viel erover. Deze wel: wat [menuTextFit] toewijst, moet
    // in de opgegeven hoogte passen.
    test('het toegewezen budget past altijd in de ruimte', () {
      for (var available = 2.0; available <= 400; available += 1) {
        for (final hasDescription in [true, false]) {
          final fit = menuTextFit(
            available: available,
            maxLabelSize: 25,
            hasDescription: hasDescription,
          );
          expect(
            fit.height,
            lessThanOrEqualTo(available + 0.001),
            reason:
                'bij $available px (uitleg: $hasDescription) vraagt de tekst '
                '${fit.height} px',
          );
        }
      }
    });

    test('er blijft altijd minstens één labelregel over', () {
      for (var available = 0.0; available <= 40; available += 0.5) {
        expect(
          menuTextFit(
            available: available,
            maxLabelSize: 25,
            hasDescription: true,
          ).labelLines,
          greaterThanOrEqualTo(1),
        );
      }
    });

    test('een ruime kaart houdt de volle lettergrootte', () {
      final fit = menuTextFit(
        available: 200,
        maxLabelSize: 25,
        hasDescription: true,
      );
      expect(fit.labelSize, 25);
      expect(fit.showsDescription, isTrue);
    });

    test(
      'een lage kaart laat de uitleg vallen en geeft het label de ruimte',
      () {
        // Op deze hoogte zou de uitleg tot een grijze veeg krimpen. Dan valt hij
        // weg — en gaat de ruimte die vrijkomt naar het label, niet verloren.
        final krap = menuTextFit(
          available: 18,
          maxLabelSize: 25,
          hasDescription: true,
        );
        expect(krap.showsDescription, isFalse);
        expect(
          krap.labelLines,
          menuTextFit(
            available: 18,
            maxLabelSize: 25,
            hasDescription: false,
          ).labelLines,
          reason: 'zonder leesbare uitleg telt het label alsof er geen was',
        );

        // En op een ruime kaart blijft de uitleg gewoon staan.
        expect(
          menuTextFit(
            available: 80,
            maxLabelSize: 25,
            hasDescription: true,
          ).showsDescription,
          isTrue,
        );
      },
    );

    test('zonder uitleg krijgt het label de regels die overblijven', () {
      final fit = menuTextFit(
        available: 100,
        maxLabelSize: 25,
        hasDescription: false,
      );
      expect(fit.labelLines, greaterThan(1));
      expect(fit.descriptionLines, 0);
    });
  });

  group('cirkelindeling', () {
    // De maat van een schijf volgt uit de meetkunde van de ring; deze proef
    // bewaakt dat twee buren elkaar bij geen enkel aantal blokken raken.
    test('schijven raken elkaar niet, van twee tot dertig blokken', () {
      for (var n = 2; n <= 30; n++) {
        final disc = menuDiscFraction(n);
        final chord = 2 * menuRingRadius(n) * math.sin(math.pi / n);
        expect(
          disc,
          lessThan(chord),
          reason: 'bij $n blokken past een schijf van $disc niet in $chord',
        );
      }
    });

    test('de ring past binnen het vlak', () {
      for (var n = 1; n <= 30; n++) {
        expect(
          2 * menuRingRadius(n) + menuDiscFraction(n),
          lessThanOrEqualTo(1),
        );
      }
    });

    test('de focusring van een schijf past in de lucht tussen twee buren', () {
      // De ring hangt buiten de schijf. Bij een volle ring is de lucht daar
      // krap: twaalf schijven op een dia van 1280 stonden 98 px uit elkaar met
      // een doorsnede van 84, en een ring van 19 px lag over de buren heen
      // (#1162, derde beeldkeuring).
      const side = 500.0;
      for (var n = 2; n <= 30; n++) {
        final gebruikt =
            menuDiscRingWidth(side: side, n: n, maxWidth: 10) * 1.9;
        final lucht =
            2 * side * menuRingRadius(n) * math.sin(math.pi / n) -
            side * menuDiscFraction(n);
        expect(
          gebruikt,
          lessThanOrEqualTo(lucht),
          reason:
              'bij $n schijven vraagt de ring $gebruikt px terwijl er $lucht '
              'px lucht is',
        );
      }
    });

    test('bij weinig schijven blijft de ring op zijn volle dikte', () {
      expect(menuDiscRingWidth(side: 500, n: 3, maxWidth: 10), 10);
    });

    test('één blok staat in het midden', () {
      expect(menuRingRadius(1), 0);
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
